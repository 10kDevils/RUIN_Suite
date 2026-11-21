-- RUIN Quest Data: the bundled quest database, read by Pathfinder when the
-- addon (nothing else is read).
local alice, check, errorsSoFar = T.alice, T.check, T.errorsSoFar
local here = T.here or "."

print("Pathfinder: RUIN Quest Data")
do
    local env = alice.env
    local pf = env.RUIN_API:GetModule("Pathfinder")
    local QB = pf.QB
    -- the data ships inside Pathfinder, loaded by its TOC before the code that reads it
    local toc = io.open(here .. "/../RUIN_Pathfinder/RUIN_Pathfinder.toc"):read("*a")
    local d, h, qdb = toc:find("QuestData\\Data.lua", 1, true), toc:find("QuestData\\Horde.lua", 1, true), toc:find("QuestDB.lua", 1, true)
    check(d and h and qdb and d < h and h < qdb and not toc:find("OptionalDeps: RUIN_QuestData", 1, true), "Pathfinder's TOC loads its own quest data, before QuestDB.lua")
    check(io.open(here .. "/../RUIN_Pathfinder/QuestData/LICENSE.md") and io.open(here .. "/../RUIN_Pathfinder/QuestData/NOTICE.md"), "with the data's license and notice beside it")
    local saved = { RUIN_QuestData = env.RUIN_QuestData }
    env.RUIN_QuestData = nil
    local t0 = os.clock()
    for _, f in ipairs({ "Data.lua", "Horde.lua" }) do
        local chunk = assert(loadfile(here .. "/../RUIN_Pathfinder/QuestData/" .. f))
        setfenv(chunk, env)
        chunk()
    end
    local took = os.clock() - t0
    QB.Forget()
    local D = env.RUIN_QuestData
    local n = 0
    for _ in pairs(D.q) do n = n + 1 end
    check(n > 5000, ("the database loads every quest (%d, %.2f s)"):format(n, took))
    local faction = env.UnitFactionGroup
    env.UnitFactionGroup = function() return "Horde", "Horde" end
    check(QB.Has() and QB.Source() == "RUIN Quest Data", "Pathfinder reads it (" .. tostring(QB.Source()) .. ")")
    check(D.applied == "Horde" and D.q[113][22] == 32, "the Horde's own rows are put in for a Horde character")
    env.UnitFactionGroup = faction
    local q = QB.Quest(2)
    check(q and q.name == "Sharptalon's Claw" and q.level and #q.ends > 0, "a quest's name, level and who takes it in (" .. tostring(q and q.ends[1]) .. ")")
    local spots = QB.Spots(7, "objective")
    check(#spots > 0 and spots[1].map == 1429, "where its targets are: Kobold Camp Cleanup's vermin in Elwynn (" .. #spots .. " places)")
    local f = QB.Spot(2, "finish")
    check(f and f.map and f.x > 0 and f.x < 1, "where it's handed in, on a map")
    -- a zone's quests for this character
    local zones = QB.Zones()
    check(#zones > 20, "zone routes for the world (" .. #zones .. " parts)")
    -- the dungeon set upgrade chain (Mux in Gadgetzan, Deliana, Mokvar, Anthion, Bodley) is endgame
    local upgrade = 0
    for _, z in ipairs(zones) do
        for _, q in ipairs(z.quests) do if QB.IsSetUpgradeQuest(q) or q == 8921 or q == 8977 then upgrade = upgrade + 1 end end
    end
    check(upgrade == 0, "no zone route has the dungeon set upgrade chain (" .. upgrade .. ")")
    -- every route keeps to the levels it's mostly for: nothing needing you
    -- more than 3 levels above the level 80% of its quests are at or below
    local function overs(qids)
        local top, bad = QB.RouteTop(qids), {}
        for _, q in ipairs(qids) do
            local i = QB.Quest(q)
            if top and i and (i.req or 1) > top + 3 then bad[#bad + 1] = q .. " " .. tostring(i.name) end
        end
        return bad
    end
    local zoneBad = {}
    for _, z in ipairs(zones) do for _, b in ipairs(overs(z.quests)) do zoneBad[#zoneBad + 1] = z.name .. ": " .. b end end
    check(#zoneBad == 0, "no zone route has a quest needing more than 3 levels over its range (" .. table.concat(zoneBad, "; ") .. ")")
    local dunBad = {}
    for _, r in ipairs(pf.DungeonRoutes() or {}) do
        local ids, seen = {}, {}
        for _, st in ipairs(r.steps) do if st.qid and st.act == "accept" and not seen[st.qid] then seen[st.qid] = true; ids[#ids + 1] = st.qid end end
        for _, b in ipairs(overs(ids)) do dunBad[#dunBad + 1] = r.title .. ": " .. b end
    end
    check(#dunBad == 0, "nor any dungeon route: Gnomeregan's 27-34 route drops The Mad King at 40 (" .. table.concat(dunBad, "; ") .. ")")
    local kept, out = QB.TrimHigh({ 1690, 1707, 3520, 1691, 8925 })
    check(out[8925] and #kept == 4, "a route's quest needing level 58 among 43-44s is left out")
    -- a route's walked-past reminder only for a quest you could take now
    local lvl = env.UnitLevel
    env.UnitLevel = function() return 50 end
    check(pf.CanTakeNow(8925) == false, "at level 50, Mux's level-58 quest isn't one to be reminded of")
    env.UnitLevel = function() return 60 end
    check(#QB.Prereqs(783) == 0 and pf.CanTakeNow(783) == true and (#QB.Prereqs(7) == 0 or not pf.CanTakeNow(7)), "a quest you can take is; one waiting on an earlier quest isn't")
    env.UnitLevel = lvl
    -- quests of the real data that share a target end up in one stop
    local groups = 0
    local zq = zones[1] and zones[1].quests or {}
    local _, members = QB.DoGroups(zq)
    for _, m in pairs(members) do if #m > 1 then groups = groups + 1 end end
    check(type(members) == "table", ("%s: %d shared objective stops in %d quests"):format(zones[1] and zones[1].name or "?", groups, #zq))
    for k, v in pairs(saved) do env[k] = v end
    QB.Forget()
    errorsSoFar("RUIN Quest Data")
end
