# Project-Specific Rules: Public Skills Repo

This repository is **public**. It holds Claude Code skills (`skills/<name>/SKILL.md` plus supporting files) and `bin/skillsync`, which symlinks each skill into `~/.claude/skills` on the maintainer's machines. Anything merged here is world-readable, so the first job of this review is keeping private material out.

## 1. Nothing private (BLOCKER)

**Rule**: Added or changed lines MUST NOT contain:

- names of clients or customers, or of their companies, products, or projects
- internal hostnames or domains, private IP addresses (10.x, 172.16–31.x, 192.168.x), VPN or tailnet names, cloud account IDs
- names of private repositories, or links to them
- credentials of any kind: API keys, tokens, passwords, private keys, connection strings that embed secrets
- real financial figures or personal data

**Why**: skills that need any of the above belong in the maintainer's private skills repo, not here. Once pushed, treat it as permanent.

**Flag as a blocker** any line that looks like one of these, even inside an example. Obvious placeholders (`acme/webapp`, `example.com`, an illustrative `10.0.0.1`) are fine; when you judge a match to be a placeholder, say so.

## 2. Skill layout

- Every skill is `skills/<name>/SKILL.md` with frontmatter `name: <name>` matching its directory and a `description` that says when to use the skill. New skills start it with "Use when"; don't flag the wording of existing or vendored skills.
- Executables a skill ships go in `skills/<name>/bin/`. `skillsync` puts them on PATH, so their names must be unique across the repo.
- `bin/skillsync` must never name a specific repository, and must stay compatible with bash 3.2 (macOS).

## 3. Vendored skills

A skill with an `UPSTREAM` file is a third-party copy. It must keep the upstream `LICENSE`, and changes should be a fresh copy from upstream with the commit updated in `UPSTREAM`, not local edits.
