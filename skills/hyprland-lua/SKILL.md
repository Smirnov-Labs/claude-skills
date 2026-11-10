---
name: hyprland-lua
description: "Use when scripting or debugging Hyprland configured in Lua (hyprland.lua, 0.55+): Lua parse errors from `hyprctl dispatch` or `keyword`, a special workspace that toggles wrong or won't hide, workspace renames, a Quickshell bar not tracking workspaces."
---

# Controlling a Lua-configured Hyprland

## Overview

Some Hyprland setups are configured in **Lua** (`~/.config/hypr/hyprland.lua`) instead of `hyprland.conf` — **native since Hyprland 0.55** (embedded Lua 5.4; the compositor loads `hyprland.lua` in place of `hyprland.conf` when it exists — not a plugin). On these the **whole IPC surface is parsed as Lua** — classic `hyprctl dispatch <name>` / `hyprctl keyword` are DEAD and error. All runtime control goes through `hyprctl eval '<lua>'` wrapping `hl.dispatch(hl.dsp.X(...))`.

**Core principle:** when a dispatch keeps hitting the wrong or *default* target, suspect the **argument form (string vs table)** before blaming keybinds, focus, races, or "another agent."

## When this applies

- `hyprctl dispatch workspace 3` → `')' expected near '3'` (any Lua parse error)
- `hyprctl keyword …` → *"keyword can't work with non-legacy parsers. Use eval."*
- A scratchpad/special workspace won't hide, or an empty `special:special` keeps appearing
- Focus dispatches land on the wrong window/monitor (`input:follow_mouse=1`)
- You need to script show/hide/move/focus at runtime, or inspect live state

Detect via: `~/.config/hypr/hyprland.lua` exists / no `hyprland.conf`, or a failing `hyprctl dispatch`.

## Also in this skill (load on demand)

