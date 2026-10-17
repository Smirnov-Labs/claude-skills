---
name: quickshell-bar
description: Use when editing, extending, or debugging the hexane Quickshell (Qt6/QML) status bar on Hyprland — the `qs` bar whose config lives in `~/.dotfiles/quickshell/` (symlinked to `~/.config/quickshell/`). Triggers — adding/changing a bar module (workspaces, clock, audio/volume, cpu/mem/temp/net stats, tray, brightness, i3blocks-style blocklets, calendar), or symptoms like the bar rendering all-black/blank after an edit, a module not appearing, a PopupWindow landing in the wrong place, a workspace showing a neutral dot instead of an app icon, a blocklet that "works in the shell but shows stale/empty/`?`" in the bar, or needing the edit→relaunch-qs→check-log→screenshot loop. Covers Quickshell 0.3.0 gotchas (QTBUG-137166 border blanks the bar, qs's minimal PATH breaking ~/.local/bin tools like gws, PopupWindow anchoring, flaky hot-reload, DesktopEntries icon no-op) and the Google Calendar (gws) auth chain + stale hint.
---

# Working on the hexane Quickshell bar

## Overview

The default hexane bar is **Quickshell 0.3.0** (Qt6/QML), running as **`qs`** (replaced waybar because waybar's workspace click-to-switch broke on Hyprland 0.56's Lua dispatch — see the `hyprland-lua` skill). Config lives in **`~/.dotfiles/quickshell/`**, a **directory symlink** to `~/.config/quickshell/`. Layout is **FLAT** — Quickshell auto-imports uppercase-neighbor `.qml` files, so there is **no `qmldir` and no per-file imports of siblings**. Entry point: `shell.qml`.

**Core principle:** hot-reload is unreliable through Edit-tool writes + the dir symlink, so **never trust "I edited it, it's live" — RELAUNCH `qs` and QA visually with a screenshot.** Most "it didn't work" moments are a stale process or a locked screen, not your code.

**Source of truth for facts/gotchas:** `~/docs/docs/systems/hexane/hyprland-bars.md` (KB) and the design spec `~/.dotfiles/docs/superpowers/specs/2026-08-05-quickshell-bar-design.md`. This skill is the *how-to-work-on-it* companion.

## When this applies

- The bar renders **all-black or blank** after an edit (or in a screenshot).
- A module you added doesn't show, or `qs` won't start / logs a QML error.
- A **PopupWindow** (e.g. a slider) lands at bar-level or off to the side.
- A workspace shows a **neutral dot** instead of the window's app icon.
- A **blocklet** script works when you run it but the bar shows **stale/empty/`?`**.
- You need to add/restyle a module, or run the **edit → relaunch → screenshot** loop.

## The dev loop (do this every time)

1. **Edit** `~/.dotfiles/quickshell/*.qml` (or `lib/*`). The symlink means changes are on disk immediately.
2. **Relaunch** (never rely on hot-reload):
   ```bash
   pkill -x qs; hyprctl dispatch 'hl.dsp.exec_cmd("qs >/tmp/qs.log 2>&1")'
   ```
   ⚠️ Launch via **`hyprctl dispatch exec`** — the agent shell sandbox kills direct GUI spawns (exit 144). (`hl.dsp.exec_cmd` is the Lua dispatch; see the `hyprland-lua` skill.)
3. **Check the log:** `grep -iE 'error|warning|invalid|not a type' /tmp/qs.log`. `"Configuration Loaded"` = clean parse; QML errors print `file:line`. (An `sni.watcher` StatusNotifierItem warning is benign.)
4. **Screenshot to QA** (see below). Iterate.

## File map (`~/.dotfiles/quickshell/`)

| File | Role |
|---|---|
| `shell.qml` | Entry. `Variants{ model: Quickshell.screens.filter(s=>s.name!=="HDMI-A-2") }` → one `Bar` per monitor. Timers for `Hyprland.refreshToplevels()` + `cal-notify`. |
| `Theme.qml` | **Singleton** palette + metrics. ⚠️ needs `import QtQuick` for the `color` type. `variant` "pastel"/"vivid" reskins everything. |
| `Bar.qml` | `PanelWindow`, `color:"transparent"` + inner rounded `Rectangle` (**NO border** — see gotcha 1). left=Workspaces, center=Clock+worldclock+calendar chips, right=usage+Brightness+Audio+Stats+IdleToggle+SysTray. |
| `Workspaces.qml` | Per-monitor pills, sorted by id, click=`HyprlandWorkspace.activate()`, app icons + `overrideIcon` map (gotcha 6). |
| `Blocklet.qml` | Generic i3blocks-script runner (see "Adding a blocklet"). |
| `Audio.qml` | Pipewire sink (needs `PwObjectTracker`); left-click = slider `PopupWindow`, scroll ±5%, right-click mute. |
| `Sys.qml`/`Stats.qml` | `Sys` singleton runs `lib/sysinfo.sh` q2s → cpu/mem/temp/net/load; `Stats` renders chips. |
| `Clock.qml` `SysTray.qml` `IdleToggle.qml` `Brightness.qml` | Center clock; tray; idle-inhibitor toggle; backlight. |
| `lib/sysinfo.sh` | Emits `idle cpu mem temp rx tx load` (coretemp hwmon by NAME, iface via /proc/net/route). |
| `lib/cal-next` `lib/cal-notify` | Calendar (see "Calendar"). |

## ⚠️ Gotchas that cost hours

1. **Black/blank bar = QTBUG-137166 ("hole in my window").** A Rectangle **`border`** on a `color:"transparent"` window blanks the ENTIRE bar on screen. Fix = **no border**. This is NOT a grim/dmabuf capture limit — grim captures the bar fine once it actually renders. Don't re-conclude "grim can't capture NVIDIA dmabuf" (false).
2. **Blocklet works in your shell but the bar shows stale/empty/`?` = qs's minimal PATH.** qs launches blocklet processes with `PATH=/usr/local/bin:/usr/bin` — **no `~/.local/bin`**. Any script shelling out to a `~/.local/bin` tool (`gws`, etc.) must `export PATH="$HOME/.local/bin:$PATH"` itself or the call silently fails and the script serves stale/empty output. Verify: `env PATH=/usr/local/bin:/usr/bin command -v <tool>` (empty = it's the bug).
3. **Edited a `.qml` but nothing changed** → hot-reload is flaky through Edit + dir-symlink. **Relaunch `qs`** (step 2).
4. **`X.qml` breaks / "X is not a type"** → a neighbor file named like a Quickshell type **shadows** it (hit with `IdleInhibitor.qml` → renamed `IdleToggle.qml`). Also `Theme.qml` needs `import QtQuick` for the `color` value type.
5. **PopupWindow lands at bar-level or wrong side** → setting `anchor.rect.x` **alone** collapses the anchor rect to zero-height at y=0. Leave `anchor.rect` at the item bounds and align via flags: `anchor.edges: Edges.Bottom | Edges.Right` + `anchor.gravity: Edges.Bottom | Edges.Left` (drop-down, right-aligned, stays on-screen). Dismiss on click-away: `HyprlandFocusGrab { windows:[popup]; active: popup.visible; onCleared: popup.visible=false }`. A visual gap = transparent popup window + inner `Rectangle` `topMargin`.
6. **Workspace shows a neutral dot, not an app icon** → `DesktopEntries.heuristicLookup` is a **NO-OP** in this 0.3.0. Resolution is `hasThemeIcon(class)` ONLY (the window CLASS must be a valid icon name in the Adwaita→hicolor chain, **NOT** Papirus) **OR** `/usr/share/pixmaps/<class>.{png,svg}`. Anything else (Papirus-only, hashed/prefixed class like Telegram's `org.telegram.desktop.<hash>`) needs an `overrideIcon` entry — a substring-of-lowercased-class → `file://` map in `Workspaces.qml`.
7. **Binding loop on `Bar.visible`** → filter monitors in `shell.qml`'s `Variants` model (`.filter(s=>s.name!==…)`), not via a `visible:` binding on `screen`.
8. **All-black screenshots but qs is running** → the **screen is locked** (the locker covers the bar), not a render bug. Confirm bar health another way (see QA).

## Adding a module or blocklet

- **New QML module:** create `Foo.qml` (Uppercase), then drop `Foo {}` into a Row in `Bar.qml`. No imports/qmldir needed (flat auto-import). Pull colors/metrics from `Theme.*`.
- **Reuse an i3blocks script** (`~/.dotfiles/i3/blocklets/*` or `lib/*`):
  ```qml
  Blocklet { exec: "/abs/path"; args: ["mode"]; instance: "claude:foo"; flat: true; interval: 60000 }
  ```
  Script emits ≤3 lines: **full_text, short_text, color(`#hex`)**. `instance` → `BLOCK_INSTANCE` env. `flat:true` = no chip background (center cluster). The emitted `#hex` becomes the **text color** (empty → `Theme.subtext`). The chip **auto-hides** when full_text is empty.
- **Workspace click** dispatches via `HyprlandWorkspace.activate()` — do NOT hand-roll a dispatch string.
- **Scratchpad / special-workspace indicator:** special workspaces are a separate overlay and do NOT light up the normal pills (`ws.focused` never turns true for them, and the monitor cache doesn't auto-refresh on toggle). For a `◆ scratch` badge — read `hlMonitor.lastIpcObject.specialWorkspace.name`, refresh on the `activespecial` event, and exclude specials from the pill filter — see the **`hyprland-lua`** skill's `quickshell.md`.

## Screenshot / interaction QA

- **grim per-output + crop** (DP-1 is 3840-wide; bar strip ≈ y=0..60):
  ```bash
  grim -o DP-1 -t png /tmp/b.png
  magick /tmp/b.png -crop 1000x60+1620+2 +repage /tmp/c.png   # then view /tmp/c.png
  ```
- **hypr-cua MCP** for clicks/drags: `screenshot(output="DP-1")` returns a scaled image + `frame_id`; then `click(x,y,frame_id)` / `drag(x1,y1,x2,y2,frame_id)` in that frame's pixel space (e.g. open the Audio popup, drag the slider, verify with `wpctl get-volume @DEFAULT_AUDIO_SINK@`).
- ⚠️ **Locked screen → black.** Verify the bar is actually rendering with (works through the lock):
  ```bash
  hyprctl layers -j | jq -r 'to_entries[] | .key as $o | .value.levels | to_entries[] | .value[]? | select(.namespace|test("quickshell";"i")) | "\($o): \(.w)x\(.h)"'
  # expect two surfaces: DP-1 + DP-2, ~3820x46
  ```

## Calendar (`lib/cal-next` + `lib/cal-notify`)

- Two center chips: **`cal-next current`** (`●` happening now, mint, counts to END) + **`cal-next`** (`◷` next, counts to START, yellow<15m/red<5m). `cal-notify` fires **swaync** at 10/5/1 min (driven by the `shell.qml` 1-min Timer — no systemd). Merges ALL ~17 calendars (Google has no all-calendars endpoint).
- Cache `~/.cache/quickshell-cal/events.json`: atomic (tmp+mv), **`flock`-serialized** (3 callers), **15-min TTL** (`CAL_REFRESH_TTL`), greys to **`(stale)`** when older than 2× TTL (`CAL_STALE_AFTER`).
- ⚠️ **gws auth chain** (ALL required, in order): `gws auth login --services gmail,calendar --readonly` → **delete stale `~/.config/gws/token_cache.json`** (an old pre-scope access token keeps 403'ing "insufficient scopes") → the account needs **`roles/serviceusage.serviceUsageConsumer`** on project **`internal-ops-slabs`** (a personal acct consuming the org-project OAuth client 403s "Caller does not have required permission to use project" until granted). Broken → chip shows `cal ?`. Creds stay in `~/.config/gws`, **OUT of the dotfiles**.
- Force a refetch: `CAL_REFRESH_TTL=0 ~/.config/quickshell/lib/cal-next`. Preview the stale look: `CAL_STALE_AFTER=-1 CAL_NO_FETCH=1 cal-next`.

## Commit hygiene ⚠️

- `~/.dotfiles` is git **`master`** and **multiple agent sessions edit it concurrently**. **Stage only your explicit files** (`git add quickshell/Foo.qml …`) — **never `git add -A`/`-am`**. The user keeps *uncommitted* edits in `hypr/hyprland.lua`, `waybar/config.jsonc`, `claude/settings.json` — **don't touch/stage them**.
- Durable facts → the KB `~/docs/docs/systems/hexane/hyprland-bars.md` (source of truth). `~/docs` is its own git repo with its own churn — commit only your one doc file there too.
- Calendar tokens/creds must **never** enter the dotfiles (they live in `~/.config/gws`).
- End commit messages with the `Co-Authored-By: Claude …` trailer.

## Common mistakes

| Mistake | Fix |
|---|---|
| Edited a `.qml`, assumed it's live | Relaunch `qs`; check `/tmp/qs.log`; screenshot |
| Rectangle `border` on the transparent bar window | Remove it (QTBUG-137166 blanks the whole bar) |
| "grim can't capture the NVIDIA bar" | False — it was the border bug or a locked screen |
| Blocklet fetch silently fails from the bar | `export PATH="$HOME/.local/bin:$PATH"` in the script |
| `anchor.rect.x` to place a PopupWindow | Use `anchor.edges`/`anchor.gravity` flags instead |
| Named a file after a Quickshell type | Rename it (shadowing → "X is not a type") |
| `git add -A` in ~/.dotfiles | Stage only your files; parallel sessions + user edits coexist |
| Calendar chip `cal ?` | Walk the gws auth chain (scope → token_cache → serviceUsageConsumer IAM) |
