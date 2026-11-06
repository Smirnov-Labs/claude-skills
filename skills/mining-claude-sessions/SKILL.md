---
name: mining-claude-sessions
description: Use when asked to find or resume a past Claude Code session ("find the session where we...", "resume the one that built X"), to say what a session did, or to audit Claude Code usage (which tools, skills, commands, agents or prompts recur), and before you parse ~/.claude/projects transcripts by hand.
---

# Mining Claude sessions

`cc-sessions` reads Claude Code's local transcripts and answers the common questions in one command. Without it, agents wrote a new JSONL parser for each audit and each "find that session" request.

## Commands

| Question | Command |
|---|---|
| Which session did X, and how do I resume it? | `cc-sessions find handbrake transcode` |
| Only recent sessions in one project | `cc-sessions find invoice --days 14 --project finance` |
| What did that session do? | `cc-sessions show 9548d7af` |
| What do we use, and what recurs? | `cc-sessions stats --days 30` |
| The same, as JSON | `cc-sessions stats --days 30 --json` |
| Masked events for your own analysis | `cc-sessions export /tmp/events.jsonl --days 30` |

- `find` needs every word to appear in a session: its title, typed prompts, edited file paths or commands. Title and prompt hits rank highest. Each hit ends with a `cd <dir> && claude --resume <id>` line.
- `show` takes a session id or a unique prefix of one.
- `--days N` keeps sessions whose file changed in the last N days. `--project TEXT` matches the project directory name.
- `cc-sessions --help` lists the rest.

`cc-sessions` is on PATH where skillsync installed this skill. In a plugin install, call `<this skill's base directory>/bin/cc-sessions` by its full path.

## Masking

Transcripts hold everything a session saw, secrets included. Every line `cc-sessions` prints or exports goes through a masker first. It masks API keys, tokens, auth headers, cookies and long random strings. It also masks passwords piped into `sudo -S`, `sshpass -p` values, and the credential options of curl, wget and httpie. It reads shell commands word by word, so quotes and escapes do not hide a secret. Pass your own literal values with `--mask-file FILE`, one per line, or set `CC_SESSIONS_MASK_FILE`. `export` writes its file with mode 600.

Masking is best effort: patterns cannot catch every secret. It lowers exposure, it does not remove it, so treat the output as sensitive too. The masker does not touch the transcripts themselves. Quote them through `cc-sessions`, never with `cat` or `grep`.

## The transcript format

The tool relies on these facts:

- Main sessions are `~/.claude/projects/<project>/<session-id>.jsonl`. Subagents are `<session-id>/subagents/agent-*.jsonl`. `CLAUDE_CONFIG_DIR` moves the root.
- Each line is one JSON record with a `type`.
- A prompt a person typed is a `user` record with `origin.kind` set to `human`. Task notifications and tool results are `user` records too: skip them.
- Tool calls are `tool_use` blocks in `assistant` records (`name`, `input`). Results come back as `tool_result` blocks, with `is_error` on failures.
- `ai-title` records hold the session title. `pr-link` records hold `prUrl`, repeated each turn.
- Timestamps are UTC.

## When the answer is not there

- Claude Code deletes a transcript after `cleanupPeriodDays` (default 30) without activity. Older sessions are gone unless something else kept them.
- Each machine keeps its own transcripts. Run `cc-sessions` on the machine where the session ran.
