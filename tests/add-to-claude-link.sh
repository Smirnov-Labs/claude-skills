#!/usr/bin/env bash
# Sandbox test for add-to-claude-link. The script runs no other command and
# makes no network call, so there is nothing to fake. Each check runs it and
# decodes the output in Python before it compares: the query with unquote
# (not unquote_plus, so a stray + shows), an HTML href with html.parser (which
# turns &amp; back into &), and the React href with json.
#   tests/add-to-claude-link.sh                  test this checkout's script
#   TOOL=/path/to/add-to-claude-link tests/...   test another copy
set -uo pipefail
TOOL=${TOOL:-$(cd "$(dirname "$0")/.." && pwd)/skills/adding-an-add-to-claude-button/bin/add-to-claude-link}
T=$(mktemp -d /tmp/add-to-claude-link-test.XXXXXX)
pass=0 fail=0 out="" err="" rc=0
check() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1"; echo "     exit $rc, stdout: $out"; echo "     stderr: $err"; fi; }
run() { out=$("$TOOL" "$@" 2>"$T/err"); rc=$?; err=$(cat "$T/err"); }

USER=https://claude.ai/customize/connectors
ADMIN=https://claude.ai/admin-settings/connectors
U=https://mcp.example.com/mcp

# decodes FORMAT PAGE NAME URL: the output's link opens PAGE with exactly the
# three documented parameters, and they decode to NAME and URL.
cat > "$T/decode.py" <<'EOF'
import html.parser, json, re, sys
from urllib.parse import unquote

fmt, page, name, url = sys.argv[1:5]
text = sys.stdin.read().strip()

def fail(msg):
    print(f"     decode: {msg}", file=sys.stderr)
    sys.exit(1)

