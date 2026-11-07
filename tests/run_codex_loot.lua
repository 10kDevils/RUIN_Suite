-- Codex 0.5.3: every dungeon's loot, read from Questie or QuestieDB while you
-- play (a made-up QuestieDB here; none of Questie's data is used). Bosses and
-- rares get their own lists, the rest is Trash, and the launch data's names
-- fill in what the database lacks. Runs after the other run_features_*.lua files.
local alice, check, errorsSoFar = T.alice, T.check, T.errorsSoFar
local Server = Server
local here = T.here or "."
local fakeQuestieDB = dofile(here .. "/fake_questiedb.lua")

print("Codex: dungeon loot from QuestieDB")
do
    local R = alice.env.RUIN_API
    local CX = R:GetModule("Codex")
    local QL = CX.QuestieLoot
    local dbC = alice.env.RUIN_CodexDB
    local hot = CX:FindDungeon("Hall of Thanes")
    local function text(lines) local t = {}; for _, l in ipairs(lines) do t[#t + 1] = l[1] end; return table.concat(t, "\n") end

    -- without the database: the launch list, and a hint
    QL.state, dbC.qloot = "idle", nil
    local t = text(CX.JournalLines(CX:FindDungeon("The Stockade"), false))
    check(t:find("Install QuestieDB (or Questie) for this dungeon's full loot list", 1, true), "without QuestieDB, the Journal says how to get the full loot list")

    local undo = fakeQuestieDB(alice, {})
    QL.state, dbC.qloot = "idle", nil
    QL.state = "building"     -- what the page shows while the real (much larger) database is read
    t = text(CX.JournalLines(hot, false))
    check(t:find("Reading every dungeon's loot", 1, true), "while it reads, the Journal says so")
    QL.state = "idle"
    QL.Start()
    for _ = 1, 20 do Server:Advance(0.05) end
    check(QL.state == "ready" and dbC.qloot and dbC.qloot.d["Hall of Thanes"], "a moment later every dungeon's list is ready and saved")

    local loot = alice.mns.RUIN_Codex.Loot.For(hot)
    check(loot and loot.source == "questie", "the Journal's loot now comes from QuestieDB")
    local by = {}
    for _, b in ipairs(loot.bosses) do by[b.name] = b end
    local durgen = by["Durgen Dirgehammer"]
    local names = {}
    for _, it in ipairs(durgen and durgen.items or {}) do names[#names + 1] = it.name .. (it.id and "#" .. it.id or "") end
    check(table.concat(names, ",") == "Durgen's Crescent Axe#8002,Direhammer Leggings#8001,Durgen Dirgehammer's Head#8003,Robes of the Disgraced Thane",
        "a boss lists its drops with item IDs (gear by item level, quest items last), then launch-data drops the database lacks (" .. table.concat(names, ",") .. ")")
    check(durgen.items[2].info and durgen.items[2].info:find("Legs", 1, true), "a drop in both lists keeps the launch data's slot")
    local faldrim = by["Faldrim Anvilmar"]
    check(faldrim and faldrim.items[1] and faldrim.items[1].name == "Ephemeral Choker" and not faldrim.items[1].id,
        "the launch data's drops the database doesn't have yet stay on the list")
    check(by["Old Rustjaw"] and by["Old Rustjaw"].tip:find("Rare", 1, true) and by["Old Rustjaw"].items[1].id == 8004, "a rare gets its own list")
    local trash = {}
    for _, it in ipairs(loot.trash) do trash[#trash + 1] = it.name end
    check(table.concat(trash, ","):find("Thane Guard Bracers", 1, true), "drops from the other mobs are under Trash")
    check(not table.concat(trash, ","):find("Healing Potion", 1, true) and not table.concat(trash, ","):find("Mining Mallet", 1, true),
        "potions and world drops (mostly dropped outside) are left out")

    local lines = CX.JournalLines(hot, false)
    t = text(lines)
    check(t:find("Loot read from QuestieDB", 1, true) and t:find("Trash|r", 1, true), "the page says where the loot comes from, with a Trash list")
    local axe
    for _, l in ipairs(lines) do if l[1]:find("Crescent Axe", 1, true) then axe = l end end
    check(axe and axe.link == "item:8002", "every listed item opens its full tooltip")

    -- built once: the saved list is reused until the database changes
    local stamp = dbC.qloot.stamp
    QL.state = "idle"
    QL.Start()
    check(QL.state == "ready" and dbC.qloot.stamp == stamp, "next time, the saved list is used at once")

    undo()
    QL.state, dbC.qloot = "idle", nil
    errorsSoFar("codex loot")
end
