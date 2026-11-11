-- A made-up quest database for tests and screenshots: a few invented quests
-- in Hall of Thanes (zone 16919), installed as RUIN Quest Data (what Pathfinder
-- reads) and, for Codex's dungeon loot, as a database addon's tables. None of
-- the real data is used. Returns install(client, doneTable) -> undo().
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
        -- City of Dalaran (zone 16544), with stand-in names: the attunement and
        -- follow-up quests sit outside, and the database records no order between them
        [92432] = { name = "Alliance Attunement", questLevel = 33, requiredRaces = 2 ^ (HUMAN - 1), zoneOrSort = 36,
                    startedBy = { { 820 } }, finishedBy = { { 821 } }, objectivesText = { "Speak with the Image." } },
        [92457] = { name = "Dalaran Streets", questLevel = 33, requiredRaces = 2 ^ (HUMAN - 1), zoneOrSort = 16544,
                    startedBy = { { 821 } }, finishedBy = { { 821 } }, objectives = { { { 5002 } } }, objectivesText = { "Kill 8 remnants." } },
        [92458] = { name = "Dalaran Heart", questLevel = 33, requiredRaces = 2 ^ (HUMAN - 1), zoneOrSort = 16544,
                    startedBy = { { 821 } }, finishedBy = { { 821 } }, objectives = { [3] = { { 6003 } } }, objectivesText = { "Collect the mote." } },
        [92459] = { name = "Dalaran Follow-up", questLevel = 33, requiredRaces = 2 ^ (HUMAN - 1), zoneOrSort = 36,
                    startedBy = { { 821 } }, finishedBy = { { 822 } }, objectivesText = { "Deliver the mote." } },
        [96987] = { name = "Dalaran Tome", questLevel = 33, zoneOrSort = 16544, objectives = { [3] = { { 6004 } } }, objectivesText = { "Find the tome." } },
        [96984] = { name = "Horde Heart", questLevel = 33, requiredRaces = 2 ^ (ORC - 1), zoneOrSort = 16544,
                    startedBy = { { 821 } }, finishedBy = { { 821 } } },
        -- a zone (12) with a small chain, for zone routes
        [9101] = { name = "Farm Chores", questLevel = 5, zoneOrSort = 12, startedBy = { { 806 } }, finishedBy = { { 806 } },
                   objectives = { { { 5003 } } }, objectivesText = { "Shoo 6 crows." } },
        [9102] = { name = "More Farm Chores", questLevel = 6, zoneOrSort = 12, startedBy = { { 806 } }, finishedBy = { { 806 } },
                   preQuestSingle = { 9101 }, objectives = { { { 5004 } } }, objectivesText = { "Shoo 8 more crows." } },
        [9103] = { name = "Map to the Farm", questLevel = 7, zoneOrSort = 12, startedBy = { { 806 } }, finishedBy = { { 806 } },
                   preQuestSingle = { 9003 } },
        [9104] = { name = "Daily Milk", questLevel = 5, zoneOrSort = 12, startedBy = { { 806 } }, finishedBy = { { 806 } }, specialFlags = 1 },
        -- Stormwind (1519) and Warsong Gulch (3277): no zone routes for cities or battlegrounds
        [9201] = { name = "City Errand One", questLevel = 10, zoneOrSort = 1519, startedBy = { { 806 } }, finishedBy = { { 806 } } },
        [9202] = { name = "City Errand Two", questLevel = 11, zoneOrSort = 1519, startedBy = { { 806 } }, finishedBy = { { 806 } } },
        [9203] = { name = "City Errand Three", questLevel = 12, zoneOrSort = 1519, startedBy = { { 806 } }, finishedBy = { { 806 } } },
        [9211] = { name = "Gulch Marks One", questLevel = 20, zoneOrSort = 3277, startedBy = { { 806 } }, finishedBy = { { 806 } } },
        [9212] = { name = "Gulch Marks Two", questLevel = 21, zoneOrSort = 3277, startedBy = { { 806 } }, finishedBy = { { 806 } } },
        [9213] = { name = "Gulch Marks Three", questLevel = 22, zoneOrSort = 3277, startedBy = { { 806 } }, finishedBy = { { 806 } } },
        [9100] = { name = "Somewhere Else", questLevel = 12, zoneOrSort = 12, startedBy = { { 801 } }, finishedBy = { { 801 } } },
    }
    local npcs = {
        [801] = { name = "Afadra Lightfoot", spawns = { [1537] = { { 40, 50 } } } },
        [802] = { name = "Earthseer Holm", spawns = { [1] = { { 30, 40 } } } },
        [803] = { name = "King of the Mountain", spawns = { [1537] = { { 39, 56 } } } },
        [804] = { name = "Dark Iron Lookout", spawns = { [1] = { { 70, 50 } } } },
        [820] = { name = "Emissary", spawns = { [267] = { { 48, 60 } } } },
        [821] = { name = "Image of the Archmage", spawns = { [36] = { { 68, 45 } } } },
        [822] = { name = "Citadel Archmage", spawns = { [36] = { { 14, 60 } } } },
        [806] = { name = "Farmer Dale", spawns = { [12] = { { 40, 60 } } } },
        [805] = { name = "Ghostly Attendant", spawns = { [16919] = { { 50, 50 } } } },
        -- Hall of Thanes loot: a journal boss, a rare, a trash mob, and a mob elsewhere
        [811] = { name = "Durgen Dirgehammer", spawns = { [16919] = { { 60, 60 } } }, rank = 1, minLevel = 18 },
        [812] = { name = "Old Rustjaw", spawns = { [16919] = { { 20, 20 } } }, rank = 4, minLevel = 17 },
        [813] = { name = "Thane's Guard", spawns = { [16919] = { { 30, 30 } } }, rank = 1, minLevel = 16 },
        [814] = { name = "Kobold Digger", spawns = { [1] = { { 40, 40 } } }, rank = 0, minLevel = 8 },
    }
    local items = { [7001] = { name = "Torn Map", npcDrops = { 804 } },
        [8001] = { name = "Direhammer Leggings", npcDrops = { 811 }, class = 4, itemLevel = 20 },
        [8002] = { name = "Durgen's Crescent Axe", npcDrops = { 811 }, class = 2, itemLevel = 21 },
        [8003] = { name = "Durgen Dirgehammer's Head", npcDrops = { 811 }, class = 12, itemLevel = 1 },
        [8004] = { name = "Rustjaw Fang", npcDrops = { 812 }, class = 2, itemLevel = 19 },
        [8005] = { name = "Thane Guard Bracers", npcDrops = { 813 }, class = 4, itemLevel = 18 },
        [8006] = { name = "Lesser Healing Potion", npcDrops = { 813, 814, 804 }, class = 0, itemLevel = 13 },   -- not gear: left out
        [8007] = { name = "Kobold Mining Mallet", npcDrops = { 813, 814, 804 }, class = 2, itemLevel = 12 },    -- mostly outside: a world drop
    }
    local function E(t)
        return { Exists = function(id) return t[id] ~= nil end, Get = function(id, f) local r = t[id]; return r and r[f] end,
                 GetAllIds = function(map)
                     local m, l = {}, {}
                     for id in pairs(t) do m[id] = true; l[#l + 1] = id end
                     table.sort(l)
                     return map and m or l
                 end }
    end
    local Q = E(quests)
    local FIELDS = {
        Q = { "name", "startedBy", "finishedBy", "requiredLevel", "questLevel", "requiredRaces", "requiredClasses", "objectivesText", "triggerEnd",
              "objectives", "sourceItemId", "preQuestGroup", "preQuestSingle", "childQuests", "inGroupWith", "exclusiveTo", "zoneOrSort",
              "requiredSkill", "requiredMinRep", "requiredMaxRep", "requiredSourceItems", "nextQuestInChain", "questFlags", "specialFlags",
              "parentQuest", "reputationReward", "breadcrumbForQuestId", "breadcrumbs", "extraObjectives", "requiredSpell",
              "requiredSpecialization", "requiredMaxLevel", "availableUntilCompleted", "availableStartingWith", "requiredRanks", "disabledByQuest" },
        N = { "name", "minLevel", "maxLevel", "spawns", "zoneID", "questStarts", "questEnds", "friendlyToFaction", "subName" },
        O = { "name", "spawns", "zoneID", "questStarts", "questEnds" },
        I = { "name", "npcDrops", "objectDrops", "itemDrops", "startQuest", "vendors" },
    }
    local function rows(t, names)
        local out = {}
        for id, rec in pairs(t) do
            local r = {}
            for i, f in ipairs(names) do r[i] = rec[f] end
            if rec.minLevel then r[2] = rec.minLevel end
            out[id] = r
        end
        return out
    end
    local savedData = c.env.RUIN_QuestData
    c.env.RUIN_QuestData = { fields = FIELDS, q = rows(quests, FIELDS.Q), n = rows(npcs, FIELDS.N), o = {}, i = rows(items, FIELDS.I),
                             z = { areaToMap = { [1537] = 1455, [1] = 1426 }, mapToArea = { [1455] = 1537, [1426] = 1 } } }
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
        c.env.RUIN_QuestData = savedData
        c.env.C_QuestLog = real
        c.mns.RUIN_Pathfinder.QB.Forget()
        PF:ForgetDungeonQuests()
    end
end
