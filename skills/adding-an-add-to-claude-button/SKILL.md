---
name: adding-an-add-to-claude-button
description: Use when adding an "Add to Claude" or "Connect to Claude" button or link for a remote MCP server, or when such a link opens an empty dialog, loses the server URL or points at //mcp.
---

# Add to Claude button

A claude.ai link opens the **Add custom connector** dialog with a server's name and URL filled in. `add-to-claude-link` prints the link, or a button that uses it, with the encoding and escaping done.

| To get | Run |
|---|---|
| The link | `add-to-claude-link Example https://mcp.example.com/mcp` |
| A README text link | add `--format markdown` |
| A README badge (shields.io) | add `--format badge` |
| A web page button | add `--format html` |
| A React component and its CSS | add `--format react` |
| The link for organization Owners | add `--admin` |

| Exit | Meaning |
|---|---|
| 0 | Printed. Read any warnings on stderr. |
| 3 | Usage error. `--help` has the details. |

## The link

`https://claude.ai/customize/connectors?modal=add-custom-connector&connectorName=NAME&connectorUrl=ENCODED_URL` ([docs](https://claude.com/docs/connectors/building/directory-vs-custom))

- It only fills in the dialog. Claude says the values came from an external link, and the user confirms. A signed-out user signs in first.
- On Team and Enterprise plans, most members can't add custom connectors ([docs](https://claude.com/docs/connectors/custom/add-unlisted)). Tell them to ask an Owner, and give Owners the `--admin` link. The Free plan allows one custom connector.
- A connector in the directory has its own link, `https://claude.ai/directory/connectors/SLUG`.

## OAuth

Read the protected resource metadata in Claude's order: the `resource_metadata` URL from the 401, then the path-specific document, then the root one.

```bash
U=https://mcp.example.com/mcp W=https://mcp.example.com/.well-known/oauth-protected-resource
R=$(curl -si -X POST "$U" | grep -i '^www-authenticate' | sed -n 's/.*resource_metadata="\([^"]*\)".*/\1/p')
for m in $R "$W/mcp" "$W"; do curl -sf "$m" && break; done | jq '{resource, authorization_servers}'
```

Claude uses only the first authorization server. Split its issuer into an origin `O` and a path `P`, which is often empty, then read its metadata:

```bash
O=https://auth.example.com P=/tenant
for m in "$O/.well-known/oauth-authorization-server$P" "$O/.well-known/openid-configuration$P" "$O$P/.well-known/openid-configuration"
do curl -sf "$m" && break; done | jq '{registration_endpoint, client_id_metadata_document_supported, token_endpoint_auth_methods_supported}'
```

Claude's recommended OAuth client needs `client_id_metadata_document_supported: true` and `"none"` in the auth methods. If the server has only a `registration_endpoint`, add this line next to the button:

> If Claude asks which OAuth client to use, choose Register automatically.

## Design

- Use a text label, such as "Add to Claude" or the docs' "Connect to Claude". Anthropic's [Trademark Guidelines](https://assets.claude.com/f7874b435aabdaee5f836e888b4439b9b56a934b.pdf) allow its logos only with prior approval, so the badge leaves out shields.io's `logo=claude`.
- Text needs 4.5:1 contrast (WCAG AA). White on Claude orange #D97757 is 3.1:1, and on #C15F3C 4.2:1. The html button is #FAF9F5 on #1F1E1D (15.8:1) with a grey border for dark pages, and the badge is white on #B05730 (4.9:1). Your own tokens are fine if they pass.
- Keep the real `<a>`, `target="_blank" rel="noopener noreferrer"`, the hidden "(opens in a new tab)", the `:focus-visible` ring and the 44 px height. Give an icon `aria-hidden="true"`.
- GitHub removes `<style>` from READMEs, so use `markdown` or `badge` there. `for-the-badge` writes capitals. A committed SVG button needs `role="img"`, an `aria-label`, a `<title>` and a border for GitHub's dark theme.

## Verify

1. Decode the link: `python3 -c 'import sys,urllib.parse as u; print(u.parse_qs(u.urlsplit(sys.argv[1]).query.replace("+", "%2B")))' "LINK"`. Expect only `modal`, `connectorName` and `connectorUrl`. A `+` stays a `+`, as in `decodeURIComponent`.
2. `connectorUrl` must equal the `resource` value exactly, or sign-in fails.
3. Open the link once, signed in. The dialog must show both values.
4. Screenshot it at 1280 and 390 px wide. Press Tab to see the focus ring.

## Common mistakes

| Mistake | What happens |
|---|---|
| `URLSearchParams` or `quote_plus` builds the query | A space becomes `+`, and `decodeURIComponent` keeps the `+`. |
| You paste the HTML href, with `&amp;`, into code or config | Claude gets `amp;connectorName`, so the name and URL are missing. |
| You join an origin that ends in `/` to `/mcp` | The link has `//mcp`. Strip the slash first. |
| A localhost or LAN URL | Claude connects from Anthropic's servers and cannot reach it. Use a public URL or an [MCP tunnel](https://claude.com/docs/connectors/mcp-tunnels/overview). |
