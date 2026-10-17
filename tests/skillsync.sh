#!/usr/bin/env bash
# Sandbox test for skillsync: every path is redirected under a temp dir, so it
# never touches your real ~/.claude/skills or ~/.local/bin.
#   tests/skillsync.sh                 test this checkout's bin/skillsync
#   TOOL=/path/to/skillsync tests/...  test another copy
set -uo pipefail
TOOL=${TOOL:-$(cd "$(dirname "$0")/.." && pwd)/bin/skillsync}
T=$(mktemp -d /tmp/skillsync-sandbox.XXXXXX)
export SKILLSYNC_HOME=$T/src CLAUDE_SKILLS_DIR=$T/skills SKILLSYNC_BIN_DIR=$T/bin XDG_CONFIG_HOME=$T/cfg
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
pass=0 fail=0
check() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1"; echo "     output was: $out"; fi; }
mkskill() { mkdir -p "$1/skills/$2"; printf -- '---\nname: %s\n---\n' "$2" > "$1/skills/$2/SKILL.md"; }
commit() { git -C "$1" add -A && git -C "$1" commit -qm "$2"; }
run() { out=$("$TOOL" "$@" 2>&1); }

# upstream "public": alpha, beta (+ bin/betatool), repo-level bin/pubtool, a non-skill dir, a non-exec file
P=$T/up/public; mkdir -p "$P"; git -C "$P" init -q -b main
mkskill "$P" alpha; mkskill "$P" beta; mkdir -p "$P/skills/notaskill" "$P/skills/beta/bin" "$P/bin"
printf '#!/bin/sh\necho beta\n' > "$P/skills/beta/bin/betatool"; chmod +x "$P/skills/beta/bin/betatool"
printf '#!/bin/sh\n' > "$P/bin/pubtool"; chmod +x "$P/bin/pubtool"; echo x > "$P/bin/notes.txt"
printf '#!/bin/sh\n' > "$P/skills/beta/bin/ls"; chmod +x "$P/skills/beta/bin/ls"   # would shadow the real ls
commit "$P" init
# upstream "private": gamma (+ bin/foreigncmd) and a duplicate alpha
Q=$T/up/private; mkdir -p "$Q/skills/gamma/bin"; git -C "$Q" init -q -b main; mkskill "$Q" gamma; mkskill "$Q" alpha
printf '#!/bin/sh\n' > "$Q/skills/gamma/bin/foreigncmd"; chmod +x "$Q/skills/gamma/bin/foreigncmd"; commit "$Q" init

# pre-existing state that must be respected
mkdir -p "$T/skills" "$T/bin" "$T/elsewhere/alpha"
mkdir "$T/skills/handmade"                         # unmanaged real skill dir
ln -s "$T/elsewhere/alpha" "$T/skills/alpha"       # foreign symlink with a repo skill's name
ln -s /usr/bin/true "$T/bin/othertool"             # unrelated link in ~/.local/bin
ln -s /usr/bin/true "$T/bin/foreigncmd"            # someone else's link with a repo command's name
echo real > "$T/bin/pubtool"                        # real file colliding with a repo command

echo "== bootstrap: clone public, link"
git clone -q "$P" "$SKILLSYNC_HOME/public"; run link
check "alpha relinked from foreign link, and says so" '[ "$(readlink $T/skills/alpha)" = "$SKILLSYNC_HOME/public/skills/alpha" ] && echo "$out" | grep -q "relinking alpha"'
check "beta linked" '[ -L $T/skills/beta ]'
check "dir without SKILL.md ignored" '[ ! -e $T/skills/notaskill ]'
check "skill bin/ lands on PATH dir and runs" '[ "$($T/bin/betatool)" = beta ]'
check "real file in bin not replaced, warned" '[ "$(cat $T/bin/pubtool)" = real ] && echo "$out" | grep -q "pubtool is a real file"'
check "non-executable not linked" '[ ! -e $T/bin/notes.txt ]'
check "command that would shadow one on PATH not linked, warned" '[ ! -e $T/bin/ls ] && echo "$out" | grep -q "not linking ls, it would shadow"'
check "unmanaged dir and unrelated link untouched" '[ -d $T/skills/handmade ] && [ ! -L $T/skills/handmade ] && [ -L $T/bin/othertool ]'
rm -f "$T/bin/pubtool"; run link
check "repo command linked once the slot is free" '[ -L $T/bin/pubtool ]'
run link
check "idempotent: second run is quiet" '! echo "$out" | grep -qE "relinking|removed"'

echo "== add a second source (name derived from URL)"
run add "$Q"
check "cloned to SKILLSYNC_HOME/private" '[ -d $SKILLSYNC_HOME/private/.git ]'
check "gamma linked" '[ -L $T/skills/gamma ]'
check "someone else's link in bin not replaced, warned" '[ "$(readlink $T/bin/foreigncmd)" = /usr/bin/true ] && echo "$out" | grep -q "foreigncmd points at"'
check "duplicate alpha warned" 'echo "$out" | grep -q "alpha is provided twice"'
run add "$Q"
check "re-adding an existing source refuses" 'echo "$out" | grep -q "already exists"'

echo "== exclude list"
mkdir -p "$T/cfg/skillsync"; echo beta > "$T/cfg/skillsync/exclude"; run link
check "excluded skill unlinked, with its bin/" '[ ! -e $T/skills/beta ] && [ ! -e $T/bin/betatool ]'
rm -f "$T/cfg/skillsync/exclude"; run link
check "un-excluding restores it" '[ -L $T/skills/beta ] && [ -L $T/bin/betatool ]'

echo "== upstream change + sync (pull)"
git -C "$P" rm -rq skills/beta; mkskill "$P" epsilon; commit "$P" change
git -C "$Q" rm -rq skills/alpha; commit "$Q" dedupe
run
check "new upstream skill linked after pull" '[ -L $T/skills/epsilon ]'
check "deleted upstream skill and its command pruned" '[ ! -e $T/skills/beta ] && [ ! -L $T/skills/beta ] && [ ! -L $T/bin/betatool ]'

echo "== author checkout (symlinked source) + unreachable source"
D=$T/checkout; mkdir -p "$D"; git -C "$D" init -q -b main; mkskill "$D" zeta; commit "$D" init
git -C "$D" remote add origin "$T/does-not-exist"; ln -s "$D" "$SKILLSYNC_HOME/dev"
git -C "$SKILLSYNC_HOME/private" remote set-url origin "$T/also-missing"
run
check "checkout source linked" '[ -L $T/skills/zeta ]'
check "checkout source never pulled (no warning for it)" '! echo "$out" | grep -q "update dev"'
check "unreachable source warns, keeps local copy" 'echo "$out" | grep -q "could not update private" && [ -L $T/skills/gamma ]'
run -q
check "-q hides notices (unreachable source, link conflicts)" '[ -z "$out" ]'

echo "== list + removing a source"
run list
check "list shows checkout marker" 'echo "$out" | grep -q "^dev .*\[checkout"'
rm -rf "$SKILLSYNC_HOME/private"; run link
check "removing a source prunes its skills" '[ ! -L $T/skills/gamma ]'
check "other links survive" '[ -L $T/skills/alpha ] && [ -L $T/skills/zeta ] && [ -L $T/bin/othertool ] && [ "$(readlink $T/bin/foreigncmd)" = /usr/bin/true ]'

echo; echo "passed $pass, failed $fail"; rm -rf "$T"; [ "$fail" -eq 0 ]
