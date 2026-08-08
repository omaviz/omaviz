//! Settings panel (egui). Edits config.toml, which daemon and clients reload.

use crate::config::{Config, ModeConfig};
use crate::ipc::Frame;
use anyhow::Result;
use std::sync::{Arc, Mutex};

struct SettingsApp {
    cfg: Config,
    visuals: Vec<String>,
    frame: Arc<Mutex<Frame>>,
    status: String,
    dirty: bool,
}

impl SettingsApp {
    fn new(cfg: Config, frame: Arc<Mutex<Frame>>) -> Self {
        let mut visuals = crate::render::list_visuals();
        if visuals.is_empty() {
            visuals.push("bars".into());
        }
        SettingsApp {
            cfg,
            visuals,
            frame,
            status: String::new(),
            dirty: false,
        }
    }

    fn mode_row(
        ui: &mut egui::Ui,
        label: &str,
        m: &mut ModeConfig,
        visuals: &[String],
        allowed: Option<&[&str]>,
        dirty: &mut bool,
    ) {
        ui.group(|ui| {
            ui.label(egui::RichText::new(label).strong());
            ui.horizontal(|ui| {
                ui.label("visualization");
                let before = m.visual.clone();
                egui::ComboBox::from_id_salt(format!("{label}-visual"))
                    .selected_text(&m.visual)
                    .show_ui(ui, |ui| {
                        match allowed {
                            // Mini mode has a deliberately limited selection.
                            Some(list) => {
                                for v in list {
                                    ui.selectable_value(&mut m.visual, v.to_string(), *v);
                                }
                            }
                            None => {
                                for v in visuals {
                                    ui.selectable_value(&mut m.visual, v.clone(), v);
                                }
                            }
                        }
                    });
                if before != m.visual {
                    *dirty = true;
                }
            });
            ui.horizontal(|ui| {
                ui.label("fps cap");
                if ui
                    .add(egui::Slider::new(&mut m.fps, 0..=144).text("0 = vsync"))
                    .changed()
                {
                    *dirty = true;
                }
            });
        });
    }
}