class Anchors(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.hrefs = []
    def handle_starttag(self, tag, attrs):
        if tag == "a":
            self.hrefs.append(dict(attrs).get("href"))

link = None
if fmt == "url":
    link = text
elif fmt == "markdown":
    m = re.fullmatch(r"\[[^\]]+\]\(([^()\s]+)\)", text)
    link = m and m.group(1)
elif fmt == "badge":
    m = re.fullmatch(r"\[!\[[^\]]+\]\([^()\s]+\)\]\(([^()\s]+)\)", text)
    link = m and m.group(1)
elif fmt == "html":
    p = Anchors()
    p.feed(text)
    p.close()
    link = p.hrefs[0] if len(p.hrefs) == 1 else None
elif fmt == "react":
    m = re.search(r'const ADD_TO_CLAUDE_HREF =\s*("[^"\n]*");', text)
    link = m and json.loads(m.group(1))
if not link:
    fail(f"no link in the {fmt} output")
base, _, query = link.partition("?")
if base != page:
    fail(f"page {base!r}, want {page!r}")
if not re.fullmatch(r"[A-Za-z0-9._~%=&-]*", query):
    fail(f"a character is not percent-encoded: {query!r}")
pairs = [p.partition("=") for p in query.split("&")]
keys = [k for k, _, _ in pairs]
if keys != ["modal", "connectorName", "connectorUrl"]:
    fail(f"parameters {keys}")
got = {k: unquote(v, errors="strict") for k, _, v in pairs}
want = {"modal": "add-custom-connector", "connectorName": name, "connectorUrl": url}
if got != want:
    fail(f"decoded {got}, want {want}")
EOF
decodes() { python3 "$T/decode.py" "$@" <<<"$out"; }

# A11y facts about the one <a> in the html format: its text, including the
# visually hidden part, and its target and rel.
cat > "$T/anchor.py" <<'EOF'
import html.parser, sys
class P(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.depth, self.text, self.attrs = 0, "", None
    def handle_starttag(self, tag, attrs):
        if tag == "a":
            self.depth, self.attrs = 1, dict(attrs)
        elif self.depth:
            self.depth += 1
    def handle_endtag(self, tag):
        if self.depth:
            self.depth -= 1
    def handle_data(self, data):
        if self.depth:
            self.text += data
p = P()
p.feed(sys.stdin.read())
a = p.attrs or {}
print(p.text, a.get("target"), " ".join(sorted((a.get("rel") or "").split())), sep="|")
EOF

# --- the link and its encoding ---
run Example "$U"
check "a plain name and URL give the documented link" '[ $rc -eq 0 ] && [ "$out" = "$USER?modal=add-custom-connector&connectorName=Example&connectorUrl=https%3A%2F%2Fmcp.example.com%2Fmcp" ] && [ -z "$err" ]'
run Example https://mcp.example.com/
check "the docs example comes out byte for byte" '[ "$out" = "$USER?modal=add-custom-connector&connectorName=Example&connectorUrl=https%3A%2F%2Fmcp.example.com%2F" ]'
run "My Example Server" "$U"
check "spaces become %20, never +" '[[ $out == *"connectorName=My%20Example%20Server&"* ]] && [[ $out != *+* ]] && decodes url "$USER" "My Example Server" "$U"'
run "Tools & More" "$U"
check "an & in the name stays inside connectorName" '[[ $out == *"Tools%20%26%20More"* ]] && decodes url "$USER" "Tools & More" "$U"'
run "C++ #1 a=b?" "$U"
check "+ # = ? in the name are encoded and decode back" 'decodes url "$USER" "C++ #1 a=b?" "$U"'
run "Café ☕ 日本" "$U"
check "unicode is UTF-8 percent-encoded, as encodeURIComponent does" '[[ $out == *"connectorName=Caf%C3%A9%20%E2%98%95%20%E6%97%A5%E6%9C%AC&"* ]] && decodes url "$USER" "Café ☕ 日本" "$U"'
run "Example (beta) it's *new*!" "$U"
check "! ' ( ) * are encoded too" 'decodes url "$USER" "Example (beta) it'"'"'s *new*!" "$U"'
run "Example" "https://mcp.example.com/mcp?tenant=a&b=c#top"
check "a query and fragment in the URL stay inside connectorUrl" 'decodes url "$USER" Example "https://mcp.example.com/mcp?tenant=a&b=c#top"'
run "  Example  " "  $U  "
check "spaces around NAME and URL are trimmed" '[ $rc -eq 0 ] && decodes url "$USER" Example "$U"'

# --- the trailing-slash trap ---
run Example https://mcp.example.com//mcp
check "an origin's trailing slash (//mcp) becomes /mcp, with a warning" '[ $rc -eq 0 ] && decodes url "$USER" Example "$U" && [[ $err == *"doubled slash"* ]]'
run Example "https://mcp.example.com:8443///v1//mcp"
check "only the slashes at the start of the path fold, and the port stays" 'decodes url "$USER" Example "https://mcp.example.com:8443/v1//mcp"'
run Example "https://gw.example.com/proxy/https://upstream.example/mcp"
check "a URL inside the path keeps its //, with no warning" 'decodes url "$USER" Example "https://gw.example.com/proxy/https://upstream.example/mcp" && [ -z "$err" ]'
run Example "https://mcp.example.com//mcp?next=https://a.example//b"
check "doubled slashes in the query are left alone" 'decodes url "$USER" Example "https://mcp.example.com/mcp?next=https://a.example//b"'
run Example https://mcp.example.com/mcp/
check "a final slash stays (it must match the OAuth resource)" 'decodes url "$USER" Example https://mcp.example.com/mcp/ && [ -z "$err" ]'

# --- the admin link ---
run Example "$U" --admin
check "--admin uses the Organization settings page" '[ $rc -eq 0 ] && decodes url "$ADMIN" Example "$U"'
run Example "$U" --admin --format markdown
check "--admin labels the button for the organization" '[[ $out == "[Add to Claude for your organization]("* ]] && decodes markdown "$ADMIN" Example "$U"'

# --- each format ---
run "Example (beta)" "$U" --format markdown
check "markdown is a text link with no raw ( ) in it" '[ $rc -eq 0 ] && [[ $out == "[Add to Claude]("* ]] && decodes markdown "$USER" "Example (beta)" "$U"'
run "Example" "$U" --format badge
check "badge links the shields image to the link" '[ $rc -eq 0 ] && [[ $out == "[![Add to Claude](https://img.shields.io/badge/Add_to_Claude-B05730?style=for-the-badge)]("* ]] && decodes badge "$USER" Example "$U"'
check "badge does not draw the Claude mark" '[[ $out != *logo* ]]'
run Example "$U" --admin --format badge
check "the admin badge text is escaped for shields" '[[ $out == *"/badge/Add_to_Claude_for_your_organization-B05730?"* ]] && decodes badge "$ADMIN" Example "$U"'
run "Tools & More" "$U" --format html
check "html writes the href's & as &amp;" '[ $rc -eq 0 ] && [[ $out == *"modal=add-custom-connector&amp;connectorName=Tools%20%26%20More&amp;connectorUrl="* ]] && [[ $out != *"&connector"* ]]'
check "the html href decodes to the same link" 'decodes html "$USER" "Tools & More" "$U"'
run 'Ex <b>"Tools"</b>' "$U" --format html
check "html markup in the name never reaches the page" '[[ $out != *"<b>"* ]] && [[ $out != *"\"Tools"* ]] && decodes html "$USER" "Ex <b>\"Tools\"</b>" "$U"'
run Example "$U" --format html
a11y=$(python3 "$T/anchor.py" <<<"$out")
check "the html link reads \"Add to Claude (opens in a new tab)\"" '[ "${a11y%%|*}" = "Add to Claude (opens in a new tab)" ]'
check "the html link opens a new tab with noopener noreferrer" '[[ $a11y == *"|_blank|noopener noreferrer" ]]'
check "the new-tab text is visually hidden, not display:none" '[[ $out == *"<span class=\"add-to-claude-sr\"> (opens in a new tab)</span>"* ]] && [[ $out == *"clip-path: inset(50%)"* ]] && [[ $out != *"display: none"* ]]'
check "the html button is at least 44 px tall and has a focus ring" '[[ $out == *"min-height: 44px"* ]] && [[ $out == *":focus-visible {"*"outline: 2px solid"* ]] && [[ $out != *"outline: none"* ]]'
check "the dark html button has a border for dark pages" '[[ $out == *"border: 1px solid #87867F"* ]]'
run "Tools & More" "$U" --format react
check "react keeps a plain & in its JS string" '[ $rc -eq 0 ] && [[ $out != *"&amp;"* ]] && decodes react "$USER" "Tools & More" "$U"'
check "react renders a real <a> that opens a new tab" '[[ $out == *"<a"* ]] && [[ $out == *"target=\"_blank\""* ]] && [[ $out == *"rel=\"noopener noreferrer\""* ]] && [[ $out == *"(opens in a new tab)</span>"* ]]'
check "react comes with the same CSS" '[[ $out == *"/* add-to-claude.css */"* ]] && [[ $out == *":focus-visible {"* ]] && [[ $out == *"min-height: 44px"* ]]'

# --- warnings: stderr only, exit 0, the link unchanged ---
run Example http://mcp.example.com/mcp
check "http warns, and the link is still printed" '[ $rc -eq 0 ] && [[ $err == *"not https"* ]] && decodes url "$USER" Example http://mcp.example.com/mcp'
check "a public host gets no local-address warning" '[[ $err != *"not reachable"* ]]'
for u in http://localhost:8000/mcp https://LOCALHOST./mcp https://app.localhost/mcp https://127.0.0.1/mcp "https://[::1]:8080/mcp" \
         https://0.0.0.0/mcp https://10.0.0.1/mcp https://172.16.0.1/mcp https://169.254.1.1/mcp https://100.64.0.1/mcp \
         https://server.local/mcp https://box.internal/mcp https://intranet/mcp; do
  run Example "$u"
  check "a local address warns: $u" '[ $rc -eq 0 ] && [[ $err == *"not reachable from the internet"* ]] && decodes url "$USER" Example "$u"'
done
run Example https://8.8.8.8/mcp
check "a public IP does not warn" '[ $rc -eq 0 ] && [ -z "$err" ]'

# --- usage errors exit 3 and print nothing on stdout ---
run; check "no arguments is a usage error (3)" '[ $rc -eq 3 ] && [ -z "$out" ]'
run Example; check "a missing URL is a usage error (3)" '[ $rc -eq 3 ] && [ -z "$out" ]'
run "" "$U"; check "an empty name is a usage error (3)" '[ $rc -eq 3 ] && [ -z "$out" ]'
run "   " "$U"; check "a blank name is a usage error (3)" '[ $rc -eq 3 ]'
run $'Ex\nample' "$U"; check "a newline in the name is a usage error (3)" '[ $rc -eq 3 ]'
run $'Ex\xffample' "$U"; check "a name that is not UTF-8 is a usage error (3)" '[ $rc -eq 3 ] && [[ $err == *"UTF-8"* ]]'
run Example ""; check "an empty URL is a usage error (3)" '[ $rc -eq 3 ]'
run Example mcp.example.com/mcp; check "a URL with no scheme is a usage error (3)" '[ $rc -eq 3 ] && [ -z "$out" ]'
run Example ftp://mcp.example.com/mcp; check "a URL that is not http(s) is a usage error (3)" '[ $rc -eq 3 ]'
run Example https:///mcp; check "a URL with no host is a usage error (3)" '[ $rc -eq 3 ]'
run Example "https://mcp.example.com/my mcp"; check "a space inside the URL is a usage error (3)" '[ $rc -eq 3 ]'
run Example https://mcp.example.com:abc/mcp; check "a port that is not a number is a usage error (3)" '[ $rc -eq 3 ]'
run Example "https://[::1/mcp"; check "a broken IPv6 host is a usage error (3)" '[ $rc -eq 3 ]'
run Example "$U" --format svg; check "an unknown format is a usage error (3)" '[ $rc -eq 3 ]'
run Example "$U" --bogus; check "an unknown option is a usage error (3)" '[ $rc -eq 3 ]'
run Example "$U" --adm; check "options are never abbreviated (3)" '[ $rc -eq 3 ]'
run Example "$U" extra; check "a third argument is a usage error (3)" '[ $rc -eq 3 ]'
run --help; check "--help exits 0 and lists the exit codes" '[ $rc -eq 0 ] && [[ $out == *"exit status"* ]] && [[ $out == *"3  usage error"* ]]'

echo "$pass passed, $fail failed"
rm -rf "$T"
[ "$fail" -eq 0 ]
