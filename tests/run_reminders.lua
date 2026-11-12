-- Pathfinder: pick-up reminders.
local alice, check, chatHas, errorsSoFar = T.alice, T.check, T.chatHas, T.errorsSoFar

print("Pathfinder: pick-up reminders")
do
    local env = alice.env
    local pf = env.RUIN_API:GetModule("Pathfinder")
    local QB = pf.QB
    local saved = {}
    for _, k in ipairs({ "Has", "Spots", "Spot", "InLog", "Done", "Quest", "ZoneQuests", "AreaOf", "Prereqs" }) do saved[k] = QB[k] end
    local Map = env.RUIN_API.Map
    local realPos = Map.PlayerPos
    local px, py = 0.10, 0.10
    Map.PlayerPos = function() return 1429, px, py end
    local function at(x, y) return { { map = 1429, x = x, y = y } } end
    local world = {
        [501] = { name = "Wolves at the Gate", start = at(0.30, 0.30), obj = at(0.80, 0.80), giver = "Marshal Gryan" },
        [502] = { name = "Kobold Candles", start = at(0.60, 0.20), obj = at(0.15, 0.70), giver = "William Pestle" },
    }
    local have = {}
    QB.Has = function() return true end
    QB.Spots = function(q, which) local w = world[q]; return w and (which == "start" and w.start or which == "objective" and w.obj) or {} end
    QB.Spot = function(q, which) return QB.Spots(q, which)[1] end
    QB.InLog = function(q) return have[q] and true or false, false end
    QB.Done = function() return false end
    QB.Quest = function(q) local w = world[q]; return w and { id = q, name = w.name, starts = { w.giver }, level = 10, req = 1 } end
    QB.ZoneQuests = function() return { { id = 502, level = 10 } } end
    QB.AreaOf = function() return 12 end
    QB.Prereqs = function() return {} end
    local cdb, adb = env.RUIN_PathfinderCharDB, env.RUIN_PathfinderDB
    local savedRoute, savedStep = cdb.route, cdb.step
    adb.custom["remind-test"] = { id = "remind-test", name = "Remind test", steps = {
        { act = "accept", quest = "Wolves at the Gate", qid = 501 }, { act = "complete", quest = "Wolves at the Gate", qid = 501 } } }
    cdb.route, cdb.step = "remind-test", 1
    pf.ResetReminders()

    -- walk up to the giver, then away without taking it
    px, py = 0.30, 0.302
    pf.CheckReminders()
    check(not chatHas(alice, "walked past"), "no reminder while you're at the giver")
    px, py = 0.30, 0.45
    pf.CheckReminders()
    check(chatHas(alice, "You walked past") and chatHas(alice, "Marshal Gryan"), "walking away without it: reminded who gives it")
    local lines = 0
    for _, l in ipairs(alice.chat) do if tostring(l):find("You walked past", 1, true) then lines = lines + 1 end end
    check(lines == 1, "one line in chat, not two (" .. lines .. ")")
    local list, win = pf.Alerts()
    check(win and win:IsShown() and list[1] and list[1].msg:find("You walked past", 1, true) and list[1].qid, "and in Pathfinder's alert window, with the quest to mark on the map")
    check(win.rows[1].mark:IsShown(), "which has a Mark on map button")
    win.rows[1].mark._scripts.OnClick(win.rows[1].mark, "LeftButton")
    check(chatHas(alice, "Marked the giver on your map"), "that marks the giver")
    -- only once
    local before = #alice.chat
    px, py = 0.30, 0.302; pf.CheckReminders(); px, py = 0.30, 0.45; pf.CheckReminders()
    local again = 0
    for i = before + 1, #alice.chat do if tostring(alice.chat[i]):find("walked past", 1, true) then again = again + 1 end end
    check(again == 0, "and only once")
    -- walking into a zone quest's targets without the quest
    px, py = 0.15, 0.70
    pf.CheckReminders()
    check(chatHas(alice, "Kobold Candles") and chatHas(alice, "William Pestle"), "in a quest's target area without it: reminded where to pick it up")
    -- a quest you have: no reminder
    have[501] = true
    pf.ResetReminders()
    px, py = 0.80, 0.80
    local n0 = #alice.chat
    pf.CheckReminders()
    local said = false
    for i = n0 + 1, #alice.chat do if tostring(alice.chat[i]):find("Wolves", 1, true) then said = true end end
    check(not said, "nothing for a quest you already have")

    for k, v in pairs(saved) do QB[k] = v end
    Map.PlayerPos = realPos
    cdb.route, cdb.step = savedRoute, savedStep
    adb.custom["remind-test"] = nil
    errorsSoFar("pick-up reminders")
end
