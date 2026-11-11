-- A stand-in for RUIN Quest Data, built from plain tables (none of the real data):
--   data = { quests = { [id] = { name, level, req, starts = { npc }, ends = { npc }, obj = { {Type, Id, Text} }, text, zone } },
--            npcs = { [id] = { name, spawns = { [areaId] = { { x, y } } } } }, area = { [areaId] = uiMapId }, done = { [id] = true } }
local FIELDS = {
    Q = { "name", "startedBy", "finishedBy", "requiredLevel", "questLevel", "requiredRaces", "requiredClasses", "objectivesText", "triggerEnd",
          "objectives", "sourceItemId", "preQuestGroup", "preQuestSingle", "childQuests", "inGroupWith", "exclusiveTo", "zoneOrSort" },
    N = { "name", "minLevel", "maxLevel", "spawns", "zoneID" },
    O = { "name", "spawns", "zoneID" },
    I = { "name", "npcDrops", "objectDrops" },
}
local GROUP = { monster = 1, object = 2, item = 3 }
return function(c, data)
    local q = {}
    for id, r in pairs(data.quests) do
        local objectives = {}
        for _, o in ipairs(r.obj or {}) do
            local g = GROUP[o.Type] or 1
            objectives[g] = objectives[g] or {}
            objectives[g][#objectives[g] + 1] = { o.Id, o.Text }
        end
        q[id] = { r.name, { r.starts }, { r.ends }, r.req, r.level, nil, nil, r.text and { r.text } or nil, nil, objectives, nil, nil, nil, nil, nil, nil, r.zone }
    end
    local n = {}
    for id, r in pairs(data.npcs or {}) do n[id] = { r.name, nil, nil, r.spawns } end
    local toMap, toArea = {}, {}
    for a, m in pairs(data.area or {}) do toMap[a] = m; toArea[m] = a end
    c.env.RUIN_QuestData = { fields = FIELDS, q = q, n = n, o = {}, i = {}, z = { areaToMap = toMap, mapToArea = toArea } }
    local real = c.env.C_QuestLog
    if data.done then
        c.env.C_QuestLog = setmetatable({ IsQuestFlaggedCompleted = function(id) return data.done[id] or false end }, { __index = real })
    end
    c.mns.RUIN_Pathfinder.QB.Forget()
end
