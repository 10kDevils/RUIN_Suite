-- Dungeon quests (Pathfinder 0.5.2, Codex 0.5.3): every quest a dungeon has
-- for your race and class, the quests that unlock them, a Pathfinder route
-- through them all, and Codex's Journal section with a button for it.
-- A made-up QuestieDB (contract 4) stands in for the real one; none of
-- Questie's data is used here. Runs after the other run_features_*.lua files.
local alice, check, errorsSoFar = T.alice, T.check, T.errorsSoFar

local here = T.here or "."
local fakeQuestieDB = dofile(here .. "/fake_questiedb.lua")

print("Pathfinder and Codex: dungeon quests")
do
    local done = {}
    local undo = fakeQuestieDB(alice, done)
    local R = alice.env.RUIN_API
    local PF = R:GetModule("Pathfinder")
    local CX = R:GetModule("Codex")

    local list, why = PF:DungeonQuests("Hall of Thanes")
    local ids = {}
    for _, q in ipairs(list or {}) do ids[#ids + 1] = q.id end
    check(list and table.concat(ids, ",") == "9001,9005,96395,9002", "Hall of Thanes: the quests for a human warrior, by level (" .. table.concat(ids, ",") .. ")" .. tostring(why or ""))
    local by = {}
    for _, q in ipairs(list or {}) do by[q.id] = q end
    check(not by[9004] and not by[9007] and not by[9100], "Horde-only, other-class and other-zone quests are left out")
    check(by[96395] and by[96395].name == "An Old Grudge", "a quest filed elsewhere that belongs to the dungeon is included")
    check(by[9002] and by[9002].pre[1] == 9003 and by[9002].state == "locked", "a quest that needs another first lists it, and says it's locked")
    check(by[9005] and by[9005].inside and by[9005].endsInside and not by[9001].inside, "it knows which quests are picked up and handed in inside")
    check(by[9001].starts[1] == "Afadra Lightfoot" and by[9001].state == "available", "givers come from Questie; an open quest is available")

    -- the route
    local r = PF:DungeonRoute("Hall of Thanes")
    local function line(s) return s.act .. ":" .. (s.quest or "") end
    local seq = {}
    for _, s in ipairs(r and r.steps or {}) do seq[#seq + 1] = line(s) end
    -- Old Halls Incursion is picked up from the NPC who takes the torn map, so it comes next
    local want = { "accept:A Torn Map", "turnin:A Torn Map", "accept:Old Halls Incursion", "accept:Restless Spirits", "accept:An Old Grudge", "note:",
                   "accept:Ghostly Errand", "complete:Restless Spirits", "complete:Ghostly Errand", "complete:An Old Grudge",
                   "complete:Old Halls Incursion", "turnin:Ghostly Errand", "turnin:Restless Spirits", "turnin:Old Halls Incursion", "turnin:An Old Grudge" }
    local ok = r ~= nil
    for i, w in ipairs(want) do if seq[i] ~= w then ok = false end end
    check(ok, "route: the unlock quest first, pick-ups, the run (inside quests and objectives), then hand-ins (" .. table.concat(seq, " | ") .. ")")
    check(r and r.steps[1].text:find("Torn Map", 1, true) and r.steps[1].text:find("Dark Iron Lookout", 1, true),
        "an item-started quest says what drops the item (" .. tostring(r and r.steps[1].text) .. ")")
    local delivery = false
    for _, s in ipairs(r and r.steps or {}) do if s.act == "complete" and s.quest == "A Torn Map" then delivery = true end end
    check(not delivery, "a delivery quest has no separate Do step")
    check(r and r.id == "dq:hallofthanes" and r.title == "Hall of Thanes quests" and r.quests == 4, "the route has its own id and title")

    -- done quests: the unlock quest done makes the next one available
    done[9003] = true
    alice.mns.RUIN_Pathfinder.QB.Forget()
    PF:ForgetDungeonQuests()
    list = PF:DungeonQuests("Hall of Thanes")
    for _, q in ipairs(list) do by[q.id] = q end
    check(by[9002].state == "available", "once the quest before it is done, the quest is available")

    -- Codex: the Journal section
    local dg = CX:FindDungeon("Hall of Thanes")
    local lines = CX.JournalLines(dg, false)
    local text, action, questRow = {}, nil, nil
    for _, l in ipairs(lines) do
        text[#text + 1] = l[1]
        if l.action then action = l end
        if l.quest == 9001 and not questRow then questRow = l end
    end
    local t = table.concat(text, "\n")
    check(t:find("Quests for Alliance", 1, true) and t:find("4 quests, 0 done", 1, true), "Codex lists the dungeon's quests for your faction")
    check(t:find("Old Halls Incursion", 1, true) and t:find("First: |r", 1, true) and t:find("A Torn Map (done)", 1, true),
        "with the quests before each one, and which are done")
    check(t:find("Starts: Afadra Lightfoot", 1, true) and t:find("Hand in: Ghostly Attendant (inside)", 1, true), "where each starts and is handed in")
    check(not t:find("For the Horde Only", 1, true), "and not the other faction's")
    check(action ~= nil, "and a line that opens the quest route")
    if action then action.action() end
    check(alice.env.RUIN_PathfinderCharDB.route == "dq:hallofthanes", "which starts the route in Pathfinder (" .. tostring(alice.env.RUIN_PathfinderCharDB.route) .. ")")
    -- clicking a quest marks it on the map
    local opened
    alice.env.OpenWorldMap = function(m) opened = m end
    if questRow then
        CX.UI.detail:SetItems(lines)
        for _, row in ipairs(CX.UI.detail.rows) do
            if row.quest == 9001 and row._shown then row._scripts.OnMouseUp(row, "LeftButton"); break end
        end
    end
    local pin = R.Map:GetPins("Pathfinder")["quest"]
    check(pin and pin.map == 1455 and math.abs(pin.x - 0.40) < 0.001 and opened == 1455, "clicking a quest marks where it starts and opens the map")
    alice.env.OpenWorldMap = nil
    R.Map:RemovePin("Pathfinder", "quest")

    -- the Journal's Quest route button
    R:OpenTab("Codex")
    T.openAllSubTabs(alice, "Codex")
    local qb = CX.UI.questRoute
    qb.SetEnabled = function(self, v) self._en = v end
    T.openAllSubTabs(alice, "Codex")
    check(qb._en == true, "the Journal's Quest route button is on for a dungeon Pathfinder knows")

    -- Pathfinder's library lists the dungeon routes
    R:OpenTab("Pathfinder")
    T.openAllSubTabs(alice, "Pathfinder")
    local routes = PF.DungeonRoutes()
    check(#routes == 1 and routes[1].dungeon == "Hall of Thanes", "Pathfinder's library has a quest route for each dungeon with quests for you")

    -- without Questie: the launch data's names, and why there's no more
    undo()
    alice.env.QuestieLoader = nil
    lines = CX.JournalLines(dg, false)
    text = {}
    for _, l in ipairs(lines) do text[#text + 1] = l[1] end
    t = table.concat(text, "\n")
    check(t:find("The Restless Dead", 1, true) and t:find("Questie isn't installed", 1, true), "without Questie, the launch data's quest names and how to get more")
    alice.env.RUIN_PathfinderCharDB.route = nil
    errorsSoFar("dungeon quests")
end
