# Architecture

This file explains how the skills in this repo reach a machine, and the rules that keep that safe. The README lists the skills. CLAUDE.md has the notes for working on the repo.

## Two ways to install

1. **skillsync** (`bin/skillsync`). The maintainer uses it on every machine. It links skills from any number of skills repos.
2. **Plugins** (`.claude-plugin/marketplace.json`). These cover some of the skills, for people who use `/plugin`.

Use one method per machine. With both, each skill loads twice. If `~/.claude/settings.json` is a symlink into a dotfiles repo, use skillsync. `/plugin install` writes into that file, so the plugin settings land in the dotfiles repo.

## skillsync

### Sources

A source is a git clone in `~/.local/share/skillsync/<name>/`. skillsync works on every source that it finds there, and it names no repository itself. A machine gets exactly the sources that are cloned onto it.

`skillsync add <git-url>` clones another source. If the machine cannot read that repo, the clone fails and nothing is installed. That is the whole access model: the git credentials on the machine decide which skills it gets.

A source that is a symlink is an author checkout (`ln -s <working clone> ~/.local/share/skillsync/<name>`). skillsync links it but never pulls it. Edits in the working clone are live at once.

### What a run does

1. `skillsync` with no command pulls each source that is a real clone (`git pull --ff-only`, no password prompts). If a pull fails, it keeps the local copy and says so.
2. It links each `skills/<name>/` that has a `SKILL.md` to `~/.claude/skills/<name>`.
3. It links each executable in `skills/<name>/bin/` and in the source's own `bin/` into `~/.local/bin/`.
4. It removes each link that points into a source but that this run did not place, for example a deleted or renamed skill.

`skillsync link` does steps 2 to 4 only. `skillsync -q` prints errors only, for cron.

### Safety rules

- It never replaces a real file or directory. A skill that you made by hand in `~/.claude/skills/` stays.
- In `~/.local/bin/`, it never replaces a symlink that points somewhere else.
- It never links a command that would shadow another command on `PATH`.
- If two sources have a skill or a command with the same name, the first source in name order wins, and skillsync reports the clash.
- It removes only links that point into its own sources.
- It does not link the names listed in `~/.config/skillsync/exclude` (one name per line) on that machine.

skillsync must run on bash 3.2. Under cron's minimal `PATH` on macOS, `env bash` finds Apple's `/bin/bash`, which is 3.2. `tests/skillsync.sh` checks the rules above in a sandbox. It sets `SKILLSYNC_HOME`, `CLAUDE_SKILLS_DIR` and `SKILLSYNC_BIN_DIR` to temporary directories.

## Why this design

- **Per-skill symlinks, not a git repo in `~/.claude/skills`.** That directory also holds skills from other places, such as hand-made or third-party skills. A repo there tracks all of them.
- **No dotfiles.** Skills change often and come from more than one repo. Dotfiles would have to name every repo, including the private ones.
- **No repo names in skillsync.** Public code that names a private repo leaks the name, and it breaks on machines without access.
- **Links run one way.** A private skill can mention a public one. A public skill never mentions a private one.

## Skill anatomy

- `SKILL.md`: YAML frontmatter and the prompt. `name` is the directory name. `description` says when to use the skill.
- `<SUBAGENT-STOP>` comes right after the frontmatter on workflow skills that take over a session.
- `disable-model-invocation: true` is on skills that run only when the user invokes them, such as `pr-fix`.
- `bin/` holds commands that the skill calls, such as `prbots`. The names must be unique across all sources.
- `UPSTREAM` is only on vendored skills (`humanizer`, `nonstop`). It records the source, the commit and the license. To update a vendored skill, copy it from upstream again.

## Shared patterns

- **Codex calls** (`codex-plan-review`, `detect-overengineering`). The prompt goes in on stdin, built with `cat`, so a long plan is not typed out again. `-o` writes the reply. The log is kept, never sent to `/dev/null`. The model pin and the table of tested models are in the Model section of `codex-plan-review`, and `detect-overengineering` uses the same pin. If Codex rejects the pin, the skill runs once more without `-m`.
- **PR bots** (`watching-pr-bot-reviews`, `pr-fix`). Run `prbots wait <PR>` in the background. Never write a polling loop.

## Review gate

Every PR gets the Architect-Gate review (`.github/claude/`), which posts a System Architecture Review as a PR comment. `02-public-skills-repo.prompt.md` holds the rules for this repo, and private material is a blocker. Commit messages and PR text are public too, so keep them clean as well.

The review does not run again on push. To start it, comment `@architect-run`, or run `prbots wait <PR> --need sar --trigger`. Codex review is not enabled on this repo.

## History

- 2026-10-16 (#11): skillsync replaced the plugin installs on the maintainer's machines, and the local skills moved in.
- 2026-10-17 (#12): `de-slopping` and `minto-pyramid` moved in from one machine's `~/.claude/skills`.
- 2026-10-19 (#9, #15): codex-cli 0.163 removed `--full-auto`. In both Codex skills, `2>/dev/null` hid the failure. Both skills now pin `gpt-6-astra` and keep the log.
