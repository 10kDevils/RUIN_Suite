# RUIN QA loop

A tester, a fixer and an optimizer agent that check every RUIN addon in a simulated WoW Forever
world, fix what's really broken, make the addons lighter, and check again.

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
- **The performance probe (`qa/perf.lua`):** measures, by source file and line, event handlers
  in a burst of the busiest game events, OnUpdate scripts, an hour of timers, frames/textures/
  font strings per window, texture files loaded many times, Lua memory and its growth, and
  single calls of 4 ms or more. `texlua qa/run51.lua qa/perf.lua <outdir> [previous perf.json]`
  writes `PERF.md` and `perf.json` (about 10 seconds).

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

## The QA cycle (run by the main Claude session)

1. **Tester** (`.claude/agents/ruin-qa-tester.md`) runs a pass into `/tmp/ruin-qa/round-N`,
   looks at each finding (pictures included) and writes `triage.json` with fix requests, harness
   gaps, by-design items and open questions.
2. **Fixer** (`.claude/agents/ruin-qa-fixer.md`) makes the smallest change for each fix
   request, adds change-log lines, runs the four regression suites and writes
   `fix-results.json`.
3. **Tester again** with the previous `findings.json`: it confirms what the fixes resolved and
   catches anything they broke. Repeat 2-3 until the tester finds no bugs.
4. **Optimizer** (`.claude/agents/ruin-qa-optimizer.md`), once the tester finds no bugs:
   measures with the probe, makes up to about 8 changes that cut calls, memory or repeated
   assets without changing what players see, keeps only the ones the probe shows helped, runs
   the suites and writes `optimizations.json`.
5. **Tester and fixer again** after each optimization round (steps 1-3, with the optimizer's
   `verify` notes), then another optimization round. Stop when the optimizer finds nothing
   worth changing or a round gains little (about three optimization rounds at most).
6. The main session reviews the diff, fixes harness gaps in `tests/`, copies the changed addon
   files to the AddOns folder for testing in game, and bumps versions and pushes only when told.
