---
name: finding-latest-versions
description: Use when you need the newest release of a GitHub repo or the newest tag of a container image (Docker Hub, ghcr.io, quay.io, registry.k8s.io or any OCI registry) before you bump or pin a version, or the digest of an image tag. Also use when you are about to run gh release list, call releases/latest or do a registry token handshake by hand.
---

# Finding latest versions

`latest-version` (in this skill's `bin/`) prints the newest version of a GitHub repo or a container image. It sorts tags as versions, skips pre-releases unless you ask, and reads every page.

Do not look versions up by hand. GitHub's `releases/latest` picks by date, not by version, so a backport can win. A registry lists tags in text order, one page at a time. So `1.9` comes after `1.10`, and the newest tag can be on the last page.

| You need | Run |
|---|---|
| The newest release of a GitHub repo | `latest-version cloudflare/cloudflared` |
| The 3 newest tags of an image | `latest-version docker.io/library/caddy -n 3` |
| A tag on any other registry | `latest-version ghcr.io/project-zot/zot` |
| A Docker Hub user image | `latest-version docker.io/grafana/grafana` |
| The newest of one line | `latest-version kubernetes/kubernetes --match '^v1\.31\.'` |
| The newest variant of an image | `latest-version caddy --match '-alpine$'` |
| Pre-releases too | `latest-version prometheus/prometheus --pre` |
| Tags with a prefix, such as `jq-1.8.2` | `latest-version jqlang/jq --match '^jq-(.+)$'` |
| The digest, to pin an image | `latest-version registry.k8s.io/pause --digest 3.10.2` |
| All fields, for a script | add `--json` |

GitHub calls use `gh api` when gh has a login, else the public API (60 calls an hour). Registries get an anonymous pull token. `latest-version --help` lists every flag.

## Reading the output

The output is one tag per line, newest first, as the source spells it.

| Exit | Meaning | Do |
|---|---|---|
| 0 | found | use the first line |
| 1 | nothing matched | read stderr: it says what it set aside, and can suggest a `--match` |
| 2 | network or API error | read stderr: a rate limit, a private image or an unknown repo |
| 3 | usage error | correct the command |

`--digest` prints `sha256:...`, for a multi-platform image the digest of the index, which `docker pull` uses.

How tags sort:

- `1.10` is newer than `1.9`. A `v` prefix does not count.
- A suffix with `rc`, `beta`, `alpha`, `dev` or a similar word makes a pre-release. It shows only with `--pre`.
- Any other suffix (`-alpine`, `-slim`, `-1`) makes a variant. Variants show only with `--match`.
- Tags that are not versions (`latest`, `main`, `sha-...`, dates) are set aside.
- `13.3` and `13.3.0` are one version. The longer tag prints; `--json` lists the other under `aliases`.

## Common mistakes

- A bare `OWNER/REPO` always means GitHub. For the `grafana/grafana` image, write `docker.io/grafana/grafana`.
- A release tag and an image tag can differ: `v2.11.9` on GitHub is `2.11.9` on Docker Hub. To bump an image, ask the registry, not GitHub.
- A repo that stopped making GitHub releases still answers with its last one. If the answer looks old, try `--tags`.
- `--match '^v?2\.'` also lets in variants such as `2.8.4-alpine`. To get only plain versions, anchor both ends: `--match '^v?2\.[0-9.]+$'`.
