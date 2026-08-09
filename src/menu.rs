//! Generates the waybar right-click menu (GtkBuilder XML) from installed
//! visuals, plus the matching `menu-actions` block for the waybar module.

use crate::visual;

/// Absolute path to the installed omaviz binary. waybar's environment does NOT
/// have `~/.local/bin` on PATH, so every command the menu runs must be absolute
/// (the module's `exec` already uses an absolute path for the same reason).
fn omaviz_bin() -> String {
    // Prefer the running binary's own path; fall back to the known install path.
    std::env::current_exe()
        .ok()
        .and_then(|p| p.to_str().map(|s| s.to_string()))
        .unwrap_or_else(|| "/home/kishan/.local/bin/omaviz".to_string())
}

/// Build the menu. `current` is the active mode string (unused for mode rows
/// now that modes are implicit, but kept for interface compatibility).
pub fn generate(_current: &str) -> (String, String) {
    let bin = omaviz_bin();
    let visuals = visual::discover();
    let mut submenu_items = String::new();
    for v in &visuals {
        submenu_items.push_str(&format!(
            "<item><label>{}</label><action name=\"viz_{}\">{} select mini {}</action></item>\n",
            v.name, v.name, bin, v.name
        ));
    }

    let xml = format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<interface>
  <menu id="menu">
    <section>
      <item>
        <label>Settings</label>
        <action name="settings">{} settings</action>
      </item>
      <submenu>
        <label>Visualizations</label>
        {submenu_items}
      </submenu>
      <item>
        <label>Turn off</label>
        <action name="mode_off">{} off</action>
      </item>
      <item>
        <label>Exit</label>
        <action name="quit">{} quit</action>
      </item>
    </section>
  </menu>
</interface>
"#,
        bin, bin, bin, submenu_items = submenu_items,
    );

    // The corresponding waybar "menu-actions" block. The `win.*` actions are
    // emitted by omaviz when registered via `omaviz menu --actions`; we map
    // them directly to omaviz subcommands so no D-Bus registration is needed.
    let actions = visuals
        .iter()
        .map(|v| format!("viz_{} -> {} select mini {}", v.name, bin, v.name))
        .collect::<Vec<_>>()
        .join("\n");
    let menu_actions = format!(
        "{}\nsettings -> {} settings\nmode_off -> {} off\nquit -> {} quit",
        actions, bin, bin, bin
    );

    (xml, menu_actions)
}