| File | For |
|---|---|
| `launcher.md` | Building a **Wayland-native switcher/launcher** (fuzzel over rofi), the two focus-landing bugs, workspace rename/move |
| `quickshell.md` | **Hyprland ↔ Quickshell/QML** integration: driving Hyprland from QML, the special-workspace badge + `activespecial` refresh (the Hyprland side only, not bar internals or Quickshell's own gotchas) |

## Runtime dispatch — the wrapper

```bash
hyprctl eval 'hl.dispatch(hl.dsp.<path>(<args>))'
```
- `eval` prints `ok` on success (return values swallowed) but **surfaces Lua errors** — use that to enumerate an unknown dispatcher table:
  ```bash
  hyprctl eval 'local s="" for k in pairs(hl.dsp.workspace) do s=s..k.."," end error(s)'
  ```
- `hyprctl reload` re-executes the Lua from disk. Safe *if* autostart is gated behind `hl.on("hyprland.start", …)` (reload won't re-run those execs → no duplicate apps).
- **Queries are NOT Lua** — `hyprctl clients -j`, `monitors -j`, `workspaces -j`, `cursorpos` work normally. Drive everything from these + `jq`.

## Quick reference (verified forms)

| Action | Correct Lua form |
|---|---|
| Switch workspace (numbered) | `hl.dispatch(hl.dsp.focus({ workspace = 3 }))` |
| Switch workspace (named) | `hl.dispatch(hl.dsp.focus({ workspace = "name:obsidian" }))` |
| Focus window by address | `hl.dispatch(hl.dsp.focus({ window = "address:0x…" }))` |
| **Toggle named special ws** | `hl.dispatch(hl.dsp.workspace.toggle_special("scratch"))` ← **STRING** |
| Move current ws to monitor | `hl.dispatch(hl.dsp.workspace.move({ monitor = "DP-2" }))` |
| Rename workspace (label only, see below) | `hl.dispatch(hl.dsp.workspace.rename({ workspace = "name:<address>", name = "x" }))`; numbered: `workspace = <id>` |
| Center active floating window | `hl.dispatch(hl.dsp.window.center())` |
| Move window to workspace | `hl.dispatch(hl.dsp.window.move({ workspace = "name:x", follow = false }))` |
| Warp cursor (absolute px) | `hl.dispatch(hl.dsp.cursor.move({ x = 1920, y = 1080 }))` |
| Run cmd (honors `[rules]` prefix) | `hl.dispatch(hl.dsp.exec_cmd("[workspace special:x silent] app"))` |

⚠️ To *switch* workspaces use `hl.dsp.focus({workspace=…})`, NOT `hl.dsp.workspace` (that table is move/rename/toggle_special, not switch). Legacy `hyprctl dispatch workspace N` is dead.

## ⚠️ The string-vs-table gotcha (this cost hours)

`toggle_special` (and likely other name-taking dispatchers) takes a **string positional** arg:

```bash
hyprctl eval 'hl.dispatch(hl.dsp.workspace.toggle_special("scratch"))'        # ✅ toggles special:scratch
hyprctl eval 'hl.dispatch(hl.dsp.workspace.toggle_special({ name = "scratch" }))'  # ❌ silently toggles special:special
```

The table/keyword form does **not** error — it silently ignores the name and toggles the unnamed **default `special:special`**. That single mistake produces a whole cascade of misleading symptoms:
- The named scratchpad "won't hide" (you're toggling a *different*, empty workspace).
- A phantom `special:special` keeps appearing — easy to misattribute to another user/agent; **it's your own script**.
- Show/hide looks random.

**If a dispatch keeps affecting the wrong/default target:** test the arg form (`"x"` vs `{name="x"}`) in isolation, watch the live `hyprctl monitors -j` state, and confirm *which* workspace actually toggled — before theorizing about external causes.

## follow_mouse (input:follow_mouse=1)

- **Special-workspace toggles act on the monitor the MOUSE is over**, not keyboard focus. Toggling with the pointer on the other screen re-summons the ws there instead of hiding it.
- **Focus dispatches get stolen** back to whatever sits under the cursor.

Fixes:
- Deterministic toggle on a chosen monitor: save `hyprctl cursorpos`, `cursor.move` onto that monitor's center, toggle, then warp the cursor back.
- After a focus dispatch, warp the cursor onto the target's center in the **same** eval so no cursor-driven re-focus sneaks in between.

## Workspace ids and addresses (0.57+)

- Only numbered workspaces have an `id` in `-j` output. Named and special ones have no `id` key, so `jq -r .id` prints `null`.
- Every workspace has an `address`: the name Hyprland created it with (`special:<name>` for a special one). `type` is `normal` or `special`.
- A `name:<x>` selector matches the **address**, not the current `name`. Target a named workspace by `"name:<address>"` and a special one by `"special:<name>"`. A bare name throws `Invalid workspace`.
- `hl.dsp.workspace.rename` changes only `name`. Afterwards `name:<new>` finds nothing: `rename` warns `no such workspace`, and `focus` or `window.move` create a second workspace with that label.
- `hl.dsp.workspace.change_id` takes a numeric `id` only, so it can't re-address a named workspace.
- To give a workspace a new name that selectors find, move its windows onto `name:<new>` and follow. The recipe is in `launcher.md`.

## Special workspaces (multi-monitor)

- A monitor shows **exactly one** special workspace at a time.
- A new special ws **auto-binds to a monitor at creation** — it can land on the wrong / tiny display (centering a tall window on a short monitor shoves it off-screen). **Pin** it: `hl.workspace_rule({ workspace = "special:scratch", monitor = "DP-2" })`. ⚠️ The pin applies at **creation only** — it won't relocate an already-existing special ws (destroy it first: close its windows so the empty ws auto-removes when hidden, then respawn).

## Live-compositor debugging workflow

1. **Inspect, don't guess** — state is fully queryable:
   ```bash
   hyprctl clients  -j | jq -c '.[]|{class,ws:.workspace.name,float:.floating,at,size,pid}'
   hyprctl monitors -j | jq -rc '.[]|select(.specialWorkspace.name!="")|.name+" -> "+.specialWorkspace.name'
   ```
   ⚠️ Read the **`.specialWorkspace.name`** explicitly — "a special is showing on DP-2" hides *which* one (`special:scratch` vs `special:special`). That distinction is often the whole bug.
2. **Screenshot a specific output** for ground truth (beats a racy query mid-transition): `grim -o DP-2 /tmp/x.png`, then view it.
3. **Reproduce, then read back** — spawn a test window, poll for it, read its real `class` / `floating` / `.workspace.name`.

## Shell gotchas on the live box

- **`pkill -f "<pattern>"` can kill your own shell** when the pattern also appears in the invoking command line (exit 144, truncated output). Kill by PID instead: `kill "$(hyprctl clients -j | jq -r '.[]|select(.class=="scratchpad")|.pid')"`.
- **Foreground `sleep` may be sandbox-blocked** — pace with a bounded poll (`for _ in $(seq 1 200); do <cond> && break; done`); hyprctl's ~10–30ms/call latency is the delay.
- **zsh `noclobber`** → redirect with `>|`.
- **GUI apps spawned directly from the agent shell get killed** — launch them via Hyprland's exec (`hl.dispatch(hl.dsp.exec_cmd("app"))`) or `setsid -f app` to detach from the shell.

## Config-edit gotchas

- **Config is Lua** — `~/.config/hypr/hyprland.lua` is **hardlinked** to the dotfile (one edit updates both). `hyprctl reload` re-executes it from disk.
- **Autostart execs** belong inside `hl.on("hyprland.start", function() … end)`. Then `hyprctl reload` re-parses rules **without** re-running them — no duplicate Slack/Telegram spawned on every reload.
- Window-rule **`rounding` is capped at 20**; a larger value errors the whole rule out.
- **`binds:scroll_event_delay`** defaults to ~300 ms and **drops scroll ticks** (scroll-to-cycle feels laggy — "spinning more doesn't move more") → set it to **0**.
- **hyprpm plugins** (hyprbars, hyprexpo…): building needs **sudo** (compiles against Hyprland headers — run interactively, no polkit GUI in a headless/agent shell). ⚠️ After any `pacman -Syu` that bumps `hyprland`, the plugin **ABI mismatches and silently vanishes** → rebuild: `hyprpm update && hyprpm reload -n`.

## Common mistakes

| Mistake | Fix |
|---|---|
| `hyprctl dispatch workspace 3` | `hyprctl eval 'hl.dispatch(hl.dsp.focus({workspace=3}))'` |
| `toggle_special({name="scratch"})` | `toggle_special("scratch")` (string positional) |
| Blaming another agent for a phantom `special:special` | It's your own mis-toggled dispatch — verify the arg form |
| Guessing dispatcher names/signatures | Enumerate `hl.dsp.<table>` via the `error()` trick |
| Trusting one racy `hyprctl` read | `grim` the output; re-query after it settles |
| `pkill -f <pattern in your own command>` | kill by PID from `hyprctl clients -j` |
| Reading `.id` of a named workspace (0.57+) | It's `null`. Read `.address` and target `"name:<address>"` |
| `rename`, then target `name:<new>` | Selectors match the creation-time address. Move the windows onto `name:<new>` instead |
