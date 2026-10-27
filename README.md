# RUIN Gaming Companion App

The RUIN Gaming Companion App for World of Warcraft: Forever (and Retail), made for the RUIN organization of Alliance guilds: a leveling and quest guide, events and group finding, class macros and a dungeon journal, and one guild across every RUIN guild. Each addon lives in its own repository; this repository ties them together at matching versions, builds the one-zip download, and keeps the player website and the test harness.

## What's here

| Folder | What it is |
| --- | --- |
| `RUIN_Core` … `RUIN_Exchange` | The six addons, linked as git submodules (each points at a tagged commit in its own repo) |
| `build.sh` | Packs all six into `dist/RUIN_Gaming_Companion_App-<version>.zip` |
| `tests/` | Lua 5.1 test harness that simulates several game clients (`tests/run.sh`) |
| `tests/render/` | Draws every page and sub-page outside the game as PNG screenshots, for checking layout and colors (see its README) |
| `site/` | The player website: plain HTML pages, plus the design-canvas sources in `site/design-canvas` |
| `.github/ISSUE_TEMPLATE/feedback.yml` | The feedback form on GitHub (Settings → Feedback in the game opens a new issue with the player's text filled in) |
| `.github/workflows/release.yml` | Publishes each new version: on a push to `main` whose RUIN Core version has no release yet, builds the zip and creates the release with notes from the change logs (also on a pushed `v*` tag, or run by hand) |

## The addons (app version 0.4.4)

In the RUIN window the tabs run Guild, Finder, Muster, Pathfinder, Codex, Exchange and Settings by default; each player can rearrange them under Settings → Options → Tab order. Guild and Settings use RUIN's navy, teal and gold; each module's page and tab use that addon's color.

| Addon | Version | Repository | What it does |
| --- | --- | --- | --- |
| RUIN Core | 0.4.4 | [RUIN_Core](https://github.com/10kDevils/RUIN_Core) | The RUIN window, Guild page (census of every guild with search and history, every guild's roster with moderation, people and appointed offices, guild and org chat with search, pins and block words, the Watch for reports and sanctions, guild bank snapshots, a join screen for newcomers) and community links, what's new after updates and RUIN lines in the right-click menu, Settings with the org admin's guild list, org key or key phrase, and feedback, org-wide guild and officer chat, presence, module API. Required by every module. |
| RUIN Codex | 0.4.0 | [RUIN_Codex](https://github.com/10kDevils/RUIN_Codex) | Class macros you can add in one click, a macro command reference, dungeon and raid journal with boss loot lists and learned drops, run planning, an upgrade line on item tooltips |
| RUIN Pathfinder | 0.4.0 | [RUIN_Pathfinder](https://github.com/10kDevils/RUIN_Pathfinder) | Leveling checklist with waypoint arrow, Alliance routes 1-30 checked against the Forever quest database, Questie integration, quests shared across RUIN, class track, recorder, officer routes, follow a partner |
| RUIN Finder | 0.4.1 | [RUIN_Finder](https://github.com/10kDevils/RUIN_Finder) | Org-wide LFG board: players and groups, matching, badge, Muster open slots, "Find group" from a sighting; where members are, layer detection and layer hops, member marks on nameplates, world boss and buff timers |
| RUIN Muster | 0.4.2 | [RUIN_Muster](https://github.com/10kDevils/RUIN_Muster) | Events, role sign-ups and limits, weekly repeats, roster, soft reserves, a Plan tab with raid groups and the War Room's squads and after-action reports, loot notes, rally points, bounties, an automatic Most Wanted list, world sightings with map pins and under-attack calls |
| RUIN Exchange | 0.4.2 | [RUIN_Exchange](https://github.com/10kDevils/RUIN_Exchange) | Pooled auction prices and trends, crafters by profession with item quality, craft requests, leveling plan, bag sweep, the guild treasury book, a confirmed crafting history |

RUIN Intel ([RUIN_Intel](https://github.com/10kDevils/RUIN_Intel)) is retired: its sightings moved to RUIN Muster, its timers to RUIN Finder, and starting a group from a sighting is in RUIN Finder.

RUIN Warfront ([RUIN_Warfront](https://github.com/10kDevils/RUIN_Warfront)) is retired: RUIN uses [Overlord Forever](https://www.curseforge.com/wow/addons/overlord-forever) for world PvP, and Warfront's bounties and meeting points moved to RUIN Muster.

## Getting it

```sh
git clone --recurse-submodules https://github.com/10kDevils/RUIN_Suite.git
cd RUIN_Suite
./build.sh            # -> dist/RUIN_Gaming_Companion_App-0.4.4.zip
```

Extract the zip into your WoW Forever `Interface/AddOns` folder. Players who only want some modules can copy just `RUIN_Core` plus those folders. The newest zip is always on the [latest release](https://github.com/10kDevils/RUIN_Suite/releases/latest).

## Releasing a new version

1. Commit the change in each addon repo that changed and push it.
2. In this repo, move each submodule to its new commit (`git -C RUIN_Codex checkout <commit or tag>`), commit, and push.
3. That's it: the push to `main` runs the release workflow, which sees that RUIN Core's version has no release yet, builds the zip and publishes the release `v<version>` (for example `v0.4.2`) with the change log entries of the addons that changed. Pushing a tag like `v0.4.2` yourself still works too.

Versioning: the third number counts meaningful changes since the second number last went up; the first two numbers change only for app milestones. The app's version is RUIN Core's.

## Feedback

Players write feedback under **Settings → Feedback** in the RUIN window and press *Copy GitHub link*. WoW addons can't reach the internet, so RUIN gives them a link to a new issue in this repo, labeled `feedback`, with their text, its type and their RUIN version filled in; they open it in a browser and press Submit (a free GitHub account is needed). Issues here are public.

## Tests

```sh
LUA=/path/to/lua5.1 ./tests/run.sh
```

The harness loads the real addon files into several simulated clients in different guilds and checks chat, keys, every module's messages and pages. Last run: 436 checks passing.
