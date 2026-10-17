# Wayland switcher / launcher on Lua Hyprland (fuzzel, not rofi)

## Why fuzzel, not rofi

rofi on this box is the **X11/XWayland** build — its built-in window modi are **blind to native-Wayland windows**. So a rofi window switcher shows nothing useful. Route window/workspace switching through `hyprctl` instead, and use **fuzzel** (Wayland-native) as the picker. (A rofi 2.0.0 Wayland fork is fine for simple text menus like rename/move, but not for enumerating windows.)

## Pattern: one merged dmenu switcher

`~/.dotfiles/hypr/scripts/hypr-switch` (SUPER+Space) is a single `fuzzel --dmenu --index` list that merges: open **windows** (focus + jump), **workspaces** (focus), a few **favorite apps** (spawn), and **"All apps…"** (re-open fuzzel in drun mode). Techniques worth reusing:

- **`--index` decouples display from action.** fuzzel returns the chosen line NUMBER; map it back to a parallel bash `actions[]` array (`kind|payload`). Nothing ever parses display text → robust to titles containing any characters.
- **dmenu icon protocol** for per-row category dots: each line is `label\0icon\x1f/path.png`. A NUL byte can't live in a bash variable → assemble each line with `printf '%s\0icon\x1f%s\n'` at feed time, keyed off the action kind.
- **Dedup launch vs switch:** before adding a "launch Slack" row, read `hyprctl clients -j | jq -r '.[].class'` — if Slack's window is already open, DROP the launch row, so typing "slack" resolves to its window/workspace (a switch), not a no-op re-launch of a running app.
- Windows carry their **center** (`at[i] + size[i]/2`) in the payload so focus can warp the cursor onto them (see focus bugs). Workspaces: positive id → focus by id; named (negative id) → focus by `"name:<name>"`.

## ⚠️ Two focus-landing bugs (both must be handled)

A naive "focus the chosen window" dispatch loses focus in two *different* ways — the switcher must defeat both:

1. **follow_mouse steals it.** `input:follow_mouse=1` snaps focus to whatever's under the cursor. Fix: focus the window AND warp the cursor onto its center in ONE atomic eval, so no cursor-driven re-focus sneaks between them:
   ```
   hl.dispatch(hl.dsp.focus({ window = "address:0x…" })); hl.dispatch(hl.dsp.cursor.move({ x = cx, y = cy }))
   ```
2. **The launcher teardown race.** When fuzzel closes it releases its keyboard grab and Hyprland returns focus to the *previously* focused window — AFTER your dispatch. A single immediate dispatch loses the race (the workspace visibly switches but the keyboard stays put). Fix: run the focus dispatch **detached and re-asserted** a few times over ~150 ms so one lands after teardown:
   ```bash
   setsid -f bash -c 'for _ in 1 2 3; do hyprctl eval "$1" >/dev/null 2>&1; sleep 0.06; done' _ "$lua"
   ```
   Pass the Lua as argv `$1` to sidestep nested quoting.

## Workspace rename / move (i3-parity binds)

Scripts `hypr-rename` / `hypr-move`, menu via the rofi Wayland fork. Dispatch calls:
- **rename:** `hl.dsp.workspace.rename({ workspace = <id>, name = "<new>" })`
- **move window:** `hl.dsp.window.move({ workspace = <N | "name:X">, follow = <bool> })`

⚠️ Named workspaces **MUST** use the `name:` prefix — a bare non-existent name throws `Invalid workspace`. `follow=false` = silent move to an existing target; `follow=true` = create + switch.

⚠️ **`renameworkspace` keeps the numeric id** → a renamed numbered workspace still squats its old slot. To get a *pure* named workspace (which needs a NEGATIVE id), move its windows onto `name:<x>` rather than renaming in place. Relocate a named ws to a monitor with `hl.dsp.workspace.move({ workspace = "name:x", monitor = "DP-1" })`.
