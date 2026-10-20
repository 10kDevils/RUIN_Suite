# UI renderer

Draws every RUIN page and sub-page outside the game, so layout changes can be checked as pictures.

- `frames.lua` stands in for WoW's frame API: it resolves anchors and sizes the way the game does (closely enough to see overlaps, clutter and colors) and dumps every visible region.
- `render.lua` builds three RUIN clients with sample org data (events, sightings, Finder listings, links), opens each tab and sub-tab on one of them and writes a JSON layout per page.
- `render.py` draws those layouts as PNG screenshots with Playwright and Chromium.

```
RUIN_CORE_DIR=../RUIN_Core lua render/render.lua /tmp/ruin-ui          # as an officer
RENDER_AS=eve RUIN_CORE_DIR=../RUIN_Core lua render/render.lua /tmp/ruin-ui-member
python3 render/render.py /tmp/ruin-ui
```

Fonts and icons are stand-ins (icons draw as brown squares), so judge spacing, overlap and color, not exact text width.
