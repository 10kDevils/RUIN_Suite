-- A made-up QuestieDB (contract 4) for tests and screenshots: a few invented
-- quests in Hall of Thanes (zone 16919). None of Questie's data is used.
-- Returns install(client, doneTable) -> undo().
local HUMAN, ORC = 1, 2
return function(c, done)
    local quests = {
        [9001] = { name = "Restless Spirits", questLevel = 15, requiredLevel = 10, requiredRaces = 2 ^ (HUMAN - 1) + 4, zoneOrSort = 16919,
                   startedBy = { { 801 } }, finishedBy = { { 801 } }, objectives = { { { 5001 } } }, objectivesText = { "Kill 10 restless spirits." } },
        [9002] = { name = "Old Halls Incursion", questLevel = 16, requiredLevel = 9, requiredRaces = 2 ^ (HUMAN - 1), zoneOrSort = 16919,
                   startedBy = { { 802 } }, finishedBy = { { 803 } }, preQuestSingle = { 9003 }, objectives = { [3] = { { 6001 } } },
                   objectivesText = { "Claim the head of the last boss." } },
        [9003] = { name = "A Torn Map", questLevel = 15, requiredLevel = 9, zoneOrSort = 1, startedBy = { [3] = { 7001 } },
                   finishedBy = { { 802 } }, objectivesText = { "Deliver the torn map to the Earthseer." } },
        [9004] = { name = "For the Horde Only", questLevel = 15, requiredRaces = 2 ^ (ORC - 1), zoneOrSort = 16919,
                   startedBy = { { 801 } }, finishedBy = { { 801 } } },
        [9005] = { name = "Ghostly Errand", questLevel = 15, requiredLevel = 10, zoneOrSort = 16919, startedBy = { { 805 } },
                   finishedBy = { { 805 } }, objectives = { [3] = { { 6002 } } }, objectivesText = { "Collect 8 heirlooms." } },
        [9007] = { name = "Mage Business", questLevel = 15, requiredClasses = 2 ^ (8 - 1), zoneOrSort = 16919,
                   startedBy = { { 801 } }, finishedBy = { { 801 } } },
        [96395] = { name = "An Old Grudge", questLevel = 15, objectivesText = { "Put the spirit to rest." } },   -- listed outside the zone, no giver
        [9100] = { name = "Somewhere Else", questLevel = 12, zoneOrSort = 12, startedBy = { { 801 } }, finishedBy = { { 801 } } },
    }
    local npcs = {
        [801] = { name = "Afadra Lightfoot", spawns = { [1537] = { { 40, 50 } } } },
        [802] = { name = "Earthseer Holm", spawns = { [1] = { { 30, 40 } } } },
        [803] = { name = "King of the Mountain", spawns = { [1537] = { { 39, 56 } } } },
        [804] = { name = "Dark Iron Lookout", spawns = { [1] = { { 70, 50 } } } },
        [805] = { name = "Ghostly Attendant", spawns = { [16919] = { { 50, 50 } } } },
    }
    local items = { [7001] = { name = "Torn Map", npcDrops = { 804 } } }
    local function E(t) return { Exists = function(id) return t[id] ~= nil end, Get = function(id, f) local r = t[id]; return r and r[f] end } end
    local Q = E(quests)
    Q.GetAllIds = function() local m = {}; for id in pairs(quests) do m[id] = true end; return m end
    c.env.LibQuestieDB = { RequireContract = function(v) return v == 4 end, Quest = Q, Npc = E(npcs), Object = E({}), Item = E(items),
        Support = { Get = function(name) return name == "ZoneDB" and { private = { areaIdToUiMapId = { [1537] = 1455, [1] = 1426 },
                                                                                       uiMapIdToAreaId = { [1455] = 1537, [1426] = 1 } } } or nil end } }
    c.env.UnitRace = function() return "Human", "Human", HUMAN end
    c.env.UnitClass = function() return "Warrior", "WARRIOR", 1 end
    c.env.UnitLevel = function() return 15 end
    local real = c.env.C_QuestLog
    c.env.C_QuestLog = setmetatable({ IsQuestFlaggedCompleted = function(id) return done[id] or false end }, { __index = real })
    local PF = c.env.RUIN_API:GetModule("Pathfinder")
    c.mns.RUIN_Pathfinder.QB.Forget()
    PF:ForgetDungeonQuests()
    return function()
        c.env.LibQuestieDB = nil
        c.env.C_QuestLog = real
        c.mns.RUIN_Pathfinder.QB.Forget()
        PF:ForgetDungeonQuests()
    end
end
