use anyhow::Result;
use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;

const MAGIC: u32 = 0x4F4D_4156;
const FLAG_SILENT: u16 = 1;

fn socket_path() -> PathBuf {
    let base = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".into());
    PathBuf::from(base).join("omaviz.sock")
}

fn main() -> Result<()> {
    let path = socket_path();
    let mut stream = UnixStream::connect(&path)?;
    stream.set_nonblocking(false)?;

    let mut buf = [0u8; 16];

    loop {
        // Read header
        if let Err(e) = stream.read_exact(&mut buf) {
            eprintln!("read error: {e}");
            std::thread::sleep(std::time::Duration::from_millis(500));
            // Try to reconnect
            match UnixStream::connect(&path) {
                Ok(s) => { stream = s; stream.set_nonblocking(false)?; continue }
                Err(_) => continue,
            }
        }

        let magic = u32::from_le_bytes(buf[0..4].try_into().unwrap());
        if magic != MAGIC {
            eprintln!("bad magic {magic:#x}");
            continue;
        }

        let n_bands = u16::from_le_bytes(buf[4..6].try_into().unwrap()) as usize;
        let flags = u16::from_le_bytes(buf[6..8].try_into().unwrap());
        let energy = f32::from_le_bytes(buf[8..12].try_into().unwrap());
        let beat = f32::from_le_bytes(buf[12..16].try_into().unwrap());
        let silent = flags & FLAG_SILENT != 0;

        let mut body = vec![0u8; n_bands * 4];
        stream.read_exact(&mut body)?;

        let bands: Vec<f32> = body.chunks_exact(4)
            .map(|c| f32::from_le_bytes(c.try_into().unwrap()))
            .collect();

        // Emit JSON line
        let bands_json = bands.iter()
            .map(|v| format!("{:.4}", v))
            .collect::<Vec<_>>()
            .join(",");

        println!(r#"{{"bands":[{}],"energy":{:.4},"beat":{:.4},"silent":{}}}"#,
            bands_json, energy, beat, silent);
        std::io::stdout().flush()?;
    }
}
