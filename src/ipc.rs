//! Frame IPC: daemon broadcasts compact binary spectrum frames over a unix
//! socket; clients (desktop, fullscreen, waybar) are pure consumers.
//!
//! Wire format (little endian), one frame:
//!   magic u32 = 0x4F4D4156 ("OMAV")
//!   n_bands u16
//!   flags   u16   bit0 = silent
//!   energy  f32
//!   beat    f32
//!   bands   [f32; n_bands]

use anyhow::{Result, bail};
use std::io::{Read, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;

pub const MAGIC: u32 = 0x4F4D_4156;
pub const FLAG_SILENT: u16 = 1;

pub fn socket_path() -> PathBuf {
    let base = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".into());
    PathBuf::from(base).join("omaviz.sock")
}

#[derive(Debug, Clone, Default)]
pub struct Frame {
    pub bands: Vec<f32>,
    pub energy: f32,
    pub beat: f32,
    pub silent: bool,
}

impl Frame {
    pub fn encode(&self, buf: &mut Vec<u8>) {
        buf.clear();
        buf.extend_from_slice(&MAGIC.to_le_bytes());
        buf.extend_from_slice(&(self.bands.len() as u16).to_le_bytes());
        let flags = if self.silent { FLAG_SILENT } else { 0 };
        buf.extend_from_slice(&flags.to_le_bytes());
        buf.extend_from_slice(&self.energy.to_le_bytes());
        buf.extend_from_slice(&self.beat.to_le_bytes());
        for b in &self.bands {
            buf.extend_from_slice(&b.to_le_bytes());
        }
    }

    pub fn read_from(s: &mut impl Read) -> Result<Frame> {
        let mut head = [0u8; 16];
        s.read_exact(&mut head)?;
        let magic = u32::from_le_bytes(head[0..4].try_into().unwrap());
        if magic != MAGIC {
            bail!("bad frame magic {magic:#x}");
        }
        let n = u16::from_le_bytes(head[4..6].try_into().unwrap()) as usize;
        let flags = u16::from_le_bytes(head[6..8].try_into().unwrap());
        let energy = f32::from_le_bytes(head[8..12].try_into().unwrap());
        let beat = f32::from_le_bytes(head[12..16].try_into().unwrap());
        let mut body = vec![0u8; n * 4];
        s.read_exact(&mut body)?;
        let bands = body
            .chunks_exact(4)
            .map(|c| f32::from_le_bytes(c.try_into().unwrap()))
            .collect();
        Ok(Frame {
            bands,
            energy,
            beat,
            silent: flags & FLAG_SILENT != 0,
        })
    }
}

/// Non-blocking broadcast server. Drops slow/dead clients silently.
pub struct Server {
    listener: UnixListener,
    clients: Vec<UnixStream>,
    buf: Vec<u8>,
}

impl Server {
    pub fn bind() -> Result<Server> {
        let path = socket_path();
        let _ = std::fs::remove_file(&path);
        let listener = UnixListener::bind(&path)?;
        listener.set_nonblocking(true)?;
        Ok(Server {
            listener,
            clients: Vec::new(),
            buf: Vec::with_capacity(512),
        })
    }

    /// Number of currently attached clients (drives idle gating).
    pub fn client_count(&self) -> usize {
        self.clients.len()
    }

    pub fn accept_pending(&mut self) {
        while let Ok((stream, _)) = self.listener.accept() {
            let _ = stream.set_nonblocking(true);
            self.clients.push(stream);
        }
    }

    pub fn broadcast(&mut self, frame: &Frame) {
        if self.clients.is_empty() {
            return;
        }
        frame.encode(&mut self.buf);
        let buf = &self.buf;
        self.clients.retain_mut(|c| match c.write_all(buf) {
            Ok(()) => true,
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => true,
            Err(_) => false,
        });
    }
}

impl Drop for Server {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(socket_path());
    }
}

pub fn connect() -> Result<UnixStream> {
    Ok(UnixStream::connect(socket_path())?)
}

/// Spawn a thread that keeps the newest frame in a shared slot, reconnecting
/// if the daemon restarts. Clients render from the slot at their own cadence,
/// so a slow renderer never backs up the socket.
pub fn spawn_reader(slot: std::sync::Arc<std::sync::Mutex<Frame>>) {
    std::thread::spawn(move || {
        loop {
            let Ok(mut stream) = connect() else {
                std::thread::sleep(std::time::Duration::from_millis(500));
                continue;
            };
            let _ = stream.set_nonblocking(false);
            while let Ok(f) = Frame::read_from(&mut stream) {
                *slot.lock().unwrap() = f;
            }
            // Daemon went away: mark silent and retry.
            *slot.lock().unwrap() = Frame::default();
            std::thread::sleep(std::time::Duration::from_millis(500));
        }
    });
}
