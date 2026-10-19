# RUIN Suite

The RUIN addon suite for World of Warcraft: Forever, for the RUIN organization of Alliance guilds. Each addon lives in its own repository; this repository ties them together at matching versions, builds the one-zip download, and keeps the player website and the test harness.

## What's here

| Folder | What it is |
| --- | --- |
| `RUIN_Core` … `RUIN_Intel` | The eight addons, linked as git submodules (each points at a commit in its own repo) |
| `build.sh` | Packs all eight into `dist/RUIN_Suite-<version>.zip` |
| `tests/` | Lua 5.1 test harness that simulates several game clients (`tests/run.sh`) |
| `site/` | The player website: plain HTML pages, plus the design-canvas sources in `site/design-canvas` |
| `.github/workflows/release.yml` | Builds the zip and attaches it to a release when a `v*` tag is pushed (needs the `SUITE_TOKEN` secret, see the file) |

## The addons (0.3.0)

| Addon | Repository | What it does |
| --- | --- | --- |
| RUIN Core | [RUIN_Core](https://github.com/10kDevils/RUIN_Core) | Org key, org-wide guild chat, cross-guild officer chat, presence, the RUIN window, module API. Required by every module. |
| RUIN Finder | [RUIN_Finder](https://github.com/10kDevils/RUIN_Finder) | Org-wide LFG board: players and groups, matching, badge, Muster open slots |
| RUIN Warfront | [RUIN_Warfront](https://github.com/10kDevils/RUIN_Warfront) | World PvP objectives, captures, Call to Arms, bounties, war record |
| RUIN Pathfinder | [RUIN_Pathfinder](https://github.com/10kDevils/RUIN_Pathfinder) | Questing routes, waypoint arrow, recorder, sharing, follow a partner |
| RUIN Codex | [RUIN_Codex](https://github.com/10kDevils/RUIN_Codex) | Dungeon and raid journal, learned drops, spec weights, best-in-slot lists, raid planning |
| RUIN Exchange | [RUIN_Exchange](https://github.com/10kDevils/RUIN_Exchange) | Pooled auction prices and trends, crafters, craft requests, leveling plan, bag sweep |
| RUIN Muster | [RUIN_Muster](https://github.com/10kDevils/RUIN_Muster) | Events, role sign-ups and limits, weekly repeats, roster, soft reserves |
| RUIN Intel | [RUIN_Intel](https://github.com/10kDevils/RUIN_Intel) | Sighting reports with map pins, under-attack calls, boss and buff timers |

## Getting it

```sh
git clone --recurse-submodules https://github.com/10kDevils/RUIN_Suite.git
cd RUIN_Suite
./build.sh            # -> dist/RUIN_Suite-0.3.0.zip
```

Extract the zip into your WoW Forever `Interface/AddOns` folder. Players who only want some modules can copy just `RUIN_Core` plus those folders.

## Releasing a new suite version

1. Commit and tag the change in each addon repo that changed (`git tag -a v0.3.1 -m "..."`, then push with `--follow-tags`).
2. In this repo, move each submodule to its new commit: `git submodule update --remote`, or `git -C RUIN_Codex checkout v0.3.1`.
3. Commit the moved submodules, tag this repo with the suite version, and push. The release workflow builds the zip.

Versioning: the third number counts meaningful changes since the second number last went up; the first two numbers change only for suite milestones.

## Tests

```sh
LUA=/path/to/lua5.1 ./tests/run.sh
```

The harness loads the real addon files into several simulated clients in different guilds and checks chat, keys, every module's messages and pages. Last run: 199 checks passing.
