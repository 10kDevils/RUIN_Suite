-- RUIN Quest Data: the bundled quest database, read by Pathfinder when the
-- standalone QuestieDB addon isn't installed.
local alice, check, errorsSoFar = T.alice, T.check, T.errorsSoFar
local here = T.here or "."

print("Pathfinder: RUIN Quest Data")
do
    local env = alice.env
    local pf = env.RUIN_API:GetModule("Pathfinder")
    local QB = pf.QB
    local saved = { LibQuestieDB = env.LibQuestieDB, QuestieLoader = env.QuestieLoader, RUIN_QuestData = env.RUIN_QuestData }
    env.LibQuestieDB, env.QuestieLoader, env.RUIN_QuestData = nil, nil, nil
    local t0 = os.clock()
    for _, f in ipairs({ "Data.lua", "Horde.lua" }) do
        local chunk = assert(loadfile(here .. "/../RUIN_QuestData/" .. f))
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
    check(QB.Has() and QB.Source() == "RUIN Quest Data", "Pathfinder reads it when nothing else is installed (" .. tostring(QB.Source()) .. ")")
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
    -- quests of the real data that share a target end up in one stop
    local groups = 0
    local zq = zones[1] and zones[1].quests or {}
    local _, members = QB.DoGroups(zq)
    for _, m in pairs(members) do if #m > 1 then groups = groups + 1 end end
    check(type(members) == "table", ("%s: %d shared objective stops in %d quests"):format(zones[1] and zones[1].name or "?", groups, #zq))
    -- the standalone QuestieDB, when installed, still comes first
    env.LibQuestieDB = { RequireContract = function() return true end, Quest = { Get = function() end, Exists = function() return false end },
                         Support = { Get = function() end } }
    QB.Forget()
    check(QB.Source() == "QuestieDB", "an installed QuestieDB is read first")
    for k, v in pairs(saved) do env[k] = v end
    QB.Forget()
    errorsSoFar("RUIN Quest Data")
end
