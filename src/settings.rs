//! Settings panel (egui) — "Split Panel" layout.
//!
//! Left: vertical visualization list (the current one pre-ticked "active").
//! Top-right: live preview (renders from the working config, so edits show
//! instantly). Bottom-right: options for the selected visual, including a
//! "Per-display fit" section that captures the mode nuance — bar visuals need
//! help filling the tiny menu bar, circular visuals want full-screen room.
//!
//! The visualization choice is SHARED across all modes (mini/desktop/full);
//! only per-display *fit* tweaks differ. Reset (per visualization) lives inside
//! the options panel. Footer is Save / Cancel only.
//!
//! Colouring follows the Omarchy theme: we tint egui's selection / accent /
//! hyperlink colours with the theme accent so the panel matches the desktop,
//! without embedding a webview (egui is a GPU canvas, not HTML/CSS).

use crate::config::{Config, PaletteSource};
use crate::ipc::Frame;
use crate::visual::{self, visual_kind, Visual, VisualKind};
use anyhow::Result;
use std::sync::{Arc, Mutex};

pub struct SettingsApp {
    cfg: Config,
    saved: Config,
    frame: Arc<Mutex<Frame>>,
    visuals: Vec<Visual>,
    /// Focused visualization in the list (drives the right-hand options + the
    /// shared `visual` selection).
    focus: String,
    status: String,
}

