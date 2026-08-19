# ADR-0002: Expose "Wave" in the settings-panel VISUALIZATION selector

| | |
|---|---|
| **Status** | Accepted (to implement in v7.6.x) |
| **Date** | 2026-08-19 |
| **Author** | architect (@architect) |
| **Task** | T-007 (roadmap #16) |
| **Applies to** | `plugin/Panel.qml` (VISUALIZATION ButtonGroup), `plugin/Model.js` (commit), `plugin/Desktop.qml` (already maps `wave → Wave`) |
| **Supersedes** | none |
| **Superseded by** | none |

## 1. Context

The GPU **Wave** visual (GL visual-code `2`, see `ADR/0001-wave-continuous-carrier.md`)
shipped in v7.6 but is **not reachable from the settings panel**. The panel
VISUALIZATION selector in `Panel.qml` is:

```qml
ButtonGroup {
  options: ["Bar", "Oscilloscope"]
  value: (root.readCfg("visual", "mini") || "equalizer") === "oscilloscope" ? "Oscilloscope" : "Bar"
  onChanged: function(v) {
    var key = v === "Oscilloscope" ? "oscilloscope" : "equalizer"
    commit("visual", '"' + key + '"', "mini")
    commit("visual", '"' + key + '"', "desktop")
  }
}
```

Wave currently only works via a hand-edited `config.toml`
(`[desktop] visual = "wave"`), which `Desktop.qml` already maps to the GL
`Wave` mode. `visuals/wave.toml` already declares `name = "wave"`,
`label = "Wave"`. So the plumbing (engine frame, GL branch, Desktop mapping)
is complete; only the panel selector is missing the third option.

## 2. Decision

Add **`"Wave"`** to the panel VISUALIZATION selector so all three GPU modes are
user-selectable. Exact specification:

- **UI label:** `Wave` — text only, **no icon**. This matches `Bar` and
  `Oscilloscope`, which are text-only `ButtonGroup` options; no iconography is
  used anywhere in this group, so adding an icon would be inconsistent. (The
  `visuals/wave.toml` `label = "Wave"` is the canonical string and is reused
  verbatim.)
- **Selector options become:** `["Bar", "Oscilloscope", "Wave"]`.
- **Commit behavior:** selecting `Wave` commits `visual = "wave"` to **both**
  `[mini]` and `[desktop]` sections, identical to the existing Bar/Oscilloscope
  handler:
  ```qml
  var key = v === "Oscilloscope" ? "oscilloscope"
          : v === "Wave"        ? "wave"
          : "equalizer"
  commit("visual", '"' + key + '"', "mini")
  commit("visual", '"' + key + '"', "desktop")
  ```
- **Value mapping (initial selection):** `readCfg("visual","mini")` of
  `wave` → display `Wave`; `oscilloscope` → `Oscilloscope`; anything else
  (`equalizer`/absent) → `Bar`.
- **Config override stays valid:** the hand-edited `[desktop] visual = "wave"`
  remains a supported override and now simply equals what the panel writes; no
  override semantics change.

## 3. Consequences

- **Positive:** Wave is first-class selectable in the GUI; closes roadmap #16.
  No engine change, no new control texture rows, no shader change — pure
  GUI-exposure of an already-working path.
- **Positive:** `Desktop.qml`'s existing `equalizer→Bars / oscilloscope→
  Oscilloscope / wave→Wave` mapping means the detached window immediately
  honors the selection.
- **Negative / cost:** none material. The preview (`VisualCanvas.qml`
  Canvas-2D) renders a *different* "Wave" (mirrored sine ribbon, `drawWave`) —
  that is the legacy Canvas-2D visual and is **unrelated** to the GL WAVE
  visual (ADR-0001). The panel preview for the GL Wave mode will show the
  Canvas-2D wave stand-in only as a thumbnail; the true GL WAVE renders in the
  detached desktop window. This mirror already exists for Bar/Oscilloscope and
  is acceptable (documented in spec §8/§10).
- **Test gate (tester, via dev):** add a `model.test.cjs` assertion that
  `commit("visual","wave","desktop")` round-trips through `readConfigFromText`
  as `visualDesktop === "wave"` and that `Panel.qml`'s selector now lists three
  options including `Wave`. (Exact count to be confirmed by the test suite run;
  do not over-claim a specific number here.)

## 4. Rejected alternatives

- **Auto-detect Wave availability:** rejected — the selector should present all
  shipped modes uniformly; availability is static (all three ship in v7.6).
- **Icon for Wave only:** rejected — inconsistent with the existing text-only
  group; adds an asset with no functional benefit.

## 5. References
- `plugin/Panel.qml` — VISUALIZATION ButtonGroup (lines ~179-191).
- `plugin/Desktop.qml` — `visualName` mapping (`wave → "Wave"`).
- `plugin/visuals/wave.toml` — `name = "wave"`, `label = "Wave"`.
- `ADR/0001-wave-continuous-carrier.md` — the WAVE GPU visual design.
- APPLICATION_SPEC.md §6 (Wave in the panel selector), §10 (visuals), §13 (#16).
