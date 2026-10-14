//! PipeWire capture backend: taps the default sink monitor, preserving f32 channels.
//! Ported from v6/daemon/src/capture.rs; adapted to spawn a thread + channel.

use crate::dsp::AudioChunk;
use anyhow::Result;
use pipewire as pw;
use pw::{properties::properties, spa};
use spa::param::format::{MediaSubtype, MediaType};
use spa::param::format_utils;
use spa::pod::Pod;
use super::latest::{Sender, Receiver, channel};

struct UserData {
    format: spa::param::audio::AudioInfoRaw,
    tx: Sender<AudioChunk>,
}

// Process on the main loop: allocation and queue synchronization must not run
// on PipeWire's realtime audio thread. Preserve channels until spectral analysis.
fn run_loop(tx: Sender<AudioChunk>) -> Result<()> {
    pw::init();
    let mainloop = pw::main_loop::MainLoopRc::new(None)?;
    let context = pw::context::ContextRc::new(&mainloop, None)?;
    let core = context.connect_rc(None)?;
    let error_loop = mainloop.clone();
    let _core_listener = core.add_listener_local().error(move |id, _, result, message| {
        if id == 0 && result < 0 {
            eprintln!("omaviz-engine: PipeWire connection lost: {message}");
            error_loop.quit();
        }
    }).register();

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

    let state_loop = mainloop.clone();
    let _listener = stream
        .add_local_listener_with_user_data(data)
        .state_changed(move |_, _, old, new| {
            if matches!(new, pw::stream::StreamState::Error(_)) ||
                (matches!(new, pw::stream::StreamState::Unconnected) &&
                 !matches!(old, pw::stream::StreamState::Unconnected)) {
                state_loop.quit();
            }
        })
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
            let n_ch = ud.format.channels().clamp(1, 64) as usize;
            let rate = if ud.format.rate() > 0 {
                ud.format.rate()
            } else {
                48_000
            };
            let d = &mut datas[0];
            let size = d.chunk().size() as usize;
            let offset = d.chunk().offset() as usize;
            let stride = d.chunk().stride();
            let Some(bytes) = d.data() else { return };
            let samples = decode_pcm(bytes, offset, size, stride, n_ch);
            if samples.is_empty() { return; }
            let _ = ud.tx.send(AudioChunk {
                samples,
                rate,
                channels: n_ch,
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
            | pw::stream::StreamFlags::MAP_BUFFERS,
        &mut params,
    )?;

    mainloop.run();
    Ok(())
}

/// Spawn the PipeWire capture loop on a background thread.
/// Returns a bounded receiver of interleaved audio chunks. The thread runs until process exit.
pub fn spawn() -> Result<Receiver<AudioChunk>> {
    let (tx, rx) = channel(4);
    std::thread::spawn(move || {
        if let Err(e) = run_loop(tx) {
            eprintln!("omaviz-engine: pipewire capture error: {e}");
        }
    });
    Ok(rx)
}

// SPA offsets wrap within maxsize; padding between interleaved frames is valid.
fn decode_pcm(bytes: &[u8], offset: usize, size: usize, stride: i32, channels: usize) -> Vec<f32> {
    if bytes.is_empty() || channels == 0 { return vec![]; }
    let packed = channels.saturating_mul(4);
    let stride = if stride > 0 { stride as usize } else { packed };
    if stride < packed { return vec![]; }
    let frames = (size.min(bytes.len()) / stride).min(8192);
    let mut samples = Vec::with_capacity(frames * channels);
    for frame in 0..frames {
        for channel in 0..channels {
            let start = (offset % bytes.len() + frame * stride + channel * 4) % bytes.len();
            let sample = f32::from_le_bytes(std::array::from_fn(|i| bytes[(start+i) % bytes.len()]));
            samples.push(if sample.is_finite() { sample.clamp(-1.0,1.0) } else { 0.0 });
        }
    }
    samples
}

#[cfg(test)]
mod tests {
    use super::decode_pcm;
    #[test]
    fn honors_offset_wrap_and_padded_stride() {
        let bytes: Vec<u8> = [0.25f32, 0.5, 0.75, -0.5].iter().flat_map(|x| x.to_le_bytes()).collect();
        assert_eq!(decode_pcm(&bytes, 8, 8, 4, 1), vec![0.75,-0.5]);
        assert_eq!(decode_pcm(&bytes, 12, 8, 4, 1), vec![-0.5,0.25]);
        assert_eq!(decode_pcm(&bytes, 0, 16, 8, 1), vec![0.25,0.75]);
        assert_eq!(decode_pcm(&bytes, 0, 16, 8, 2), vec![0.25,0.5,0.75,-0.5]);
        assert!(decode_pcm(&[], 2, 8, 4, 1).is_empty());
        assert!(decode_pcm(&bytes, 0, 16, 4, 2).is_empty());
    }
}
