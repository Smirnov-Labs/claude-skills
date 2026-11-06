#!/usr/bin/env bash
# Sandbox test for latest-version: a local fake server plays the GitHub API and
# an OCI registry (token challenge, Link pagination, manifest digests, a
# cross-host redirect), and a fake `gh` on PATH plays `gh api -i`. Nothing
# here reaches the network or calls the real gh.
#   tests/latest-version.sh                    test this checkout's script
#   TOOL=/path/to/latest-version tests/...     test another copy
set -uo pipefail
TOOL=${TOOL:-$(cd "$(dirname "$0")/.." && pwd)/skills/finding-latest-versions/bin/latest-version}
T=$(mktemp -d /tmp/latest-version-test.XXXXXX)
pass=0 fail=0 SERVER=
cleanup() { [ -n "$SERVER" ] && kill "$SERVER" 2>/dev/null && wait "$SERVER" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT
trap 'exit 130' INT TERM
check() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1"; echo "     exit $rc, stdout: $out"; echo "     stderr: $err"; fi; }
run() { out=$("$TOOL" "$@" 2>"$T/err"); rc=$?; err=$(cat "$T/err"); }
lines() { printf '%s' "$out" | tr '\n' ' ' | sed 's/ $//'; }
LOG=$T/server.log
logged() { grep -c -- "$1" "$LOG"; }
sha() { python3 -c 'import hashlib, sys; print("sha256:" + hashlib.sha256(sys.argv[1].encode()).hexdigest())' "$1"; }
pyjson() { printf '%s' "$out" | python3 -c "import json, sys; d = json.load(sys.stdin); sys.exit(0 if ($1) else 1)"; }

cat > "$T/fake.py" <<'EOF'
import hashlib, json, os, sys, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT_FILE, LOG = sys.argv[1], sys.argv[2]

def rel(tag, **kw):
    r = {"tag_name": tag, "name": "Release " + tag, "draft": False, "prerelease": False,
         "published_at": "2026-01-02T03:04:05Z", "html_url": "https://example.com/r/" + tag}
    r.update(kw)
    return r

RELEASES = {   # pages of releases, newest first as GitHub sends them
    "acme/tool": [[rel("v1.10.0"), rel("v2.0.0-rc.1", prerelease=True), rel("v1.9.0"),
                   rel("v9.9.9", draft=True), rel("nightly", prerelease=True)],
                  [rel("v1.2.0"), rel("v1.1.0")]],
    "acme/flagged": [[rel("v3.0.0", prerelease=True), rel("v2.5.0")]],
    "acme/deep": [[rel("v1.0.5"), rel("v1.0.4")], [rel("v2.0.0"), rel("v1.0.3")],
                  [rel("v0.1.0")], [rel("v0.0.1")]],
    "acme/norel": [[]],
    "acme/drafts": [[rel("v5.0.0", draft=True)]],
    "acme/prefixed": [[rel("jq-1.7.1"), rel("jq-1.8.0"), rel("jq-1.10.0rc1", prerelease=True)]],
}
GH_TAGS = {
    "acme/tool": [["v1.11.0"]],
    "acme/norel": [["v0.9.0", "v0.10.0"], ["latest", "v0.10.1-rc1"]],
    "acme/drafts": [["v4.0.0"]],
}
IDS = {s: i for i, s in enumerate(sorted(set(RELEASES) | set(GH_TAGS)), start=1)}
SLUGS = {i: s for s, i in IDS.items()}
REG = {   # tag lists in lexical order, as registries send them
    "org/img": sorted(["1", "1.10", "1.10.0", "1.10.1-alpine", "1.11.0-beta.2", "1.11.0-rc.1",
                       "1.11.0-rc.10", "1.11.0-rc.9", "1.2.0", "1.9.0", "1234567", "20241105",
                       "latest", "main", "sha-abc1234", "v1.10.1"]),
    "library/caddy": ["2.10.0", "2.10.0-alpine", "2.10.0-builder-alpine", "2.8.4", "2.9.1", "latest"],
    "user/app": ["0.1.0", "0.2.0"],
    "org/open": ["1.0.0", "1.1.0"],
}
PAGE = 4
INDEX, PLATFORM = b'{"index":true}', b'{"platform":true}'
NOHEAD = b'{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json"}'
NAME_UNKNOWN = {"errors": [{"code": "NAME_UNKNOWN", "message": "repository name not known to registry"}]}


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, body=b"", headers=None, ctype="application/json"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def do_CONNECT(self):   # stands in for an https proxy: refuses, but logs the host
        self.route(tunnel=True)

    def do_GET(self):
        self.route()

    def do_HEAD(self):
        self.route()

    def route(self, tunnel=False):
        with open(LOG, "a") as f:
            f.write(f"{self.command} host={self.headers.get('Host')} path={self.path} "
                    f"auth={self.headers.get('Authorization', '-')} accept={self.headers.get('Accept', '-')}\n")
        if tunnel:
            return self.send(403, b"no tunnels", ctype="text/plain")
        u = urllib.parse.urlsplit(self.path)
        q = dict(urllib.parse.parse_qsl(u.query))
        if u.path.startswith("/gh/"):
            return self.github(u.path[4:], q)
        if u.path == "/token":
            return self.token(q)
        if u.path.startswith("/v2/"):
            return self.registry(u.path[4:], q)
        self.send(404, {"message": "Not Found"})

    def github(self, path, q):
        parts = path.strip("/").split("/")
        if parts[0] == "repos" and len(parts) == 4:
            slug, kind = parts[1] + "/" + parts[2], parts[3]
        elif parts[0] == "repositories" and len(parts) == 3:
            slug, kind = SLUGS.get(int(parts[1]), "?"), parts[2]
        else:
            return self.send(404, {"message": "Not Found"})
        if slug == "acme/limited":
            return self.send(403, {"message": "API rate limit exceeded for 203.0.113.9."},
                             {"X-RateLimit-Remaining": "0"})
        if slug == "acme/broken":
            return self.send(500, b"oops", ctype="text/plain")
        if slug == "acme/badjson":
            return self.send(200, b"<html>", ctype="text/html")
        if slug not in IDS:
            return self.send(404, {"message": "Not Found"})
        pages = (RELEASES if kind == "releases" else GH_TAGS).get(slug, [[]])
        page = int(q.get("page", "1"))
        items = pages[page - 1] if page <= len(pages) else []
        if kind == "tags":
            items = [{"name": t, "commit": {"sha": "0" * 40}} for t in items]
        headers = {}
        if page < len(pages):
            base = f"http://{self.headers.get('Host')}/gh/repositories/{IDS[slug]}/{kind}?per_page=100"
            headers["Link"] = f'<{base}&page={page + 1}>; rel="next", <{base}&page={len(pages)}>; rel="last"'
        self.send(200, items, headers)

    def token(self, q):
        scope = q.get("scope", "").split(":")
        if q.get("service") != "fake-registry" or len(scope) != 3:
            return self.send(400, {"details": "bad token request"})
        if scope[1] == "org/private":
            return self.send(401, {"details": "no anonymous access"})
        self.send(200, {"token": f"tok-{self.headers.get('Host')}-{scope[1]}"})

    def registry(self, path, q):
        if path.endswith("/tags/list"):
            repo, ref = path[:-len("/tags/list")], None
        elif "/manifests/" in path:
            repo, ref = path.split("/manifests/", 1)
        else:
            return self.send(404, NAME_UNKNOWN)
        host = self.headers.get("Host")
        if repo == "org/basic":
            return self.send(401, {"errors": []}, {"WWW-Authenticate": 'Basic realm="fake"'})
        if repo != "org/open" and self.headers.get("Authorization") != f"Bearer tok-{host}-{repo}":
            return self.send(401, {"errors": [{"code": "UNAUTHORIZED", "message": "authentication required"}]},
                             {"WWW-Authenticate": f'Bearer realm="http://{host}/token",'
                                                  f'service="fake-registry",scope="repository:{repo}:pull"'})
        if repo == "org/moved":   # a token here, then off to another host
            other = host.replace("127.0.0.1", "localhost")
            return self.send(307, b"", {"Location": f"http://{other}/v2/org/img/tags/list"})
        if repo == "org/gone":
            return self.send(404, NAME_UNKNOWN)
        if repo == "org/badjson":
            return self.send(200, b"garbage", ctype="text/plain")
        if ref is not None:
            return self.manifest(repo, ref)
        if repo == "org/endless":
            n = int(q.get("last", "0")) + 1
            return self.send(200, {"name": repo, "tags": [f"0.0.{n}"]},
                             {"Link": f'</v2/org/endless/tags/list?n=1&last={n}>; rel="next"'})
        if repo == "org/loop":
            return self.send(200, {"name": repo, "tags": ["1.0.0"]},
                             {"Link": '</v2/org/loop/tags/list?n=4&last=x>; rel="next"'})
        if repo == "org/strict" and int(q.get("n", "0")) > 100:
            return self.send(400, {"errors": [{"code": "PAGINATION_NUMBER_INVALID", "message": "n too big"}]})
        tags = REG.get("org/img" if repo == "org/strict" else repo)
        if tags is None:
            return self.send(404, NAME_UNKNOWN)
        start = tags.index(q["last"]) + 1 if q.get("last") in tags else 0
        chunk, headers = tags[start:start + PAGE], {}
        if start + PAGE < len(tags):
            headers["Link"] = f'</v2/{repo}/tags/list?n={PAGE}&last={urllib.parse.quote(chunk[-1])}>; rel="next"'
        self.send(200, {"name": repo, "tags": chunk}, headers)

    def manifest(self, repo, ref):
        if repo == "org/nohead":
            if self.command == "HEAD":
                return self.send(405)
            return self.send(200, NOHEAD, ctype="application/vnd.oci.image.manifest.v1+json")
        if repo != "org/img" or ref != "1.10.0":
            return self.send(404, {"errors": [{"code": "MANIFEST_UNKNOWN", "message": "manifest unknown"}]})
        if "application/vnd.oci.image.index.v1+json" in self.headers.get("Accept", ""):
            body, ctype = INDEX, "application/vnd.oci.image.index.v1+json"
        else:
            body, ctype = PLATFORM, "application/vnd.docker.distribution.manifest.v2+json"
        self.send(200, body, {"Docker-Content-Digest": "sha256:" + hashlib.sha256(body).hexdigest()}, ctype)


srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
with open(PORT_FILE + ".tmp", "w") as f:
    f.write(str(srv.server_address[1]))
os.replace(PORT_FILE + ".tmp", PORT_FILE)
srv.serve_forever()
EOF

# A fake gh: prints `gh api -i URL` the way the real one does (status line,
# CRLF headers, a blank line, the body; exit 1 on an HTTP error).
mkdir -p "$T/bin"
cat > "$T/gh.py" <<'EOF'
import os, sys, urllib.error, urllib.request
base, url, mode = os.environ["FAKE_GH_BASE"], sys.argv[-1], os.environ.get("FAKE_GH", "")
if mode == "loggedout":
    sys.stderr.write("To get started with GitHub CLI, please run:  gh auth login\n")
    sys.exit(4)
if url.startswith("https://api.github.com/"):
    url = base + url[len("https://api.github.com"):]
elif not url.startswith("http"):
    url = base + "/" + url
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
try:
    r = opener.open(url)
    code, reason, headers, body = r.status, r.reason, r.headers, r.read()
except urllib.error.HTTPError as e:
    code, reason, headers, body = e.code, e.reason, e.headers, e.read()
if mode == "stale":
    code, reason, body = 401, "Unauthorized", b'{"message":"Bad credentials"}'
out = sys.stdout.buffer
out.write(f"HTTP/2.0 {code} {reason}\n".encode())
for k, v in headers.items():
    out.write(f"{k}: {v.replace(base, 'https://api.github.com')}\r\n".encode())
out.write(b"\r\n" + body)
if code >= 400:
    sys.stderr.write(f"gh: {reason} (HTTP {code})\n")
    sys.exit(1)
EOF
cat > "$T/bin/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$T/gh.log"
exec python3 "$T/gh.py" "\$@"
EOF
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH"
: > "$T/gh.log"

unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
export NO_PROXY=127.0.0.1,localhost no_proxy=127.0.0.1,localhost
python3 "$T/fake.py" "$T/port" "$LOG" 2>"$T/server.err" & SERVER=$!
for _ in $(seq 1 50); do [ -s "$T/port" ] && break; sleep 0.1; done
[ -s "$T/port" ] || { echo "the fake server did not start: $(cat "$T/server.err")"; exit 1; }
R=127.0.0.1:$(cat "$T/port")
export LATEST_VERSION_GITHUB_API=http://$R/gh LATEST_VERSION_REGISTRY_SCHEME=http LATEST_VERSION_DOCKER_HUB=$R

# ---- GitHub releases, through the API base override (gh is never called)
run acme/tool
check "newest stable release: 1.10 beats 1.9, drafts and pre-releases skipped" '[ $rc -eq 0 ] && [ "$out" = v1.10.0 ]'
run acme/tool --pre
check "--pre includes a release GitHub marks as a pre-release" '[ $rc -eq 0 ] && [ "$out" = v2.0.0-rc.1 ]'
run acme/tool -n 3
check "-n 3 follows the Link header to page 2" '[ $rc -eq 0 ] && [ "$(lines)" = "v1.10.0 v1.9.0 v1.2.0" ]'
run acme/tool -n 9 --pre
check "a draft never shows, not even with --pre" '[ $rc -eq 0 ] && [[ $out != *v9.9.9* ]] && [[ $out != *nightly* ]]'
check "the override base means gh is never called" '[ ! -s "$T/gh.log" ]'
run https://github.com/acme/tool
check "a github.com URL works" '[ $rc -eq 0 ] && [ "$out" = v1.10.0 ]'
run acme/flagged
check "a plain tag marked pre-release is skipped" '[ $rc -eq 0 ] && [ "$out" = v2.5.0 ]'
run acme/flagged --pre
check "a plain tag marked pre-release ranks as the newest with --pre" '[ $rc -eq 0 ] && [ "$out" = v3.0.0 ]'
: > "$LOG"; run acme/deep
check "a higher version on a later page still wins" '[ $rc -eq 0 ] && [ "$out" = v2.0.0 ]'
check "paging stops once a page adds nothing to the top" '[ "$(logged "page=3")" -eq 1 ] && [ "$(logged "page=4")" -eq 0 ]'
run acme/norel
check "no releases falls back to tags" '[ $rc -eq 0 ] && [ "$out" = v0.10.0 ]'
run acme/norel --match zzz
check "an empty tag fallback says the repo has no releases" '[ $rc -eq 1 ] && [[ $err == *"has no releases, so its tags were read"* ]]'
run acme/norel --pre --json
check "the tag fallback says so in JSON and reads every page" '[ $rc -eq 0 ] && [[ $out == *"\"source\": \"github-tags\""* ]] && [[ $out == *v0.10.1-rc1* ]]'
run acme/drafts
check "a repo with only draft releases falls back to tags" '[ $rc -eq 0 ] && [ "$out" = v4.0.0 ]'
run acme/tool --tags
check "--tags reads tags even when there are releases" '[ $rc -eq 0 ] && [ "$out" = v1.11.0 ]'
run acme/tool --json
check "JSON carries the release fields" '[ $rc -eq 0 ] && [[ $out == *"\"source\": \"github-releases\""* ]] && [[ $out == *"\"published_at\": \"2026-01-02T03:04:05Z\""* ]]'
run acme/prefixed
check "prefixed tags exit 1 with a --match hint" '[ $rc -eq 1 ] && [ -z "$out" ] && [[ $err == *"--match"*"^jq-(.+)"* ]]'
run acme/prefixed --match '^jq-(.+)$'
check "a --match group reads the version from the group" '[ $rc -eq 0 ] && [ "$out" = jq-1.8.0 ]'
run acme/prefixed --match '^jq-(.+)$' --pre
check "the group works with --pre too" '[ $rc -eq 0 ] && [ "$out" = jq-1.10.0rc1 ]'
run acme/missing
check "an unknown repo exits 2 and suggests docker.io" '[ $rc -eq 2 ] && [[ $err == *"docker.io/acme/missing"* ]]'
run acme/limited
check "the rate limit exits 2 and says how to fix it" '[ $rc -eq 2 ] && [[ $err == *"rate limit"* ]] && [[ $err == *"gh auth login"* ]]'
run acme/broken
check "an HTTP 500 exits 2" '[ $rc -eq 2 ] && [[ $err == *"HTTP 500"* ]]'
run acme/badjson
check "a reply that is not JSON exits 2" '[ $rc -eq 2 ] && [[ $err == *"not JSON"* ]]'

# ---- GitHub through a fake gh (no override, so the script picks gh)
(
  unset LATEST_VERSION_GITHUB_API
  export FAKE_GH_BASE=http://$R/gh https_proxy=http://$R HTTPS_PROXY=http://$R
  run acme/tool -n 3
  check "gh api: the same answer, page 2 from the Link header" '[ $rc -eq 0 ] && [ "$(lines)" = "v1.10.0 v1.9.0 v1.2.0" ]'
  check "gh api runs with -i and gets the absolute Link URL" '[ "$(grep -c "^api -i" "$T/gh.log")" -eq 2 ] && grep -q "https://api.github.com/repositories/" "$T/gh.log"'
  : > "$LOG"; run acme/missing
  check "gh api: a 404 exits 2 and does not retry without a token" '[ $rc -eq 2 ] && [[ $err == *"no such repo"* ]] && [ "$(logged CONNECT)" -eq 0 ]'
  : > "$LOG"; FAKE_GH=loggedout run acme/tool
  check "gh not logged in: falls back to the API without a token" '[ "$(logged "^CONNECT .*api.github.com:443")" -eq 1 ] && [ $rc -eq 2 ]'
  : > "$LOG"; FAKE_GH=stale run acme/tool
  check "gh with a stale token (401): falls back too" '[ "$(logged "^CONNECT .*api.github.com:443")" -eq 1 ]'
  echo "$pass $fail" > "$T/sub.count"
)
read -r pass fail < "$T/sub.count"

# ---- registries: token challenge, pagination, sorting
I=$R/org/img
: > "$LOG"; run "$I"
check "registry: newest stable across 4 pages (v-prefix and 1.10 vs 1.9)" '[ $rc -eq 0 ] && [ "$out" = v1.10.1 ]'
check "registry: one anonymous token, reused on every page" '[ "$(logged "path=/token")" -eq 1 ] && [ "$(logged "auth=Bearer tok-$R-org/img")" -eq 4 ]'
check "registry: the token request carries the challenge service and scope" 'grep -q "path=/token?service=fake-registry&scope=repository%3Aorg%2Fimg%3Apull" "$LOG"'
check "registry: the first page asks for n=10000" '[ "$(logged "path=/v2/org/img/tags/list?n=10000 auth=Bearer")" -eq 1 ]'
: > "$LOG"; run "$R/org/strict"
check "a registry that refuses a big page is asked again without n" '[ $rc -eq 0 ] && [ "$out" = v1.10.1 ] && [ "$(logged "path=/v2/org/strict/tags/list auth=Bearer")" -eq 1 ]'
run "http://$R/org/img"
check "an image written as a URL works" '[ $rc -eq 0 ] && [ "$out" = v1.10.1 ]'
run "$I" -n 10
check "-n 10: equal versions once, one-number tags only beside their N.N" '[ $rc -eq 0 ] && [ "$(lines)" = "v1.10.1 1.10.0 1.9.0 1.2.0 1" ]'
run "$I" --pre
check "--pre: rc.10 beats rc.9, rc.1 and beta.2" '[ $rc -eq 0 ] && [ "$out" = 1.11.0-rc.10 ]'
run "$I" --pre -n 5
check "--pre -n 5: pre-releases rank above older releases, by number" '[ "$(lines)" = "1.11.0-rc.10 1.11.0-rc.9 1.11.0-rc.1 1.11.0-beta.2 v1.10.1" ]'
run "$I" --match '^1\.9\.'
check "--match picks a line" '[ $rc -eq 0 ] && [ "$out" = 1.9.0 ]'
run "$I" --match 'alpine$'
check "--match admits a variant" '[ $rc -eq 0 ] && [ "$out" = 1.10.1-alpine ]'
run "$I" --match -alpine$
check "--match takes a value that starts with a dash" '[ $rc -eq 0 ] && [ "$out" = 1.10.1-alpine ]'
run "$I" --match zzz
check "--match with no hit exits 1 and says so" '[ $rc -eq 1 ] && [ -z "$out" ] && [[ $err == *"none of the 16 tags"* ]]'
run "$I" --json
J='d["source"] == "registry" and d["target"] == "'$R'/org/img" and [v["tag"] for v in d["versions"]] == ["v1.10.1"] and set(d["other_tags"]) == {"latest", "main", "sha-abc1234"} and d["other_count"] == 3'
check "JSON: the source, the target and the tags set aside" '[ $rc -eq 0 ] && pyjson "$J"'
run "$I" -n 2 --json
check "JSON: 1.10 is an alias of 1.10.0" 'pyjson "[v[\"aliases\"] for v in d[\"versions\"]] == [[], [\"1.10\"]]"'
run "$I" --match 'alpine$' --json
check "JSON: a variant says so" 'pyjson "d[\"versions\"][0][\"variant\"] is True and d[\"versions\"][0][\"kind\"] == \"stable\""'
run "$R/org/img:latest"
check "a :tag on the image is ignored" '[ $rc -eq 0 ] && [ "$out" = v1.10.1 ]'
: > "$LOG"; run "$R/org/open"
check "a registry without auth needs no token" '[ $rc -eq 0 ] && [ "$out" = 1.1.0 ] && [ "$(logged "path=/token")" -eq 0 ]'
run caddy
check "a bare name is a Docker Hub library image" '[ $rc -eq 0 ] && [ "$out" = 2.10.0 ] && grep -q "path=/v2/library/caddy/tags/list" "$LOG"'
run caddy --match '-alpine$'
check "of two variants of one version the plainer ranks first" '[ $rc -eq 0 ] && [ "$out" = 2.10.0-alpine ]'
run docker.io/user/app
check "docker.io/user/app is a Docker Hub user image" '[ $rc -eq 0 ] && [ "$out" = 0.2.0 ]'
run user/app:latest
check "user/app with a tag is a Docker Hub image, not a GitHub repo" '[ $rc -eq 0 ] && [ "$out" = 0.2.0 ]'
: > "$LOG"; run "$R/org/moved"
check "a redirect to another host gets its own token" '[ $rc -eq 0 ] && [ "$out" = v1.10.1 ]'
check "the first host's token never goes to the second host" '! grep -q "host=localhost.*auth=Bearer tok-127" "$LOG" && grep -q "host=localhost.*auth=Bearer tok-localhost" "$LOG"'

# ---- digests
: > "$LOG"; run "$I" --digest 1.10.0
check "--digest asks for the index and prints its digest" '[ $rc -eq 0 ] && [ "$out" = "$(sha "{\"index\":true}")" ]'
check "--digest uses HEAD, which does not count as a pull" '[ "$(logged "^HEAD")" -ge 1 ] && [ "$(grep -c "^GET.*manifests" "$LOG")" -eq 0 ]'
run "$I" --digest 1.10.0 --json
check "--digest --json names the media type" '[[ $out == *"application/vnd.oci.image.index.v1+json"* ]]'
run "$R/org/nohead" --digest 1.0.0
check "no HEAD: --digest hashes the GET body" '[ $rc -eq 0 ] && [ "$out" = "$(sha "{\"schemaVersion\":2,\"mediaType\":\"application/vnd.oci.image.manifest.v1+json\"}")" ]'
run "$I" --digest nope
check "--digest of a missing tag exits 1" '[ $rc -eq 1 ] && [ -z "$out" ] && [[ $err == *"not found"* ]]'

# ---- registry errors
run "$R/org/basic"
check "a registry that wants a login exits 2" '[ $rc -eq 2 ] && [[ $err == *"wants a login"* ]]'
run "$R/org/private"
check "a refused anonymous token exits 2" '[ $rc -eq 2 ] && [[ $err == *"no anonymous token"* ]]'
run "$R/org/gone"
check "an unknown image exits 2" '[ $rc -eq 2 ] && [[ $err == *"NAME_UNKNOWN"* ]]'
run "$R/org/badjson"
check "a tag list that is not JSON exits 2" '[ $rc -eq 2 ] && [[ $err == *"not JSON"* ]]'
run "$R/org/loop"
check "a registry that repeats a page exits 2" '[ $rc -eq 2 ] && [[ $err == *"same page twice"* ]]'
run "$R/org/endless"
check "an endless tag list stops at the page cap and warns" '[ $rc -eq 0 ] && [ "$out" = 0.0.100 ] && [[ $err == *"warning"* ]]'
run 127.0.0.1:1/org/img
check "a connection error exits 2" '[ $rc -eq 2 ] && [ -z "$out" ]'

# ---- usage
run; check "no target is a usage error (3)" '[ $rc -eq 3 ]'
run acme/tool -n 0; check "-n 0 is a usage error (3)" '[ $rc -eq 3 ]'
run acme/tool -n x; check "-n x is a usage error (3)" '[ $rc -eq 3 ]'
run acme/tool --match '('; check "a bad regex is a usage error (3)" '[ $rc -eq 3 ]'
run acme/tool --bogus; check "an unknown flag is a usage error (3)" '[ $rc -eq 3 ]'
run acme/tool --digest 1.0; check "--digest on a GitHub repo is a usage error (3)" '[ $rc -eq 3 ] && [[ $err == *"docker.io/acme/tool"* ]]'
run "$I" --tags; check "--tags on an image is a usage error (3)" '[ $rc -eq 3 ]'
run "$I" --digest 1.0 --pre; check "--digest with --pre is a usage error (3)" '[ $rc -eq 3 ]'
run 'not a/name!'; check "a bad name is a usage error (3)" '[ $rc -eq 3 ]'
run --help; check "--help exits 0 and documents the exit codes" '[ $rc -eq 0 ] && [[ $out == *"EXIT STATUS"* ]] && [[ $out == *"3 usage error"* ]]'

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
