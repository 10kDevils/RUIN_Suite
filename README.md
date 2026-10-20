# RUIN Gaming Companion App

The RUIN Gaming Companion App for World of Warcraft: Forever (and Retail), made for the RUIN organization of Alliance guilds: time-ranked gear, a leveling and quest guide, and one guild across every RUIN guild. Each addon lives in its own repository; this repository ties them together at matching versions, builds the one-zip download, and keeps the player website and the test harness.

## What's here

| Folder | What it is |
| --- | --- |
| `RUIN_Core` … `RUIN_Exchange` | The six addons, linked as git submodules (each points at a tagged commit in its own repo) |
| `build.sh` | Packs all six into `dist/RUIN_Gaming_Companion_App-<version>.zip` |
| `tests/` | Lua 5.1 test harness that simulates several game clients (`tests/run.sh`) |
| `tests/render/` | Draws every page and sub-page outside the game as PNG screenshots, for checking layout and colors (see its README) |
| `site/` | The player website: plain HTML pages, plus the design-canvas sources in `site/design-canvas` |
| `.github/workflows/release.yml` | Builds the zip and attaches it to a release when a `v*` tag is pushed or the workflow is run by hand (needs the `SUITE_TOKEN` secret, see the file) |

## The addons (app version 0.3.12)

In the RUIN window the tabs run Guild, Finder, Muster, Pathfinder, Codex, Exchange and Options. Guild and Options use RUIN's navy, teal and gold; each module's page and tab use that addon's color.

| Addon | Version | Repository | What it does |
| --- | --- | --- | --- |
| RUIN Core | 0.3.12 | [RUIN_Core](https://github.com/10kDevils/RUIN_Core) | The RUIN window, Guild page and community links, Settings, org key, org-wide guild and officer chat, presence, module API. Required by every module. |
| RUIN Codex | 0.3.8 | [RUIN_Codex](https://github.com/10kDevils/RUIN_Codex) | Gear Path (upgrades ranked by time, solo and group), class macros you can add in one click, dungeon journal, learned drops, spec weights, officer best-in-slot lists, raid planning |
| RUIN Pathfinder | 0.3.9 | [RUIN_Pathfinder](https://github.com/10kDevils/RUIN_Pathfinder) | Leveling checklist with waypoint arrow, class track, recorder, route sharing, follow a partner; uses Questie when installed |
| RUIN Finder | 0.3.5 | [RUIN_Finder](https://github.com/10kDevils/RUIN_Finder) | Org-wide LFG board: players and groups, matching, badge, Muster open slots, "Find group" from a sighting |
| RUIN Muster | 0.3.7 | [RUIN_Muster](https://github.com/10kDevils/RUIN_Muster) | Events, role sign-ups and limits, weekly repeats, roster, soft reserves, rally points, bounties, world sightings with map pins and under-attack calls, boss and buff timers |
| RUIN Exchange | 0.3.4 | [RUIN_Exchange](https://github.com/10kDevils/RUIN_Exchange) | Pooled auction prices and trends, crafters, craft requests, leveling plan, bag sweep |

RUIN Intel ([RUIN_Intel](https://github.com/10kDevils/RUIN_Intel)) is retired: its sightings and timers moved to RUIN Muster, and starting a group from a sighting is in RUIN Finder.

RUIN Warfront ([RUIN_Warfront](https://github.com/10kDevils/RUIN_Warfront)) is retired: RUIN uses [Overlord Forever](https://www.curseforge.com/wow/addons/overlord-forever) for world PvP, and Warfront's bounties and meeting points moved to RUIN Muster.

## Getting it

```sh
git clone --recurse-submodules https://github.com/10kDevils/RUIN_Suite.git
cd RUIN_Suite
./build.sh            # -> dist/RUIN_Gaming_Companion_App-0.3.8.zip
```

Extract the zip into your WoW Forever `Interface/AddOns` folder. Players who only want some modules can copy just `RUIN_Core` plus those folders. The newest zip is always on the [latest release](https://github.com/10kDevils/RUIN_Suite/releases/latest).

## Releasing a new version

1. Commit the change in each addon repo that changed and push it.
2. In this repo, move each submodule to its new commit (`git -C RUIN_Codex checkout <commit or tag>`), commit, and push.
3. Publish a release named after RUIN Core's version (for example `v0.3.8`). The release workflow builds the zip and attaches it.

Versioning: the third number counts meaningful changes since the second number last went up; the first two numbers change only for app milestones. The app's version is RUIN Core's.

## Tests

```sh
LUA=/path/to/lua5.1 ./tests/run.sh
```

The harness loads the real addon files into several simulated clients in different guilds and checks chat, keys, every module's messages and pages. Last run: 238 checks passing.
