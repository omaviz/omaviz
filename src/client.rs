//! Window client: desktop mode (floating widget) and full mode (fullscreen).
//!
//! Handles hot config reload, mode-state changes (a bar menu switching to
//! "off" closes this window) and double-click to toggle fullscreen.

use crate::config::{Config, Mode};
use crate::ipc::Frame;
use crate::mode;
use crate::render::Renderer;
use anyhow::Result;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use winit::application::ApplicationHandler;
use winit::event::{ElementState, MouseButton, WindowEvent};
use winit::event_loop::{ActiveEventLoop, ControlFlow, EventLoop};
use winit::window::{Window, WindowId};

/// Two clicks within this window count as a double-click.
const DOUBLE_CLICK: Duration = Duration::from_millis(400);

pub struct App {
    mode: Mode,
    cfg: Config,
    frame: Arc<Mutex<Frame>>,
    window: Option<Arc<Window>>,
    renderer: Option<Renderer>,
    watcher: crate::config::Watcher,
    last_click: Option<Instant>,
    fullscreen: bool,
    mode_check: Instant,
}

impl App {
    pub fn new(mode: Mode, cfg: Config, frame: Arc<Mutex<Frame>>) -> App {
        App {
            mode,
            cfg,
            frame,
            window: None,
            renderer: None,
            watcher: crate::config::Watcher::new(),
            last_click: None,
            fullscreen: mode == Mode::Full,
            mode_check: Instant::now(),
        }
    }

    fn toggle_fullscreen(&mut self) {
        let Some(w) = self.window.as_ref() else {
            return;
        };
        self.fullscreen = !self.fullscreen;
        w.set_fullscreen(if self.fullscreen {
            Some(winit::window::Fullscreen::Borderless(None))
        } else {
            None
        });
        // Fullscreen uses its own configured visual.
        self.mode = if self.fullscreen {
            Mode::Full
        } else {
            Mode::Desktop
        };
        if let Some(r) = self.renderer.as_mut() {
            let want = self.cfg.mode(self.mode).visual.clone();
            if let Err(e) = r.set_visual(&want) {
                eprintln!("omaviz: {e:#}");
            }
        }
    }
}

impl ApplicationHandler for App {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.window.is_some() {
            return;
        }

        let mut attrs = Window::default_attributes()
            .with_title(if self.mode == Mode::Full {
                "omaviz fullscreen"
            } else {
                "omaviz"
            })
            .with_inner_size(winit::dpi::LogicalSize::new(640.0, 200.0))
            .with_transparent(true);
        // Without an explicit app_id the Wayland window class is empty and no
        // compositor windowrule can ever match it.
        #[cfg(target_os = "linux")]
        {
            use winit::platform::wayland::WindowAttributesExtWayland;
            attrs = attrs.with_name("omaviz", "omaviz");
        }
        if self.mode == Mode::Full {
            attrs = attrs.with_fullscreen(Some(winit::window::Fullscreen::Borderless(None)));
        }

        let window = match event_loop.create_window(attrs) {
            Ok(w) => Arc::new(w),
            Err(e) => {
                eprintln!("omaviz: cannot create window: {e}");
                event_loop.exit();
                return;
            }
        };

        let size = window.inner_size();
        match Renderer::new(
            window.clone(),
            size.width,
            size.height,
            self.cfg.clone(),
            self.mode,
        ) {
            Ok(r) => self.renderer = Some(r),
            Err(e) => {
                eprintln!("omaviz: renderer init failed: {e:#}");
                event_loop.exit();
                return;
            }
        }
        self.window = Some(window);
    }

    fn window_event(&mut self, event_loop: &ActiveEventLoop, _id: WindowId, event: WindowEvent) {
        match event {
            WindowEvent::CloseRequested => event_loop.exit(),

            WindowEvent::Resized(size) => {
                if let Some(r) = self.renderer.as_mut() {
                    r.resize(size.width, size.height);
                }
            }

            WindowEvent::MouseInput {
                state: ElementState::Pressed,
                button: MouseButton::Left,
                ..
            } => {
                let now = Instant::now();
                let is_double = self
                    .last_click
                    .map(|t| now.duration_since(t) < DOUBLE_CLICK)
                    .unwrap_or(false);
                if is_double {
                    self.toggle_fullscreen();
                    self.last_click = None;
                } else {
                    self.last_click = Some(now);
                }
            }

            WindowEvent::KeyboardInput { event, .. } => {
                use winit::keyboard::{Key, NamedKey};
                if event.state != ElementState::Pressed {
                    return;
                }
                match event.logical_key.as_ref() {
                    Key::Named(NamedKey::Escape) | Key::Character("q") => event_loop.exit(),
                    Key::Character("f") => self.toggle_fullscreen(),
                    _ => {}
                }
            }

            WindowEvent::RedrawRequested => {
                // Hot reload: pick up settings saves without a restart.
                if let Some(cfg) = self.watcher.poll() {
                    self.cfg = cfg.clone();
                    if let Some(r) = self.renderer.as_mut() {
                        if let Err(e) = r.apply_config(cfg) {
                            eprintln!("omaviz: applying config: {e:#}");
                        }
                    }
                }

                // If the bar menu switched the display mode off, close.
                if self.mode != Mode::Full && self.mode_check.elapsed() > Duration::from_millis(500)
                {
                    self.mode_check = Instant::now();
                    if !mode::get().shows_desktop() {
                        event_loop.exit();
                        return;
                    }
                }

                let frame = self.frame.lock().unwrap().clone();
                if let Some(r) = self.renderer.as_mut() {
                    if let Err(e) = r.render(&frame) {
                        eprintln!("omaviz: render: {e:#}");
                    }
                }
                if let Some(w) = self.window.as_ref() {
                    w.request_redraw();
                }
            }

            _ => {}
        }
    }
}

pub fn run(mode: Mode, cfg: Config) -> Result<()> {
    // Single instance per window kind: a second launch focuses the first.

    let Some(_guard) = crate::instance::acquire(if mode == Mode::Full {
        crate::instance::WindowKind::Full
    } else {
        crate::instance::WindowKind::Desktop
    })?
    else {
        eprintln!("omaviz: already running, focusing existing window");
        crate::instance::focus_existing(if mode == Mode::Full {
            crate::instance::WindowKind::Full
        } else {
            crate::instance::WindowKind::Desktop
        });
        return Ok(());
    };

    let frame = Arc::new(Mutex::new(Frame::default()));
    crate::ipc::spawn_reader(frame.clone());

    let event_loop = EventLoop::new()?;
    event_loop.set_control_flow(ControlFlow::Poll);
    let mut app = App::new(mode, cfg, frame);
    event_loop.run_app(&mut app)?;
    // Leak `app` on exit instead of dropping it. The GL/EGL backend's EGL
    // instance segfaults when dropped after the Wayland connection is torn
    // down (wgpu + Mesa + Wayland bug); leaking skips that teardown. The GPU
    // resources are released by the OS when the process exits.
    std::mem::forget(app);
    Ok(())
}
