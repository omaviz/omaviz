//! Settings panel (egui).
//!
//! Layout follows the requested shape:
//!   top ~50%  — live visualization preview (renders from the *working* config,
//!                so changes appear instantly, before Save)
//!   bottom    — left: visualization list (vertical radio, current ticked);
//!                right: options for the selected visual + mode-only tweaks
//!   footer    — Reset (per visual), Save, Cancel
//!
//! Saving writes config.toml; every running client watches that file, so the
//! desktop window and the waybar module update live.

use crate::config::{Config, Mode, PaletteSource};
use crate::ipc::Frame;
use crate::visual::{self, Visual};
use anyhow::Result;
use std::sync::{Arc, Mutex};

pub struct SettingsApp {
    cfg: Config,
    saved: Config,
    frame: Arc<Mutex<Frame>>,
    visuals: Vec<Visual>,
    /// Which mode's settings are being edited.
    target: Mode,
    status: String,
    /// Visual currently focused in the list (drives the right-hand options).
    focus: String,
}

impl SettingsApp {
    fn new(cfg: Config, frame: Arc<Mutex<Frame>>) -> SettingsApp {
        let focus = cfg.mode(Mode::Desktop).visual.clone();
        SettingsApp {
            saved: cfg.clone(),
            cfg,
            frame,
            visuals: visual::discover(),
            target: Mode::Desktop,
            status: String::new(),
            focus,
        }
    }

    fn dirty(&self) -> bool {
        toml::to_string(&self.cfg).ok() != toml::to_string(&self.saved).ok()
    }

    fn save(&mut self) {
        match self.cfg.save() {
            Ok(()) => {
                self.saved = self.cfg.clone();
                self.status = "Saved — applied live".into();
            }
            Err(e) => self.status = format!("Save failed: {e}"),
        }
    }

    fn reset_visual(&mut self) {
        // Reset this visual's knobs to their declared defaults (in-memory only;
        // Save persists). Also clears any stored per-visual overrides.
        self.cfg.visuals.remove(&self.focus);
        self.status = format!("Reset '{}' (unsaved)", self.focus);
    }

    fn selected_visual(&self) -> Option<&Visual> {
        self.visuals.iter().find(|v| v.name == self.focus)
    }
}

/// Paint the live spectrum preview using the same palette the renderer uses.
/// Renders from the *working* cfg so slider/param edits show immediately.
fn draw_preview(ui: &mut egui::Ui, frame: &Frame, cfg: &Config, target: Mode) {
    let rect = ui.available_rect_before_wrap();
    let painter = ui.painter_at(rect);
    let pal = cfg.resolved_palette();

    let bg = egui::Color32::from_rgba_unmultiplied(
        (pal.bg[0] * 255.0) as u8,
        (pal.bg[1] * 255.0) as u8,
        (pal.bg[2] * 255.0) as u8,
        (pal.bg[3] * 255.0) as u8,
    );
    painter.rect_filled(rect, 6.0, bg);

    if frame.bands.is_empty() {
        painter.text(
            rect.center(),
            egui::Align2::CENTER_CENTER,
            "waiting for daemon…",
            egui::FontId::proportional(13.0),
            egui::Color32::GRAY,
        );
        return;
    }

    let n = frame.bands.len();
    let gap = 2.0;
    let w = (rect.width() - gap * (n as f32 - 1.0)) / n as f32;
    for (i, b) in frame.bands.iter().enumerate() {
        let h = (b * cfg.sensitivity(target)).clamp(0.0, 1.0) * rect.height();
        let x = rect.left() + i as f32 * (w + gap);
        let bar = egui::Rect::from_min_max(
            egui::pos2(x, rect.bottom() - h),
            egui::pos2(x + w, rect.bottom()),
        );
        let t = i as f32 / n.max(1) as f32;
        let col = egui::Color32::from_rgb(
            ((pal.low[0] + (pal.high[0] - pal.low[0]) * t) * 255.0) as u8,
            ((pal.low[1] + (pal.high[1] - pal.low[1]) * t) * 255.0) as u8,
            ((pal.low[2] + (pal.high[2] - pal.low[2]) * t) * 255.0) as u8,
        );
        painter.rect_filled(bar, 2.0, col);
    }
}

impl eframe::App for SettingsApp {
    fn clear_color(&self, _v: &egui::Visuals) -> [f32; 4] {
        [0.0, 0.0, 0.0, 0.0]
    }

