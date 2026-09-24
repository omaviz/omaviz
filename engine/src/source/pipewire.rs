//! PipeWire capture backend: taps the default sink monitor and mixes to mono f32.
//! Ported from v6/daemon/src/capture.rs; adapted to spawn a thread + channel.

use crate::dsp::AudioChunk;
use anyhow::Result;
use pipewire as pw;
use pw::{properties::properties, spa};
use spa::param::format::{MediaSubtype, MediaType};
use spa::param::format_utils;
use spa::pod::Pod;
use std::convert::TryInto;
use std::sync::mpsc::Sender;

struct UserData {
    format: spa::param::audio::AudioInfoRaw,
    tx: Sender<AudioChunk>,
}

/// Runs the PipeWire main loop forever, pushing mono chunks to `tx`.
fn run_loop(tx: Sender<AudioChunk>) -> Result<()> {
    pw::init();
    let mainloop = pw::main_loop::MainLoopRc::new(None)?;
    let context = pw::context::ContextRc::new(&mainloop, None)?;
    let core = context.connect_rc(None)?;

    let mut props = properties! {
        *pw::keys::MEDIA_TYPE => "Audio",
        *pw::keys::MEDIA_CATEGORY => "Capture",
        *pw::keys::MEDIA_ROLE => "Music",
        *pw::keys::NODE_NAME => "omaviz-engine",
    };
    // Capture what the default sink is playing, whatever app produced it.
    props.insert(*pw::keys::STREAM_CAPTURE_SINK, "true");
    // NOTE: we rely on session-manager autoconnect (STREAM_CAPTURE_SINK).
    // Explicitly pinning `target.object` to the "<sink>.monitor" name linked
    // to a suspended/idle monitor node and produced silence; autoconnect
    // reliably delivers the sink's playback audio.

    let data = UserData {
        format: Default::default(),
        tx,
    };

    let stream = pw::stream::StreamBox::new(&core, "omaviz-capture", props)?;

    let _listener = stream
        .add_local_listener_with_user_data(data)
        .param_changed(|_, ud, id, param| {
            let Some(param) = param else { return };
            if id != spa::param::ParamType::Format.as_raw() {
                return;
            }
            let Ok((mt, ms)) = format_utils::parse_format(param) else {
                return;
            };
            if mt != MediaType::Audio || ms != MediaSubtype::Raw {
                return;
            }
            if ud.format.parse(param).is_ok() {
                eprintln!(
                    "omaviz-engine: capturing rate:{} channels:{}",
                    ud.format.rate(),
                    ud.format.channels()
                );
            }
        })
        .process(|stream, ud| {
            let Some(mut buffer) = stream.dequeue_buffer() else {
                return;
            };
            let datas = buffer.datas_mut();
            if datas.is_empty() {
                return;
            }
            let n_ch = ud.format.channels().max(1) as usize;
            let rate = if ud.format.rate() > 0 {
                ud.format.rate()
            } else {
                48_000
            };
            let d = &mut datas[0];
            let size = d.chunk().size() as usize;
            let Some(bytes) = d.data() else { return };
            let avail = size.min(bytes.len());
            let n_samples = avail / 4;
            let frames = n_samples / n_ch;
            if frames == 0 {
                return;
            }
            let mut mono = Vec::with_capacity(frames);
            for f in 0..frames {
                let mut acc = 0.0f32;
                for c in 0..n_ch {
                    let start = (f * n_ch + c) * 4;
                    let v = f32::from_le_bytes(bytes[start..start + 4].try_into().unwrap());
                    acc += v;
                }
                mono.push(acc / n_ch as f32);
            }
            let _ = ud.tx.send(AudioChunk {
                samples: mono,
                rate,
                channels: ud.format.channels().min(2) as u16,
            });
        })
        .register()?;

    let mut audio_info = spa::param::audio::AudioInfoRaw::new();
    audio_info.set_format(spa::param::audio::AudioFormat::F32LE);
    let obj = spa::pod::Object {
        type_: spa::utils::SpaTypes::ObjectParamFormat.as_raw(),
        id: spa::param::ParamType::EnumFormat.as_raw(),
        properties: audio_info.into(),
    };
    let values: Vec<u8> = spa::pod::serialize::PodSerializer::serialize(
        std::io::Cursor::new(Vec::new()),
        &spa::pod::Value::Object(obj),
    )?
    .0
    .into_inner();
    let mut params = [Pod::from_bytes(&values).unwrap()];

    stream.connect(
        spa::utils::Direction::Input,
        None,
        pw::stream::StreamFlags::AUTOCONNECT
            | pw::stream::StreamFlags::MAP_BUFFERS
            | pw::stream::StreamFlags::RT_PROCESS,
        &mut params,
    )?;

    mainloop.run();
    Ok(())
}

/// Spawn the PipeWire capture loop on a background thread.
/// Returns a receiver of mono audio chunks. The thread runs until the process exits.
pub fn spawn() -> Result<std::sync::mpsc::Receiver<AudioChunk>> {
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        if let Err(e) = run_loop(tx) {
            eprintln!("omaviz-engine: pipewire capture error: {e}");
        }
    });
    Ok(rx)
}
