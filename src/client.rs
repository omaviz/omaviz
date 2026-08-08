//! Window client: desktop mode (normal toplevel) and full mode (fullscreen).

use crate::config::{Config, Mode};
use crate::ipc::Frame;
use crate::render::Renderer;
use anyhow::Result;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use winit::application::ApplicationHandler;
use winit::event::WindowEvent;
use winit::event_loop::{ActiveEventLoop, ControlFlow, EventLoop};
use winit::window::{Window, WindowId};

struct App {
    cfg: Config,
    mode: Mode,
    window: Option<Arc<Window>>,
    renderer: Option<Renderer>,
    frame: Arc<Mutex<Frame>>,
    start: Instant,
    /// Frames of continuous silence; used to stop rendering when idle.
    silent_frames: u32,
    min_period: Option<Duration>,
    last_draw: Instant,
}

impl App {
    fn new(cfg: Config, mode: Mode, frame: Arc<Mutex<Frame>>) -> Self {
        let fps = cfg.mode(mode).fps;
        // fps 0 = uncapped (vsync governs).
        let min_period = if fps > 0 {
            Some(Duration::from_secs_f64(1.0 / fps as f64))
        } else {
            None
        };
        App {
            cfg,
            mode,
            window: None,
            renderer: None,
            frame,
            start: Instant::now(),
            silent_frames: 0,
            min_period,
            last_draw: Instant::now(),
        }
    }
}

impl ApplicationHandler for App {
    fn resumed(&mut self, el: &ActiveEventLoop) {
        let mut attrs = Window::default_attributes()
            .with_title("omaviz")
            .with_inner_size(winit::dpi::LogicalSize::new(640.0, 200.0));
        if self.mode == Mode::Full {
            attrs = attrs.with_fullscreen(Some(winit::window::Fullscreen::Borderless(None)));
        }
        let window = Arc::new(el.create_window(attrs).expect("create window"));
        match Renderer::new(window.clone(), &self.cfg, self.mode) {
            Ok(r) => self.renderer = Some(r),
            Err(e) => {
                eprintln!("omaviz: renderer init failed: {e:#}");
                el.exit();
                return;
            }
        }
        self.window = Some(window);
    }

    fn window_event(&mut self, el: &ActiveEventLoop, _id: WindowId, event: WindowEvent) {
        match event {
            WindowEvent::CloseRequested => el.exit(),
            WindowEvent::KeyboardInput { event, .. } => {
                use winit::keyboard::{Key, NamedKey};
                if event.state.is_pressed() {
                    match event.logical_key {
                        Key::Named(NamedKey::Escape) => el.exit(),
                        Key::Character(ref c) if c == "q" => el.exit(),
                        Key::Character(ref c) if c == "f" => {
                            if let Some(w) = &self.window {
                                let fs = w.fullscreen().is_some();
                                w.set_fullscreen(if fs {
                                    None
                                } else {
                                    Some(winit::window::Fullscreen::Borderless(None))
                                });
                            }
                        }
                        _ => {}
                    }
                }
            }
            WindowEvent::Resized(sz) => {
                if let Some(r) = &mut self.renderer {
                    r.resize(sz.width, sz.height);
                }
            }
            WindowEvent::RedrawRequested => {
                let frame = self.frame.lock().unwrap().clone();

                // Silence gating: after ~2s of quiet, stop issuing draws.
                if frame.silent {
                    self.silent_frames = self.silent_frames.saturating_add(1);
                } else {
                    self.silent_frames = 0;
                }
                let idle = self.silent_frames > 120;

                if !idle && let Some(r) = &mut self.renderer {
                    let t = self.start.elapsed().as_secs_f32();
                    if let Err(e) = r.render(&frame, t) {
                        eprintln!("omaviz: render error: {e:#}");
                    }
                }
                self.last_draw = Instant::now();
            }
            _ => {}
        }
    }

    fn about_to_wait(&mut self, el: &ActiveEventLoop) {
        // Frame-cap by sleeping until the next slot; vsync handles the rest.
        if let Some(p) = self.min_period {
            let since = self.last_draw.elapsed();
            if since < p {
                el.set_control_flow(ControlFlow::WaitUntil(self.last_draw + p));
                return;
            }
        }
        // When idle, poll slowly instead of spinning.
        if self.silent_frames > 120 {
            el.set_control_flow(ControlFlow::WaitUntil(
                Instant::now() + Duration::from_millis(100),
            ));
        } else {
            el.set_control_flow(ControlFlow::Poll);
        }
        if let Some(w) = &self.window {
            w.request_redraw();
        }
    }
}

/// Background thread: read frames from the daemon into the shared slot.
pub fn spawn_frame_reader(shared: Arc<Mutex<Frame>>) {
    std::thread::spawn(move || {
        loop {
            match crate::ipc::connect() {
                Ok(mut stream) => {
                    while let Ok(f) = Frame::read_from(&mut stream) {
                        *shared.lock().unwrap() = f;
                    }
                }
                Err(_) => {
                    std::thread::sleep(Duration::from_millis(500));
                }
            }
        }
    });
}

pub fn run(cfg: Config, mode: Mode) -> Result<()> {
    let shared = Arc::new(Mutex::new(Frame::default()));
    spawn_frame_reader(shared.clone());
    let el = EventLoop::new()?;
    let mut app = App::new(cfg, mode, shared);
    el.run_app(&mut app)?;
    Ok(())
}
