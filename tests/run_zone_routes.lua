-- Pathfinder 0.5.2: a route for every zone Questie has quests in (split by
-- level), one list of routes for the Guide's picker and the Routes page,
-- and a Routes page checkbox that hides a route from the picker.
local alice, check, errorsSoFar = T.alice, T.check, T.errorsSoFar
local here = T.here or "."
local fakeQuestieDB = dofile(here .. "/fake_questiedb.lua")

print("Pathfinder: zone routes and one route list")
do
    local done = {}
    local undo = fakeQuestieDB(alice, done)
    local env = alice.env
    local realArea = env.C_Map.GetAreaInfo
    env.C_Map.GetAreaInfo = function(a) return ({ [12] = "Elwynn Forest", [36] = "Alterac Mountains" })[a] end
    local PF = env.RUIN_API:GetModule("Pathfinder")
    PF:ForgetDungeonQuests()

    local zones = PF.ZoneRoutes()
    local elwynn
    for _, r in ipairs(zones) do if r.zoneName == "Elwynn Forest" then elwynn = r end end
    check(elwynn and elwynn.title == "Elwynn Forest 5-12" and elwynn.quests == 4, "a zone with quests gets a route, titled by its levels (" .. tostring(elwynn and elwynn.title) .. ")")
    for _, r in ipairs(zones) do check(r.zoneName ~= "Zone 16919", "dungeon zones are left to the dungeon routes") end

    -- the steps: the quest from elsewhere first, then rounds
    local full = PF:GetRoute(elwynn.id)
    local seq, pos = {}, {}
    for i, s in ipairs(full and full.steps or {}) do seq[i] = s.act .. ":" .. (s.quest or ""); pos[seq[i]] = pos[seq[i]] or i end
    local function before(a, b) return pos[a] and pos[b] and pos[a] < pos[b] end
    check(seq[1] == "accept:A Torn Map", "a quest from another zone that unlocks one comes first (" .. tostring(seq[1]) .. ")")
    check(before("turnin:Farm Chores", "accept:More Farm Chores"), "a follow-up waits for the round after its quest is handed in")
    check(not pos["accept:Daily Milk"], "repeatable quests are left out")
    check(pos["complete:Farm Chores"] and not pos["complete:Map to the Farm"], "quests with something to do get a do step")

    -- one list: the picker has every route the Routes page has
    env.RUIN_API:OpenTab("Pathfinder")
    T.openAllSubTabs(alice, "Pathfinder")
    local lib, libIds = PF.RouteLibrary(), {}
    for _, sec in ipairs(lib) do for _, x in ipairs(sec.routes) do libIds[#libIds + 1] = x.id end end
    local pick = PF.PickerRoutes()
    check(#pick == #libIds, "the Guide's picker lists every route on the Routes page (" .. #pick .. " of " .. #libIds .. ")")
    local hasZone, hasDungeon = false, false
    for _, id in ipairs(pick) do
        if id == elwynn.id then hasZone = true end
        if id:sub(1, 3) == "dq:" then hasDungeon = true end
    end
    check(hasZone and hasDungeon, "including zone and dungeon routes")

    -- sections: Dungeons, Zones, Completed / out-leveled, each by level (a level 15 character)
    local heads = {}
    for _, sec in ipairs(lib) do heads[#heads + 1] = sec.header end
    check(table.concat(heads, " | ") == "Dungeons | Zones | Completed / out-leveled", "sections in order (" .. table.concat(heads, " | ") .. ")")
    local function sorted(list)
        for i = 2, #list do if (list[i].lo or 999) < (list[i - 1].lo or 999) then return false end end
        return true
    end
    check(sorted(lib[1].routes) and sorted(lib[2].routes) and sorted(lib[3].routes), "each section is sorted by level")
    check(lib[1].routes[1] and lib[1].routes[1].dungeon == "Hall of Thanes", "dungeons first, lowest level on top")
    local pastIds = {}
    for _, x in ipairs(lib[3].routes) do pastIds[x.id] = true end
    check(pastIds.elwynn_1_10 and pastIds[elwynn.id], "routes 3 or more levels below you move to Completed / out-leveled")
    local inZones = false
    for _, x in ipairs(lib[2].routes) do if x.id == "wetlands_20_30" then inZones = true end end
    check(inZones, "routes at or above your level stay under Zones")
    local dm
    for _, x in ipairs(lib[2].routes) do if x.id == "duskwood_20_28" then dm = x end end
    check(dm and dm.lo == 20 and dm.hi == 28, "levels come from the title when a route has none")

    -- hiding one
    PF:SetRouteHidden(elwynn.id, true)
    local still = false
    for _, id in ipairs(PF.PickerRoutes()) do if id == elwynn.id then still = true end end
    check(not still and #PF.PickerRoutes() == #libIds - 1, "an unticked route leaves the picker")
    local onPage = false
    for _, sec in ipairs(PF.RouteLibrary()) do for _, x in ipairs(sec.routes) do if x.id == elwynn.id then onPage = true end end end
    check(onPage, "but stays on the Routes page")
    PF:SetRouteHidden(elwynn.id, false)
    check(#PF.PickerRoutes() == #libIds, "ticking it brings it back")

    env.C_Map.GetAreaInfo = realArea
    undo()
    errorsSoFar("zone routes")
end
