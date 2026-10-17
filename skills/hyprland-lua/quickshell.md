# Hyprland ↔ Quickshell (QML) integration

How a Quickshell/QML status bar **reads and drives Hyprland** on a Lua-configured compositor. This is the Hyprland-side slice only.

> **For the bar itself** — its modules, i3blocks-style blocklets, the dev loop (edit → relaunch `qs` → screenshot), the calendar/`gws` chain, and the Quickshell 0.3.0 **rendering gotchas** (QTBUG-137166 blank-bar, minimal PATH breaking `~/.local/bin` tools, PopupWindow anchoring, icon-resolution no-op, file shadowing) — use the dedicated **`quickshell-bar`** skill. This file does not repeat them.

## Driving Hyprland from QML

- **Switch workspace:** call the object method `HyprlandWorkspace.activate()` — correct on Lua Hyprland. `Hyprland.dispatch("workspace N")` (string dispatch) writes the same IPC path that's flaky/dead under the Lua parser, so don't hand-roll dispatch strings for switching.
- **Fire a dispatch/script the API doesn't expose:** `Quickshell.execDetached(["/path/to/script"])` (e.g. run a `hyprctl eval` Lua toggle). Note the split: the **read/event** side (`rawEvent`, `refreshMonitors`, `lastIpcObject`) is unaffected by the Lua-dispatch problem — only the **write/dispatch** side is.
- **Per-monitor model:** `Hyprland.monitorFor(barScreen)` → `hlMonitor`; workspaces via `Hyprland.workspaces.values.filter(w => w.monitor === hlMonitor)`. Sort **numeric names first (by value), then named ones by DESCENDING id** — Hyprland gives move-script-created named spaces increasingly-negative ids, so the newest appends at the end and existing pills don't reshuffle.

## ⚠️ Special workspaces don't light up the normal pills

A special workspace (scratchpad) is a **separate overlay** from a monitor's active workspace, which breaks two pill assumptions:
- `ws.focused` **never turns true** for it — toggling it changes nothing in a highlight keyed on `.focused`.
- Its state lives on the monitor, not in the workspace list, and the cached monitor object **does not auto-refresh** on toggle.

Surface it with a **dedicated badge**, refreshed on the event:
```qml
property var hlMonitor: Hyprland.monitorFor(barScreen)

Rectangle {                       // the scratchpad badge
    readonly property string special:
        (hlMonitor && hlMonitor.lastIpcObject)
          ? (hlMonitor.lastIpcObject.specialWorkspace.name || "") : ""
    visible: special.length > 0
    Text { text: parent.special.replace(/^special:/, "") }   // strip the "special:" prefix
}

Connections {                     // the piece everyone misses
    target: Hyprland
    function onRawEvent(event) {   // special toggles emit activespecial, NOT workspace
        if (event.name === "activespecial" || event.name === "activespecialv2")
            Hyprland.refreshMonitors();   // invalidate the stale cache → re-drives the badge
    }
}
```
- Without `refreshMonitors()`, `lastIpcObject.specialWorkspace.name` stays **frozen at its bar-startup value** no matter how many times you toggle.
- **Exclude special workspaces from the regular pill list** (`!String(w.name).startsWith("special:")`) or you get a duplicate — a `special:scratch` pill AND the badge.
- ⚠️ The badge watches a specific name (`special:scratch`), so whatever toggles it must use that **same** name via the **string** form `toggle_special("scratch")` (see `SKILL.md`) — the `{name=…}` form toggles the default `special:special` and the badge never lights.