impl eframe::App for SettingsApp {
    fn update(&mut self, ctx: &egui::Context, _f: &mut eframe::Frame) {
        let frame = self.frame.lock().unwrap().clone();

        egui::CentralPanel::default().show(ctx, |ui| {
            ui.heading("omaviz settings");

            // Live preview strip proves the daemon connection from the GUI.
            ui.add_space(4.0);
            ui.label(if frame.bands.is_empty() {
                "daemon: not connected"
            } else if frame.silent {
                "daemon: connected (silent)"
            } else {
                "daemon: connected"
            });
            let (rect, _) = ui
                .allocate_exact_size(egui::vec2(ui.available_width(), 48.0), egui::Sense::hover());
            let p = ui.painter();
            p.rect_filled(rect, 2.0, egui::Color32::from_rgb(8, 8, 14));
            if !frame.bands.is_empty() {
                let n = frame.bands.len();
                let w = rect.width() / n as f32;
                for (i, v) in frame.bands.iter().enumerate() {
                    let h = (v * self.cfg.sensitivity).clamp(0.0, 1.0) * rect.height();
                    let x = rect.left() + i as f32 * w;
                    let bar = egui::Rect::from_min_max(
                        egui::pos2(x + w * 0.15, rect.bottom() - h),
                        egui::pos2(x + w * 0.85, rect.bottom()),
                    );
                    let t = i as f32 / n as f32;
                    let lo = self.cfg.palette.low;
                    let hi = self.cfg.palette.high;
                    let c = egui::Color32::from_rgb(
                        ((lo[0] + (hi[0] - lo[0]) * t) * 255.0) as u8,
                        ((lo[1] + (hi[1] - lo[1]) * t) * 255.0) as u8,
                        ((lo[2] + (hi[2] - lo[2]) * t) * 255.0) as u8,
                    );
                    p.rect_filled(bar, 1.0, c);
                }
            }
            ui.add_space(8.0);

            egui::ScrollArea::vertical().show(ui, |ui| {
                ui.group(|ui| {
                    ui.label(egui::RichText::new("global").strong());
                    ui.horizontal(|ui| {
                        ui.label("bands");
                        if ui
                            .add(egui::Slider::new(&mut self.cfg.bands, 8..=128))
                            .changed()
                        {
                            self.dirty = true;
                        }
                    });
                    ui.horizontal(|ui| {
                        ui.label("sensitivity");
                        if ui
                            .add(egui::Slider::new(&mut self.cfg.sensitivity, 0.2..=4.0))
                            .changed()
                        {
                            self.dirty = true;
                        }
                    });
                    ui.horizontal(|ui| {
                        ui.label("smoothing");
                        if ui
                            .add(egui::Slider::new(&mut self.cfg.smoothing, 0.0..=0.95))
                            .changed()
                        {
                            self.dirty = true;
                        }
                    });
                });

                let visuals = self.visuals.clone();
                Self::mode_row(
                    ui,
                    "desktop mode",
                    &mut self.cfg.desktop,
                    &visuals,
                    None,
                    &mut self.dirty,
                );
                Self::mode_row(
                    ui,
                    "full mode",
                    &mut self.cfg.full,
                    &visuals,
                    None,
                    &mut self.dirty,
                );
                Self::mode_row(
                    ui,
                    "mini mode (waybar)",
                    &mut self.cfg.mini,
                    &visuals,
                    Some(&["bars", "vu"]),
                    &mut self.dirty,
                );

                ui.group(|ui| {
                    ui.label(egui::RichText::new("palette").strong());
                    let mut changed = false;
                    ui.horizontal(|ui| {
                        ui.label("low");
                        changed |= ui
                            .color_edit_button_rgb(&mut self.cfg.palette.low)
                            .changed();
                        ui.label("high");
                        changed |= ui
                            .color_edit_button_rgb(&mut self.cfg.palette.high)
                            .changed();
                    });
                    let mut bg = [
                        self.cfg.palette.bg[0],
                        self.cfg.palette.bg[1],
                        self.cfg.palette.bg[2],
                    ];
                    ui.horizontal(|ui| {
                        ui.label("background");
                        if ui.color_edit_button_rgb(&mut bg).changed() {
                            self.cfg.palette.bg[0] = bg[0];
                            self.cfg.palette.bg[1] = bg[1];
                            self.cfg.palette.bg[2] = bg[2];
                            changed = true;
                        }
                    });
                    if changed {
                        self.dirty = true;
                    }
                });
            });

            ui.add_space(8.0);
            ui.horizontal(|ui| {
                if ui.button("Save").clicked() {
                    match self.cfg.save() {
                        Ok(()) => {
                            self.status =
                                format!("saved {}", crate::config::config_path().display());
                            self.dirty = false;
                        }
                        Err(e) => self.status = format!("save failed: {e}"),
                    }
                }
                if ui.button("Reload").clicked() {
                    match Config::load_or_init() {
                        Ok(c) => {
                            self.cfg = c;
                            self.dirty = false;
                            self.status = "reloaded from disk".into();
                        }
                        Err(e) => self.status = format!("reload failed: {e}"),
                    }
                }
                if ui.button("Defaults").clicked() {
                    self.cfg = Config::default();
                    self.dirty = true;
                }
                if self.dirty {
                    ui.label(egui::RichText::new("unsaved changes").weak());
                }
            });
            if !self.status.is_empty() {
                ui.label(&self.status);
            }
        });

        // Repaint at ~30 fps only while the preview has something to show.
        ctx.request_repaint_after(std::time::Duration::from_millis(if frame.silent {
            250
        } else {
            33
        }));
    }
}

pub fn run(cfg: Config) -> Result<()> {
    let shared = Arc::new(Mutex::new(Frame::default()));
    crate::client::spawn_frame_reader(shared.clone());
    let opts = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([520.0, 720.0])
            .with_title("omaviz settings"),
        ..Default::default()
    };
    eframe::run_native(
        "omaviz settings",
        opts,
        Box::new(move |_cc| Ok(Box::new(SettingsApp::new(cfg, shared)))),
    )
    .map_err(|e| anyhow::anyhow!("settings ui failed: {e}"))
}
