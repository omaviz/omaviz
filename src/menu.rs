//! Generates the waybar right-click menu (GtkBuilder XML) from installed
//! visuals, plus the matching `menu-actions` block for the waybar module.

use crate::visual;

/// Build the menu. `current` is the active mode string (unused for mode rows
/// now that modes are implicit, but kept for interface compatibility).
pub fn generate(_current: &str) -> (String, String) {
    let visuals = visual::discover();
    let mut submenu_items = String::new();
    for v in &visuals {
        submenu_items.push_str(&format!(
            "<item><label>{}</label><action name=\"viz_{}\">omaviz select mini {}</action></item>\n",
            v.name, v.name, v.name
        ));
    }

    let xml = format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<interface>
  <menu id="menu">
    <section>
      <item>
        <label>Settings</label>
        <action name="settings">omaviz settings</action>
      </item>
      <submenu>
        <label>Visualizations</label>
        {submenu_items}
      </submenu>
      <item>
        <label>Turn off</label>
        <action name="mode_off">omaviz off</action>
      </item>
      <item>
        <label>Exit</label>
        <action name="quit">omaviz quit</action>
      </item>
    </section>
  </menu>
</interface>
"#,
        submenu_items = submenu_items,
    );

    // The corresponding waybar "menu-actions" block. The `win.*` actions are
    // emitted by omaviz when registered via `omaviz menu --actions`; we map
    // them directly to omaviz subcommands so no D-Bus registration is needed.
    let actions = visuals
        .iter()
        .map(|v| format!("viz_{} -> omaviz select mini {}", v.name, v.name))
        .collect::<Vec<_>>()
        .join("\n");
    let menu_actions = format!(
        "{}\nsettings -> omaviz settings\nmode_off -> omaviz off\nquit -> omaviz quit",
        actions
    );

    (xml, menu_actions)
}

/// Pop the omaviz menu as a dmenu-style launcher (walker --dmenu) and dispatch
/// the chosen action. Used by waybar's right-click (`omaviz menu`). Returns the
/// label/command of the chosen item, or None if cancelled.
pub fn pop() -> Option<String> {
    let visuals = visual::discover();
    // (label, command) pairs shown in the menu.
    let mut items: Vec<(String, String)> = Vec::new();
    items.push(("Settings".into(), "omaviz settings".into()));
    for v in &visuals {
        items.push((
            format!("Visualization: {}", v.name),
            format!("omaviz select mini {}", v.name),
        ));
    }
    items.push(("Turn off".into(), "omaviz off".into()));
    items.push(("Exit".into(), "omaviz quit".into()));

    let list = items
        .iter()
        .map(|(l, _)| l.as_str())
        .collect::<Vec<_>>()
        .join("\n");

    use std::io::Write;
    use std::process::{Command, Stdio};

    let mut child = Command::new("walker")
        .args(["--dmenu"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .ok()?;
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(list.as_bytes());
        let _ = stdin.flush();
    }
    let out = child.wait_with_output().ok()?;
    if !out.status.success() {
        return None;
    }
    let chosen = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if chosen.is_empty() {
        return None;
    }
    // Map the chosen label back to its command.
    items
        .into_iter()
        .find(|(label, _)| label == &chosen)
        .map(|(_, cmd)| cmd)
}
