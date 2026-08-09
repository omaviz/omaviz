//! Context menu.
//!
//! The right-click menu is now rendered by waybar itself from a GtkBuilder XML
//! file (`omaviz menu --out <xml>`, referenced by the module's `menu-file`
//! key). This module is kept as a placeholder in case we later want an
//! in-app fallback; it is intentionally unused.

#[allow(dead_code)]
pub fn run(_cfg: crate::config::Config) -> anyhow::Result<()> {
    Ok(())
}
