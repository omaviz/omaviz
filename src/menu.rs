//! Generates the waybar right-click menu (GtkBuilder XML) from installed
//! visuals, plus the matching `menu-actions` block for the waybar module.

use crate::visual;

/// Absolute path to the installed omaviz binary. waybar's environment does NOT
/// have `~/.local/bin` on PATH, so every command the menu runs must be absolute
/// (the module's `exec` already uses an absolute path for the same reason).
fn omaviz_bin() -> String {
    // Allow tests / the daemon to pin the binary path. Otherwise use the
    // running binary's own path (works for installed + dev builds), and only
    // fall back to the known install path as a last resort. waybar's
    // environment does NOT have `~/.local/bin` on PATH, so every command the
    // menu runs must be absolute (the module's `exec` already uses an absolute
    // path for the same reason).
    if let Ok(p) = std::env::var("OMAVIZ_BIN") {
        if !p.is_empty() {
            return p;
        }
    }
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

/// Pop the omaviz menu as a walker --dmenu popup with icons and preselection,
/// then dispatch the chosen action. This is the waybar right-click path when
/// the GtkBuilder XML `menu-file` is unavailable or broken.
pub fn pop(current: &str) -> anyhow::Result<()> {
    use std::io::Write;
    use std::process::{Command, Stdio};
    let bin = omaviz_bin();
    let visuals = visual::discover();
    let current_viz = visuals
        .iter()
        .find(|v| v.name == current)
        .map(|v| v.name.clone())
        .unwrap_or_default();

    let items: Vec<String> = visuals
        .iter()
        .map(|v| {
            let icon = match crate::visual::visual_kind(&v.name) {
                crate::visual::VisualKind::Bars => "▮",
                crate::visual::VisualKind::Circular => "◉",
                crate::visual::VisualKind::Other => "•",
            };
            format!("{icon} {name}", icon = icon, name = v.name)
        })
        .collect();

    let input = items.join("\n");

    // walker's dmenu flags (NOT --prompt/--index, which it rejects):
    //   --placeholder  prompt text
    //   --current      preselect the matching entry (by value)
    //   --exit         close after selection
    let mut args: Vec<String> = vec!["--dmenu".into(), "--placeholder".into(), "omaviz".into(), "--exit".into()];
    if !current_viz.is_empty() {
        args.push("--current".into());
        args.push(current_viz.clone());
    }

    let mut child = Command::new("walker")
        .args(&args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()?;

    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(input.as_bytes());
    }
    let output = child.wait_with_output()?;

    let sel = String::from_utf8_lossy(&output.stdout);
    let sel = sel.trim();
    if sel.is_empty() {
        return Ok(());
    }

    let viz_name = sel.split_whitespace().last().unwrap_or(sel);
    let cmd = format!("{bin} select mini {viz_name}");
    let _ = Command::new("sh").args(["-c", &cmd]).status();
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generate_returns_valid_xml_with_absolute_paths() {
        // Pin the binary to the install path so the test asserts the exact
        // absolute command waybar will run (waybar's env lacks ~/.local/bin).
        unsafe {
            std::env::set_var("OMAVIZ_BIN", "/home/kishan/.local/bin/omaviz");
        }
        let (xml, actions) = generate("bars");
        assert!(xml.starts_with("<?xml"), "XML must start with declaration");
        assert!(xml.contains("<menu id=\"menu\">"), "XML needs menu root");
        assert!(xml.contains("<label>Settings</label>"), "needs Settings item");
        assert!(xml.contains("<label>Exit</label>"), "needs Exit item");
        // Every action must use an absolute path (waybar's env lacks ~/.local/bin).
        assert!(
            xml.contains("/home/kishan/.local/bin/omaviz settings"),
            "settings action must use absolute path"
        );
        assert!(
            actions.contains("settings -> /home/kishan/.local/bin/omaviz settings"),
            "actions block must use absolute path"
        );
    }

    #[test]
    fn generate_includes_a_submenu_for_visualizations() {
        let (xml, _actions) = generate("bars");
        assert!(xml.contains("<submenu>"), "needs a Visualizations submenu");
        assert!(xml.contains("select mini"), "submenu items must select a visual");
    }

    #[test]
    fn generate_actions_map_every_visual() {
        let (_xml, actions) = generate("bars");
        for v in visual::discover() {
            assert!(
                actions.contains(&format!("viz_{} ->", v.name)),
                "missing action for {}",
                v.name
            );
        }
    }
}
