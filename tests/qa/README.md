# RUIN QA loop

A tester agent and a fixer agent that check every RUIN addon in a simulated WoW Forever world,
fix what's really broken, and check again.

## What the simulator covers

- **The world:** `tests/harness.lua` mocks the WoW API, guilds, rosters, chat, addon messages
  and timers for several game clients that talk to each other. `tests/render/frames.lua` is a
  layout engine for frames, anchors, text and textures. `tests/render/render.lua` builds a
  populated org (3 guilds, officers, events, prices, quests) and dumps 73 pages.
- **The explorer (`qa/explore.lua`):** clicks, hovers and types into every control on every
  tab, sub-tab and dialog it opens (two levels deep). It also runs every slash command with
  odd arguments, fires about 70 game events at every client and lets 2 hours of game time pass.
  It records Lua errors, endless loops (a watchdog), timer leaks, slow timers and bad saved
  data.
- **The linter (`qa/lint.py`):** checks every page dump for overlapping or cut-off text,
  off-screen controls, low contrast, and text that looks like a bug ("nil", "%s", broken
  colour codes). Text hidden behind a dialog is ignored.
- **Pictures:** `render/render.py` draws the pages that have layout findings, so the tester can
  look at them.

What it can't catch: anything that only shows on a real GPU or font (exact text widths are
approximate), Blizzard UI taint and protected-action rules, and real server behaviour.
Those still need a check in game.

## Running a pass by hand

```sh
sh tests/qa/run_qa.sh <folder with RUIN_* addons> /tmp/ruin-qa [previous findings.json]
```

This writes `REPORT.md`, `findings.json` and `pictures/` (under a minute). It needs `texlua`
(Lua 5.3, run through `qa/lua51.lua`, a Lua 5.1 shim) and Python 3 with Pillow.
`known-issues.json` lists findings accepted as by design.

## The loop (run by the main Claude session)

1. **Tester** (`.claude/agents/ruin-qa-tester.md`) runs a pass into `/tmp/ruin-qa/round-N`,
   looks at each finding (pictures included) and writes `triage.json` with fix requests, harness
   gaps, by-design items and open questions.
2. **Fixer** (`.claude/agents/ruin-qa-fixer.md`) makes the smallest change for each fix
   request, adds change-log lines, runs the four regression suites and writes
   `fix-results.json`.
3. **Tester again** with the previous `findings.json`: it confirms what the fixes resolved and
   catches anything they broke. Repeat from step 2 until nothing fixable is left (at most three
   rounds).
4. The main session reviews the diff, fixes harness gaps in `tests/`, copies the changed addon
   files to the AddOns folder for testing in game, and bumps versions and pushes only when told.
