//! Generates the waybar right-click menu (GtkBuilder XML) from installed
//! visuals, plus the matching `menu-actions` block for the waybar module.

use crate::visual;

/// Absolute path to the installed omaviz binary. waybar's environment does NOT
/// have `~/.local/bin` on PATH, so every command the menu runs must be absolute
/// (the module's `exec` already uses an absolute path for the same reason).
fn omaviz_bin() -> String {
    // Prefer the installed binary at the known absolute path (waybar's env
    // lacks ~/.local/bin on PATH, so bare `omaviz` fails there).
    let install = format!("{}/.local/bin/omaviz", std::env::var("HOME").unwrap_or_default());
    if std::path::PathBuf::from(&install).exists() {
        return install;
    }
    // Fall back to the running binary's own path (works for installed + dev builds).
    std::env::current_exe()
        .ok()
        .and_then(|p| p.to_str().map(|s| s.to_string()))
        // Last resort: bare command (will fail if not on PATH).
        .unwrap_or_else(|| "omaviz".to_string())
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
    
    // Find the index of the current visualization for walker's --current flag
    // walker's --current expects a 0-based index, not a value
    let current_idx = visuals.iter().position(|v| v.name == current).unwrap_or(0);

    // Build menu items: visuals first, then Settings, Turn off, Exit
    let mut items: Vec<String> = visuals
        .iter()
        .map(|v| format!("▮ {}", v.name))
        .collect();
    items.push("────────────────".to_string());
    items.push("⚙ Settings".to_string());
    items.push("Turn off".to_string());
    items.push("✕ Exit".to_string());

    let input = items.join("\n") + "\n";

    // walker's dmenu flags (NOT --prompt/--index, which it rejects):
    //   --placeholder  prompt text
    //   --current      preselect the matching entry (by 0-based INDEX)
    //   --exit         close after selection
    let mut args: Vec<String> = vec!["--dmenu".into(), "--placeholder".into(), "menu".into(), "--exit".into()];
    if !visuals.is_empty() {
        args.push("--current".into());
        args.push(current_idx.to_string());
    }

    let mut child = Command::new("walker")
        .args(&args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()?;

    // Write menu items to walker's stdin and explicitly close it
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(input.as_bytes());
        // Explicitly drop to close the pipe
        drop(stdin);
    }

    // Wait for walker to finish (user makes selection or cancels)
    let output = child.wait_with_output()?;

    let sel = String::from_utf8_lossy(&output.stdout);
    let sel = sel.trim();
    if sel.is_empty() {
        return Ok(());
    }

    // Dispatch the chosen action
    if sel.starts_with("⚙") {
        let _ = Command::new(&bin).arg("settings").status();
    } else if sel == "Turn off" {
        let _ = Command::new(&bin).arg("off").status();
    } else if sel.starts_with("✕") {
        let _ = Command::new(&bin).arg("quit").status();
    } else {
        // Extract visualization name (strip icon prefix)
        let viz_name = sel.trim_start_matches("▮ ").trim();
        let _ = Command::new(&bin).args(["select", "mini", viz_name]).status();
    }
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
