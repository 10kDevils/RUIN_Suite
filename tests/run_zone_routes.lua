-- Pathfinder 0.5.2: a route for every zone the database has quests in (split by
-- level), one list of routes for the Guide's picker and the Routes page,
-- and a Routes page checkbox that hides a route from the picker.
local alice, check, errorsSoFar = T.alice, T.check, T.errorsSoFar
local here = T.here or "."
local fakeQuestDB = dofile(here .. "/fake_questdb.lua")

print("Pathfinder: zone routes and one route list")
do
    local done = {}
    local undo = fakeQuestDB(alice, done)
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
    local city, bg = false, false
    for _, r in ipairs(zones) do
        if r.zoneArea == 1519 then city = true end
        if r.zoneArea == 3277 then bg = true end
    end
    check(not city and not bg, "cities and battlegrounds get no zone route")

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

    -- sections: Suggested for you, Levelling (the planned routes), Dungeons, Zones, Completed / out-leveled,
    -- each by level (a level 15 character)
    local heads, byHead = {}, {}
    for _, sec in ipairs(lib) do heads[#heads + 1] = sec.header; byHead[sec.header] = sec end
    check(table.concat(heads, " | ") == "Suggested for you | Levelling | Dungeons | Zones | Completed / out-leveled",
        "sections in order (" .. table.concat(heads, " | ") .. ")")
    local function sorted(list)
        for i = 2, #list do if (list[i].lo or 999) < (list[i - 1].lo or 999) then return false end end
        return true
    end
    check(sorted(byHead.Levelling.routes) and sorted(byHead.Dungeons.routes) and sorted(byHead.Zones.routes)
        and sorted(byHead["Completed / out-leveled"].routes), "each section is sorted by level")
    local sug = byHead["Suggested for you"].routes
    check(#sug >= 1 and #sug <= 3 and sug[1].startLevel <= 15 and sug[1].endLevel > 15 and not sug[1].id:find("_alt"),
        "Suggested for you: the bracket's best planned route first (" .. tostring(sug[1] and sug[1].id) .. ")")
    check(byHead.Dungeons.routes[1] and byHead.Dungeons.routes[1].dungeon == "Hall of Thanes", "dungeons: lowest level on top")
    local pastIds = {}
    for _, x in ipairs(byHead["Completed / out-leveled"].routes) do pastIds[x.id] = true end
    check(pastIds.a_01_northshire_valley and pastIds[elwynn.id], "routes 3 or more levels below you move to Completed / out-leveled")
    local inLev = false
    for _, x in ipairs(byHead.Levelling.routes) do if x.id == "a_24_duskwood" then inLev = true end end
    check(inLev, "planned routes at or above your level stay under Levelling")
    local dm
    for _, x in ipairs(byHead.Levelling.routes) do if x.id == "a_24_duskwood" then dm = x end end
    check(dm and dm.lo == 24 and dm.hi == PF:GetRoute("a_24_duskwood").endLevel, "levels come from the route's levels")

    -- sections fold: click a header and its routes go; click again and they're back
    local ui = PF.UI
    ui.tabs:Select(3)
    local function rowsOf()
        local nh, routes, zoneHead = 0, 0, nil
        for _, row in ipairs(ui.library.rows) do
            if row:IsShown() and row.e then
                if row.e.key then nh = nh + 1; if row.e.key == "Zones" then zoneHead = row end end
                if row.e.route then routes = routes + 1 end
            end
        end
        return nh, routes, zoneHead
    end
    local h1, r1, zh = rowsOf()
    check(h1 == #lib and zh and zh.band:IsShown(), "a header per section, drawn as bands (" .. h1 .. ")")
    zh:GetScript("OnMouseUp")(zh, "LeftButton")
    local h2, r2 = rowsOf()
    check(h2 == #lib and r2 == r1 - #byHead.Zones.routes, "clicking Zones folds its routes away (" .. r1 .. " -> " .. r2 .. ")")
    local _, _, zh2 = rowsOf()
    zh2:GetScript("OnMouseUp")(zh2, "LeftButton")
    local _, r3 = rowsOf()
    check(r3 == r1, "and clicking again brings them back")

    -- the Cozy Sleeping Bag: your faction's version, under Zones
    local bagA, bagH = false, false
    for _, sec in ipairs(lib) do for _, x in ipairs(sec.routes) do
        if x.id == "cozy_sleeping_bag_alliance" then bagA = sec.header end
        if x.id == "cozy_sleeping_bag_horde" then bagH = true end
    end end
    check(bagA == "Zones" and not bagH, "an Alliance character gets the Alliance Cozy Sleeping Bag route, not the Horde one")
    local bag = PF:GetRoute("cozy_sleeping_bag_alliance")
    check(bag and bag.steps[#bag.steps].qid == 79976 and bag.steps[#bag.steps].act == "turnin", "it ends handing in This Must Be The Place for the bag")

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