impl SettingsApp {
    fn new(cfg: Config, frame: Arc<Mutex<Frame>>) -> SettingsApp {
        let focus = cfg.mini.visual.clone();
        SettingsApp {
            saved: cfg.clone(),
            cfg,
            frame,
            visuals: visual::discover(),
            focus,
            status: String::new(),
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
        // Reset this visual's per-knob overrides to the shader defaults.
        self.cfg.reset_visual(&self.focus);
        self.status = format!("Reset '{}' (unsaved)", self.focus);
    }

    fn selected_visual(&self) -> Option<&Visual> {
        self.visuals.iter().find(|v| v.name == self.focus)
    }

    /// Apply the accent colour from the theme to egui's interactive elements.
    fn theme_style(&self, ctx: &egui::Context) {
        let pal = self.cfg.resolved_palette();
        let a = pal.low; // accent (theme accent in auto mode)
        let accent = egui::Color32::from_rgb(
            (a[0] * 255.0) as u8,
            (a[1] * 255.0) as u8,
            (a[2] * 255.0) as u8,
        );
        let mut style = (*ctx.style()).clone();
        style.visuals.selection.bg_fill = accent;
        style.visuals.selection.stroke.color = egui::Color32::WHITE;
        style.visuals.widgets.active.bg_fill = accent;
        style.visuals.widgets.active.fg_stroke.color = egui::Color32::WHITE;
        style.visuals.hyperlink_color = accent;
        ctx.set_style(style);
    }
}

/// Paint the live spectrum preview using the same palette the renderer uses.
fn draw_preview(ui: &mut egui::Ui, frame: &Frame, cfg: &Config) {
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
        let h = (b * cfg.audio.sensitivity.clamp(0.1, 4.0)).clamp(0.0, 1.0) * rect.height();
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
        let pal = self.cfg.resolved_palette();
        ctx.set_visuals(if pal.is_light {
            egui::Visuals::light()
        } else {
            egui::Visuals::dark()
        });
        self.theme_style(ctx);

        let frame = self.frame.lock().unwrap().clone();

        // ---------------- footer (declared first so it reserves space)
        egui::TopBottomPanel::bottom("footer")
            .min_height(46.0)
            .show(ctx, |ui| {
                ui.add_space(4.0);
                ui.horizontal(|ui| {
                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        if ui.button("Cancel").clicked() {
                            self.cfg = self.saved.clone();
                            self.status = "Cancelled".into();
                        }
                        if ui.button("  Save  ").clicked() {
                            self.save();
                        }
                    });
                });
                ui.add_space(4.0);
            });

        // ---------------- top 42%: live preview
        let preview_h = ctx.content_rect().height() * 0.42;
        egui::TopBottomPanel::top("preview")
            .exact_height(preview_h)
            .show(ctx, |ui| {
                ui.horizontal(|ui| {
                    ui.heading("Preview");
                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        let v = self.selected_visual();
                        let label = v.map(|x| x.display_label()).unwrap_or("—");
                        ui.weak(format!("live · {}", label));
                    });
                });
                ui.add_space(4.0);
                draw_preview(ui, &frame, &self.cfg);
            });

        // ---------------- bottom: list | options
        egui::CentralPanel::default().show(ctx, |ui| {
            ui.add_space(8.0);
            ui.separator();
            ui.add_space(4.0);

            let list_w = ui.available_width() * 0.36;
            ui.horizontal_top(|ui| {
                // Left: vertical visualization list (radio), current ticked.
                ui.allocate_ui(egui::vec2(list_w, ui.available_height()), |ui| {
                    ui.label(egui::RichText::new("Visualization").strong());
                    ui.label(
                        egui::RichText::new("Applies to menu bar, desktop & full screen")
                            .small()
                            .weak(),
                    );
                    ui.add_space(4.0);
                    egui::ScrollArea::vertical()
                        .id_salt("viz-list")
                        .show(ui, |ui| {
                            if self.visuals.is_empty() {
                                ui.weak("no .wgsl files found");
                            }
                            for v in &self.visuals {
                                let selected = v.name == self.focus;
                                let resp =
                                    ui.selectable_label(selected, v.display_label());
                                if resp.clicked() {
                                    self.focus = v.name.clone();
                                    // Shared selection across all modes.
                                    self.cfg.set_visual_all(&v.name);
                                }
                                if v.name == self.cfg.mini.visual {
                                    ui.label(
                                        egui::RichText::new("   ▸ active").small().weak(),
                                    );
                                }
                            }
                        });
                });

                ui.separator();

                // Right: options for the focused visual.
                ui.vertical(|ui| {
                    let sel = self.selected_visual().cloned();
                    match sel {
                        None => {
                            ui.weak("Select a visualization.");
                        }
                        Some(v) => {
                            ui.label(
                                egui::RichText::new(format!("Options — {}", v.display_label()))
                                    .strong(),
                            );
                            ui.add_space(2.0);
                            egui::ScrollArea::vertical()
                                .id_salt("viz-options")
                                .show(ui, |ui| {
                                    // Per-visualization knobs (shared).
                                    if v.params.is_empty() {
                                        ui.weak("This visualization has no knobs.");
                                    }
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

                                    // Reset this visualization (per-viz) lives here.
                                    ui.add_space(6.0);
                                    if ui.button("↺ Reset visualization").clicked() {
                                        self.reset_visual();
                                    }
                                    ui.weak(
                                        egui::RichText::new(
                                            "Restores this visual's knobs to defaults.",
                                        )
                                        .small(),
                                    );

                                    // Per-display fit — the mode nuance.
                                    ui.add_space(10.0);
                                    ui.separator();
                                    ui.label(
                                        egui::RichText::new("Per-display fit").strong(),
                                    );
                                    let kind = visual_kind(&v.name);
                                    match kind {
                                        VisualKind::Bars => {
                                            ui.weak(
                                                egui::RichText::new(
                                                    "Bar visual: the menu bar is only a few px tall, \
                                                     so it needs to fill that space to read any motion. \
                                                     Full screen has room for detail.",
                                                )
                                                .small(),
                                            );
                                            fit_slider(
                                                ui,
                                                &mut self.cfg.mini,
                                                "mini_gain",
                                                "Menu-bar gain",
                                                0.5,
                                                3.0,
                                                1.0,
                                            );
                                            fit_slider(
                                                ui,
                                                &mut self.cfg.mini,
                                                "mini_floor",
                                                "Menu-bar floor (0 = fill up, 1 = pinned low)",
                                                0.0,
                                                1.0,
                                                0.0,
                                            );
                                            fit_slider(
                                                ui,
                                                &mut self.cfg.full,
                                                "full_detail",
                                                "Full-screen detail",
                                                0.0,
                                                1.0,
                                                1.0,
                                            );
                                        }
                                        VisualKind::Circular => {
                                            ui.weak(
                                                egui::RichText::new(
                                                    "Circular/disk visual: shines on the full screen; \
                                                     on the tiny menu bar it's hard to read, so keep it \
                                                     simple there.",
                                                )
                                                .small(),
                                            );
                                            fit_slider(
                                                ui,
                                                &mut self.cfg.full,
                                                "full_quality",
                                                "Full-screen quality",
                                                0.5,
                                                2.0,
                                                1.5,
                                            );
                                            fit_slider(
                                                ui,
                                                &mut self.cfg.mini,
                                                "mini_simplify",
                                                "Menu-bar simplify",
                                                0.0,
                                                1.0,
                                                1.0,
                                            );
                                        }
                                        VisualKind::Other => {
                                            ui.weak(
                                                egui::RichText::new(
                                                    "No special per-display tweaks for this visual.",
                                                )
                                                .small(),
                                            );
                                        }
                                    }

                                    // Audio + colours (shared, not per-mode).
                                    ui.add_space(10.0);
                                    ui.separator();
                                    ui.label(egui::RichText::new("Audio").strong());
                                    ui.add(
                                        egui::Slider::new(
                                            &mut self.cfg.audio.sensitivity,
                                            0.1..=4.0,
                                        )
                                        .text("sensitivity"),
                                    );
                                    ui.add(
                                        egui::Slider::new(
                                            &mut self.cfg.audio.smoothing,
                                            0.0..=1.0,
                                        )
                                        .text("smoothing"),
                                    );
                                    ui.add(
                                        egui::Slider::new(&mut self.cfg.audio.bands, 8..=64)
                                            .text("bands"),
                                    );

                                    ui.add_space(8.0);
                                    ui.label(egui::RichText::new("Colours").strong());
                                    let mut auto =
                                        self.cfg.palette.source == PaletteSource::Auto;
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
                                });
                        }
                    }
                });
            });
        });

        // status line under preview is handled via footer tooltip space; show
        // unsaved / status briefly.
        if self.dirty() {
            ctx.send_viewport_cmd(egui::ViewportCommand::Title(
                "omaviz settings • unsaved".into(),
            ));
        } else if !self.status.is_empty() {
            ctx.send_viewport_cmd(egui::ViewportCommand::Title(
                format!("omaviz settings • {}", self.status),
            ));
        } else {
            ctx.send_viewport_cmd(egui::ViewportCommand::Title("omaviz settings".into()));
        }

        // Live preview needs continuous repaint.
        ctx.request_repaint_after(std::time::Duration::from_millis(16));
    }
}

/// A per-display fit knob stored in a ModeConfig's `extra` table.
fn fit_slider(
    ui: &mut egui::Ui,
    m: &mut crate::config::ModeConfig,
    key: &str,
    label: &str,
    min: f32,
    max: f32,
    default: f32,
) {
    let mut val = *m.extra.get(key).unwrap_or(&default);
    if ui
        .add(egui::Slider::new(&mut val, min..=max).text(label))
        .changed()
    {
        m.extra.insert(key.to_string(), val);
    }
    ui.add_space(2.0);
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
            .with_inner_size([820.0, 660.0])
            .with_min_inner_size([640.0, 520.0])
            .with_title("omaviz settings")
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
