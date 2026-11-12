# Rebuilding RUIN Quest Data

Needs Lua 5.1, Python 3, an installed QuestieDB (Forever build) and LibDeflate.

```sh
cd tools/questdb
Q=/path/to/AddOns/QuestieDB
LD=/path/to/LibDeflate.lua
mkdir -p out
lua5.1 extract.lua "$Q" "$LD" wowenv.lua Alliance out/Alliance.lua
lua5.1 extract.lua "$Q" "$LD" wowenv.lua Horde out/Horde.lua
python3 assemble.py out ../../RUIN_Pathfinder/QuestData
```

Update NOTICE.md with the QuestieDB version used. The data stays GPLv3.
