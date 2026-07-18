---
name: kde-store-publish
description: >-
  Publish or update this plasmoid (Agent Usage) on the KDE Store (store.kde.org).
  Use when asked to 发版 / 更新上架 / 重新上架 / republish / bump the store version /
  release a new plasmoid version to the KDE Store, or when a code fix should reach
  Discover users. Covers first-time publish (Add Product) and version updates
  (Edit + upload new .plasmoid + bump version), driving store.kde.org via the
  claude-browser MCP. Project-specific values (product id, 5-level category,
  license, tags, logo source) are baked in below.
---

# Publish / update Agent Usage on the KDE Store

Drives store.kde.org (OpenDesktop/Pling backend) to publish or update this plasmoid.
No compile, no review queue; product goes live on Save (public search/Discover index
refreshes minutes→hours later).

## This project's fixed values (reuse verbatim)

| Field | Value |
|-------|-------|
| Product URL | https://store.kde.org/p/2365328/ |
| Account | store username `chrisyam` (already public via the product URL) |
| Category (5-level cascade) | `Linux/Unix Desktops` → `Desktop Extensions` → `KDE Plasma Extensions` → `Plasma 6 Extensions` → `Plasma 6 Applets` |
| License | GPLv3 |
| Original/Mod | **Mod** (derived from izll's GPL plasma-claude-usage — honest attribution) |
| Link to Source/Code + Homepage | https://github.com/cygmris/plasma-agent-usage |
| Tags (max 5, controlled vocab) | claude, codex, gemini, plasmoid, plasma6 |
| Logo source | `contents/icons/widget.svg` → render with `scripts/render-logo.sh` |
| Gallery screenshots | `screenshots/on-panel.png`, `screenshots/agent-usage.png` |
| plugin id | `org.kde.plasma.agentusage` |

## The category is the #1 gotcha

Discover's "Get New Widgets" queries the category in `/usr/share/knsrcfiles/plasmoids.knsrc`
(`Categories=Plasma 6 Extensions`). The store's Add/Edit form exposes this as a **5-level
cascade** — each level's dropdown appears only after selecting the parent, and each is a
required field. Select **all five** (see table). Wrong/incomplete category = invisible in
Discover.

## Before driving the browser

1. Load the **claude-browser** skill (attach to the常驻 chrome on CDP :9223; never the
   self-launching chrome-devtools plugin). Health check: `curl -s --max-time 5 http://127.0.0.1:9223/json/version`.
2. Use `mcp__claude-browser__*` tools. Open store pages in a NEW tab (`new_page`); other
   sessions share this browser.
3. Confirm logged in as chrisyam (avatar menu). If not, ask the user to log in in the
   visible chrome window.

## Path A — Update an existing release (the common case)

Order matters. Build first, then drive the browser.

### 1. Build + bump version (local)

```bash
# bump metadata.json KPlugin.Version (e.g. 1.0.1 -> 1.0.2) FIRST, then:
./build.sh                      # -> plasma-agent-usage.plasmoid  (repo root)
```

### 2. Get the package into a workspace root

`mcp__claude-browser__upload_file` **rejects paths outside the session's workspace roots**.
This repo may live outside them. Copy the built package into the session scratchpad and
upload from there:

```bash
cp plasma-agent-usage.plasmoid "$SCRATCHPAD/plasma-agent-usage.plasmoid"
```

### 3. Upload the new file (product page → Files)

- Navigate to the product page / `store.kde.org/u/chrisyam/products`, click **Files (N)**.
- Check **"I accept the Terms and Conditions"**.
- The drop-zone's `<input type=file>` is hidden (`display:none`) and has no a11y uid.
  **Reveal it** via `evaluate_script`, then re-snapshot to get its uid:
  ```js
  () => { const el = document.querySelector('input[type=file][data-file-upload]');
    el.id='cc-up'; el.style.display='block'; el.style.opacity='1'; el.removeAttribute('hidden');
    return {ok:!!el}; }
  ```
- `upload_file` the copied `.plasmoid`. The store auto-renames it with a timestamp suffix
  if the base name collides with the existing file — that's fine.
- In the new file's row, set its **File version** and click that row's **Update**.
- **Do NOT click the trash/delete on the old file** — it can fire a JS `confirm()` dialog
  that blocks the CDP session. Leaving the old file is harmless (downloads are archived;
  the highest-version file drives updates). Tell the user they can delete it manually.
- Close the Files modal.

### 4. Bump the PRODUCT version (Edit → Basics)

The listing title version is a **product-level** field, separate from the per-file version.
Discover only offers an update when the product version increases.

- Click **Edit** (loads all existing values — category, description, Mod, GPLv3, tags, logo
  all preserved; don't re-enter them).
- Basics tab → **Version** field → set to the new version.
- (Optional) **Changelog** tab: the text box is an **EasyMDE** editor — `fill` on the hidden
  textarea fails; click the editor area and use `type_text`. Fill Title + text, click
  **Save Changelog**.
- Click the main **Save** → redirects to products list. Verify the title now reads the new
  version + "updated seconds ago".

### 5. Make the fix visible locally (optional but expected)

```bash
kpackagetool6 -t Plasma/Applet -u plasma-agent-usage.plasmoid
rm -f ~/.local/share/plasma-agent-usage-cache.json    # drop stale cached data
kquitapp6 plasmashell && kstart plasmashell           # DISRUPTIVE: restarts the user's panel — confirm first
```

## Path B — First-time publish (Add Product)

Avatar menu → **Add Product**, 3-step wizard:

- **Basics**: Product Name; the 5-level Category cascade (table above); Description; Version;
  Link to Source/Code; Original/Mod = Mod; License = GPLv3; **Product Logo** (run
  `scripts/render-logo.sh`, then copy into scratchpad + upload); **Gallery Pictures**
  (required) = the two screenshots; homepage link.
- **Settings**: one "download lock" checkbox — leave unchecked.
- **Files**: accept T&C → reveal hidden input (see Path A step 3) → upload `.plasmoid` →
  set file version → **Save**.
- After publish, on the product row click **Manage tags** → add up to **5** tags. The tag
  box is a **controlled vocabulary** (autocomplete tree): type, then click the suggested
  item; free-typed non-existent tags are rejected. Click **Done**.

## Browser-automation gotchas (recap)

- Category = 5 required cascading dropdowns; must reach `Plasma 6 Extensions` for Discover.
- Upload path must be inside a workspace root → copy to scratchpad.
- Hidden `data-file-upload` input → reveal via `evaluate_script` + re-snapshot for its uid.
- Product-level Version ≠ per-file Version — bump both.
- Tags: max 5, controlled vocab, pick from autocomplete.
- Changelog = EasyMDE → click editor + `type_text` (not `fill`).
- Never click the file delete trash (JS `confirm()` blocks CDP).
- `take_screenshot` sometimes times out on this SPA; prefer `take_snapshot`.

## Not a store bug: stale plan badge

The Claude plan badge (e.g. "Max 5x") comes only from `~/.claude/.credentials.json`
`rateLimitTier`; the usage API carries no plan field. A mid-cycle plan upgrade shows up
only after the local token refreshes — the user runs `claude` (re-login). Nothing to fix
in the widget or the store.