    fn update(&mut self, ctx: &egui::Context, _f: &mut eframe::Frame) {
        // Follow the Omarchy theme for the panel chrome too.
        let pal = self.cfg.resolved_palette();
        ctx.set_visuals(if pal.is_light {
            egui::Visuals::light()
        } else {
            egui::Visuals::dark()
        });

        let frame = self.frame.lock().unwrap().clone();

        // ---------------- footer (declared first so it reserves space)
        egui::TopBottomPanel::bottom("footer")
            .min_height(48.0)
            .show(ctx, |ui| {
                ui.add_space(6.0);
                ui.horizontal(|ui| {
                    if ui.button("  Reset visual  ").clicked() {
                        self.reset_visual();
                    }
                    ui.separator();
                    let dirty = self.dirty();
                    ui.add_enabled_ui(dirty, |ui| {
                        if ui.button("  Save  ").clicked() {
                            self.save();
                        }
                    });
                    if ui.button("Cancel").clicked() {
                        self.cfg = self.saved.clone();
                        self.status = "Cancelled".into();
                    }

                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        if dirty {
                            ui.colored_label(egui::Color32::from_rgb(230, 160, 30), "unsaved");
                        } else if !self.status.is_empty() {
                            ui.weak(&self.status);
                        }
                    });
                });
                ui.add_space(6.0);
            });

        // ---------------- top 50%: live preview
        let preview_h = ctx.content_rect().height() * 0.5;
        egui::TopBottomPanel::top("preview")
            .exact_height(preview_h)
            .show(ctx, |ui| {
                ui.horizontal(|ui| {
                    ui.heading("Preview");
                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        // Mode tabs: which config section you're editing.
                        ui.horizontal(|ui| {
                            for (m, label) in [
                                (Mode::Mini, "Menu bar"),
                                (Mode::Desktop, "Desktop"),
                                (Mode::Full, "Full"),
                            ] {
                                if ui.selectable_label(self.target == m, label).clicked() {
                                    self.target = m;
                                }
                            }
                        });
                    });
                });
                ui.add_space(4.0);
                draw_preview(ui, &frame, &self.cfg, self.target);
            });

        // ---------------- bottom half: list | options
        egui::CentralPanel::default().show(ctx, |ui| {
            ui.add_space(8.0);
            ui.separator();
            ui.add_space(4.0);

            let list_w = ui.available_width() * 0.34;
            ui.horizontal_top(|ui| {
                // Left: vertical visualization list (radio).
                ui.allocate_ui(egui::vec2(list_w, ui.available_height()), |ui| {
                    ui.label(egui::RichText::new("Visualization").strong());
                    ui.add_space(4.0);
                    egui::ScrollArea::vertical()
                        .id_salt("viz-list")
                        .show(ui, |ui| {
                            if self.visuals.is_empty() {
                                ui.weak("no .wgsl files found");
                            }
                            let current = self.cfg.mode(self.target).visual.clone();
                            for v in &self.visuals {
                                let selected = v.name == self.focus;
                                let resp = ui.selectable_label(selected, v.display_label());
                                if resp.clicked() {
                                    self.focus = v.name.clone();
                                }
                                if v.name == current {
                                    ui.label(
                                        egui::RichText::new("   ▸ used by this mode")
                                            .small()
                                            .weak(),
                                    );
                                }
                            }
                        });
                    // Apply the focused visual to the edited mode.
                    if ui.button("Use selected for this mode").clicked() {
                        self.cfg.mode_mut(self.target).visual = self.focus.clone();
                    }
                });

                ui.separator();

                // Right: options for the focused visual + mode tweaks.
                ui.vertical(|ui| {
                    let mode_label = match self.target {
                        Mode::Mini => "Menu bar",
                        Mode::Desktop => "Desktop",
                        Mode::Full => "Full",
                    };
                    ui.label(egui::RichText::new(format!("Options — {mode_label}")).strong());
                    ui.add_space(4.0);
                    egui::ScrollArea::vertical()
                        .id_salt("viz-options")
                        .show(ui, |ui| {
                            let sel = self.selected_visual().cloned();
                            match sel {
                                None => {
                                    ui.weak("Select a visualization.");
                                }
                                Some(v) => {
                                    if v.params.is_empty() {
                                        ui.weak("This visualization has no options.");
                                    }
                                    ui.label(egui::RichText::new("Visualization").small().strong());
                                    for p in &v.params {
                                        let mut val = self.cfg.visual_param(&v.name, p);
                                        let changed = if p.boolean {
                                            let mut b = val > 0.5;
                                            let r = ui.checkbox(&mut b, p.display_label());
                                            val = if b { 1.0 } else { 0.0 };
                                            r.changed()
                                        } else {
                                            ui.add(
                                                egui::Slider::new(&mut val, p.min..=p.max)
                                                    .text(p.display_label()),
                                            )
                                            .changed()
                                        };
                                        if changed {
                                            self.cfg.set_visual_param(&v.name, &p.name, val);
                                        }
                                        if !p.help.is_empty() {
                                            ui.weak(egui::RichText::new(&p.help).small());
                                        }
                                        ui.add_space(2.0);
                                    }

                                    if !v.extra_params.is_empty() {
                                        ui.add_space(6.0);
                                        ui.label(
                                            egui::RichText::new("This mode only").small().strong(),
                                        );
                                        for p in &v.extra_params {
                                            let mut val = self
                                                .cfg
                                                .mode(self.target)
                                                .extra
                                                .get(&p.name)
                                                .copied()
                                                .unwrap_or(p.default)
                                                .clamp(p.min, p.max);
                                            let changed = if p.boolean {
                                                let mut b = val > 0.5;
                                                let r = ui.checkbox(&mut b, p.display_label());
                                                val = if b { 1.0 } else { 0.0 };
                                                r.changed()
                                            } else {
                                                ui.add(
                                                    egui::Slider::new(&mut val, p.min..=p.max)
                                                        .text(p.display_label()),
                                                )
                                                .changed()
                                            };
                                            if changed {
                                                self.cfg
                                                    .mode_mut(self.target)
                                                    .extra
                                                    .insert(p.name.clone(), val);
                                            }
                                            if !p.help.is_empty() {
                                                ui.weak(egui::RichText::new(&p.help).small());
                                            }
                                            ui.add_space(2.0);
                                        }
                                    }

                                    ui.add_space(8.0);
                                    ui.separator();
                                    ui.label(egui::RichText::new("Audio (this mode)").strong());
                                    // Capture the shared default before borrowing
                                    // self.cfg mutably for the mode section.
                                    let audio_sens = self.cfg.audio.sensitivity;
                                    let m = self.cfg.mode_mut(self.target);
                                    // Inherit/override toggles for shared audio.
                                    let inherit_sens = m.sensitivity.is_nan();
                                    let mut inherit_sens_mut = inherit_sens;
                                    if ui
                                        .checkbox(&mut inherit_sens_mut, "Sensitivity (inherit)")
                                        .changed()
                                    {
                                        m.sensitivity = if inherit_sens_mut {
                                            f32::NAN
                                        } else {
                                            audio_sens
                                        };
                                    }
                                    if !inherit_sens_mut {
                                        ui.add(
                                            egui::Slider::new(&mut m.sensitivity, 0.1..=4.0)
                                                .text("sensitivity"),
                                        );
                                    }
                                    ui.add(
                                        egui::Slider::new(&mut m.fps, 0..=120)
                                            .text("fps cap (0 = vsync)"),
                                    );

                                    ui.add_space(8.0);
                                    ui.separator();
                                    ui.label(egui::RichText::new("Colours").strong());
                                    let mut auto = self.cfg.palette.source == PaletteSource::Auto;
                                    if ui
                                        .checkbox(&mut auto, "Follow Omarchy theme")
                                        .on_hover_text(
                                            "Light/dark and accent colour come from your \
                                             current Omarchy theme.",
                                        )
                                        .changed()
                                    {
                                        self.cfg.palette.source = if auto {
                                            PaletteSource::Auto
                                        } else {
                                            PaletteSource::Manual
                                        };
                                    }
                                    if auto {
                                        ui.add(
                                            egui::Slider::new(
                                                &mut self.cfg.palette.opacity,
                                                0.0..=1.0,
                                            )
                                            .text("background opacity"),
                                        );
                                    } else {
                                        ui.horizontal(|ui| {
                                            ui.color_edit_button_rgb(&mut self.cfg.palette.low);
                                            ui.label("low");
                                            ui.color_edit_button_rgb(&mut self.cfg.palette.high);
                                            ui.label("high");
                                        });
                                        let mut bg = self.cfg.palette.bg;
                                        if ui.color_edit_button_rgba_unmultiplied(&mut bg).changed()
                                        {
                                            self.cfg.palette.bg = bg;
                                        }
                                        ui.weak("background (alpha = transparency)");
                                    }
                                }
                            }
                        });
                });
            });
        });

        // Live preview needs continuous repaint.
        ctx.request_repaint_after(std::time::Duration::from_millis(16));
    }
}

pub fn run(cfg: Config) -> Result<()> {
    let Some(_guard) = crate::instance::acquire(crate::instance::WindowKind::Settings)? else {
        eprintln!("omaviz: settings already open, focusing it");
        crate::instance::focus_existing(crate::instance::WindowKind::Settings);
        return Ok(());
    };

    let frame = Arc::new(Mutex::new(Frame::default()));
    crate::ipc::spawn_reader(frame.clone());

    let opts = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([760.0, 720.0])
            .with_min_inner_size([620.0, 560.0])
            .with_title("omaviz settings")
            // Wayland app_id — required for compositor windowrules to match.
            .with_app_id("omaviz"),
        ..Default::default()
    };

    eframe::run_native(
        "omaviz settings",
        opts,
        Box::new(move |_cc| Ok(Box::new(SettingsApp::new(cfg, frame)))),
    )
    .map_err(|e| anyhow::anyhow!("settings UI: {e}"))?;
    Ok(())
}
