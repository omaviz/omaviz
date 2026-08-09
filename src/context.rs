//! Right-click context window (egui).
//!
//! Replaces the old dmenu-style popup. Shows a small floating window with a
//! vertical list of visualizations (the currently-selected one pre-ticked),
//! plus Settings / Turn off / Exit actions. Selecting an item dispatches the
//! matching `omaviz` subcommand and closes the window.

use crate::config::Mode as CfgMode;
use crate::visual::{self, Visual};
use anyhow::Result;
use std::process::Command;
use std::sync::Arc;
use std::sync::Mutex;

/// Which mode the context window edits (driven by the current on-screen mode).
/// Note: the persisted AppMode is only Off/Mini/Desktop — Full is launched
/// transiently without changing the stored mode, so we treat it as Desktop.
fn target_mode() -> CfgMode {
    match crate::mode::current() {
        crate::mode::Mode::Desktop => CfgMode::Desktop,
        _ => CfgMode::Mini,
    }
}

fn dispatch(args: &[&str]) {
    // Run the chosen omaviz subcommand detached from this window process.
    let _ = Command::new("omaviz").args(args).spawn();
}

pub struct ContextApp {
    cfg: crate::config::Config,
    visuals: Vec<Visual>,
    /// Focused visualization in the list (drives preselection highlight).
    focus: String,
    /// Bumped when the window should close.
    close: Arc<Mutex<bool>>,
}

impl ContextApp {
    fn new(cfg: crate::config::Config, close: Arc<Mutex<bool>>) -> ContextApp {
        let target = target_mode();
        let focus = cfg.mode(target).visual.clone();
        ContextApp {
            visuals: visual::discover(),
            focus,
            cfg,
            close,
        }
    }

    fn choose(&self, name: &str) {
        let target = target_mode();
        let tgt = match target {
            CfgMode::Desktop => "desktop",
            CfgMode::Full => "full",
            CfgMode::Mini => "mini",
        };
        dispatch(&["select", tgt, name]);
        *self.close.lock().unwrap() = true;
    }
}

impl eframe::App for ContextApp {
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

        egui::CentralPanel::default().show(ctx, |ui| {
            ui.vertical_centered(|ui| {
                ui.heading("omaviz");
            });
            ui.separator();

            ui.label(egui::RichText::new("Visualization").strong());
            egui::ScrollArea::vertical()
                .id_salt("ctx-viz")
                .max_height(220.0)
                .show(ui, |ui| {
                    let current = self.cfg.mode(target_mode()).visual.clone();
                    for v in &self.visuals {
                        let selected = v.name == self.focus;
                        let label = egui::RichText::new(v.display_label());
                        let resp = ui.selectable_label(selected, label);
                        if resp.clicked() {
                            self.focus = v.name.clone();
                        }
                        // Clicking the row (or its "use" tick) selects it.
                        if resp.clicked() {
                            let name = v.name.clone();
                            self.choose(&name);
                            return;
                        }
                        if v.name == current {
                            ui.label(
                                egui::RichText::new("   ▸ active").small().weak(),
                            );
                        }
                    }
                    if self.visuals.is_empty() {
                        ui.weak("no visualizations found");
                    }
                });

            ui.separator();

            ui.horizontal(|ui| {
                if ui.button("⚙ Settings").clicked() {
                    dispatch(&["settings"]);
                    *self.close.lock().unwrap() = true;
                }
            });
            ui.horizontal(|ui| {
                if ui.button("⏸ Turn off").clicked() {
                    dispatch(&["off"]);
                    *self.close.lock().unwrap() = true;
                }
                if ui.button("⏏ Exit").clicked() {
                    dispatch(&["quit"]);
                    *self.close.lock().unwrap() = true;
                }
            });
        });

        if *self.close.lock().unwrap() {
            ctx.send_viewport_cmd(egui::ViewportCommand::Close);
        }
    }
}

pub fn run(cfg: crate::config::Config) -> Result<()> {
    // Singleton: if already open, just focus it.
    let Some(_guard) = crate::instance::acquire(crate::instance::WindowKind::Settings)? else {
        eprintln!("omaviz: context menu already open, focusing it");
        crate::instance::focus_existing(crate::instance::WindowKind::Settings);
        return Ok(());
    };

    let close = Arc::new(Mutex::new(false));
    let opts = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([280.0, 360.0])
            .with_title("omaviz")
            .with_app_id("omaviz")
            // A context menu should not steal focus aggressively; keep it above.
            .with_decorations(true),
        ..Default::default()
    };

    eframe::run_native(
        "omaviz",
        opts,
        Box::new(move |_cc| Ok(Box::new(ContextApp::new(cfg, close)))),
    )
    .map_err(|e| anyhow::anyhow!("context window: {e}"))?;
    Ok(())
}
