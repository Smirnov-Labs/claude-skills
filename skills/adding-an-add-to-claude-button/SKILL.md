---
name: adding-an-add-to-claude-button
description: Use when you add an "Add to Claude" or "Connect to Claude" button or link for a remote MCP server to a README, landing page, docs page or web app, or when such a link opens an empty dialog, loses the server URL or points at //mcp.
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
| 0 | Printed. Read stderr for warnings: a URL that is not https, a local host, a doubled slash that it removed. |
| 3 | Usage error. `--help` has the details. |

## The link

`https://claude.ai/customize/connectors?modal=add-custom-connector&connectorName=NAME&connectorUrl=ENCODED_URL` ([docs](https://claude.com/docs/connectors/building/directory-vs-custom))

- It only fills in the dialog. Claude says the values came from an external link, and the user confirms. A signed-out user signs in first.
- On Team and Enterprise plans, an Owner adds custom connectors for the organization, and most members can't add one ([docs](https://claude.com/docs/connectors/custom/add-unlisted)). Tell members to ask an Owner, and give Owners the `--admin` link. The Free plan allows one custom connector.
- A connector in the directory has its own link, `https://claude.ai/directory/connectors/SLUG`.

## OAuth

```bash
# The resource and its authorization server. Some servers use .../oauth-protected-resource/mcp.
curl -s https://mcp.example.com/.well-known/oauth-protected-resource | jq '{resource, authorization_servers}'
# What that authorization server supports
curl -s https://auth.example.com/.well-known/oauth-authorization-server | jq \
  '{registration_endpoint, client_id_metadata_document_supported, token_endpoint_auth_methods_supported}'
```

Claude's recommended OAuth client needs `client_id_metadata_document_supported: true` and `"none"` in the auth methods. If the server has only a `registration_endpoint`, add this line next to the button:

> If Claude asks which OAuth client to use, choose Register automatically.

## Design

- Use a text label, such as "Add to Claude" or the docs' "Connect to Claude". Anthropic's [Trademark Guidelines](https://assets.claude.com/f7874b435aabdaee5f836e888b4439b9b56a934b.pdf) allow its logos only with prior approval. shields.io's `logo=claude` draws the Claude mark, so the badge has text only.
- Text needs 4.5:1 contrast (WCAG AA). White on Claude orange #D97757 is 3.1:1, and on #C15F3C 4.2:1. The html button is #FAF9F5 on #1F1E1D (15.8:1) with a grey border for dark pages, and the badge is white on #B05730 (4.9:1). Your own tokens are fine if they pass.
- Keep the real `<a>`, `target="_blank" rel="noopener noreferrer"`, the hidden "(opens in a new tab)", the `:focus-visible` ring and the 44 px height. Give an icon `aria-hidden="true"`.
- GitHub removes `<style>` from READMEs, so use `markdown` or `badge` there. `for-the-badge` writes capitals. A committed SVG button needs `role="img"`, an `aria-label`, a `<title>` and a border for GitHub's dark theme.

## Verify

1. Decode the link: `python3 -c 'import sys,urllib.parse as u; print(u.parse_qs(u.urlsplit(sys.argv[1]).query))' "LINK"`. Expect only `modal`, `connectorName` and `connectorUrl`.
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
