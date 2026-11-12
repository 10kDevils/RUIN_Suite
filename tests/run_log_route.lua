-- Pathfinder: a route through the quests in your log, and the tab order.
local alice, check, errorsSoFar = T.alice, T.check, T.errorsSoFar

print("Pathfinder: quests in your log as a route")
do
    local env = alice.env
    local pf = env.RUIN_API:GetModule("Pathfinder")
    local QB = pf.QB
    local saved = {}
    for _, k in ipairs({ "Has", "Spots", "Spot", "Log", "Done", "Quest", "Prereqs", "DoText", "AcceptText", "TurninText", "InLog" }) do saved[k] = QB[k] end
    local Map = env.RUIN_API.Map
    local realPos = Map.PlayerPos
    Map.PlayerPos = function() return 1429, 0.10, 0.10 end
    local function at(x, y) return { { map = 1429, x = x, y = y } } end
    local world = {
        [601] = { name = "Far Away", obj = at(0.90, 0.90), fin = at(0.92, 0.92) },
        [602] = { name = "Close By", obj = at(0.15, 0.15), fin = at(0.20, 0.20) },
        [603] = { name = "Ready One", obj = at(0.50, 0.50), fin = at(0.12, 0.12) },
    }
    local log = { { id = 601, title = "Far Away" }, { id = 602, title = "Close By" }, { id = 603, title = "Ready One", ready = true },
                  { id = 699, title = "Mystery Quest" } }
    QB.Has = function() return true end
    QB.Log = function() return log end
    QB.Spots = function(q, which) local w = world[q]; return w and (which == "finish" and w.fin or which == "objective" and w.obj) or {} end
    QB.Spot = function(q, which) return QB.Spots(q, which)[1] end
    QB.Done = function() return false end
    QB.InLog = function(q) for _, e in ipairs(log) do if e.id == q then return true, e.ready end end return false, false end
    QB.Quest = function(q) local w = world[q]; return w and { id = q, name = w.name, level = 10 } end
    QB.Prereqs = function() return {} end
    QB.DoText = function(q) return world[q] and "Do " .. world[q].name or "" end
    QB.AcceptText = function() return "" end
    QB.TurninText = function(q) return "Hand in " .. tostring(q) end

    check(QB.GroupLabel({ "A", "B" }) == "A + B" and QB.GroupLabel({ "A", "B", "C" }) == "A + 2 more", "a stop for several quests: the first one's name and how many more")
    check(QB.JoinTexts({ "Bring it to Tinkmaster.", "Kill 8 boars" }) == "Bring it to Tinkmaster; Kill 8 boars", "their objectives joined without a stray period")
    local steps, yards, n = QB.LogRoute()
    check(steps and n == 4, "all four quests in the log are in it (" .. tostring(n) .. ")")
    local accepts, order = 0, {}
    for _, s in ipairs(steps or {}) do
        if s.act == "accept" then accepts = accepts + 1 end
        order[#order + 1] = s.act .. ":" .. tostring(s.qid)
    end
    local txt = table.concat(order, " ")
    check(accepts == 0, "no pick-ups: you already have them (" .. txt .. ")")
    check(not txt:find("complete:603"), "a quest that's ready goes straight to its hand-in")
    check(txt:find("complete:602") and txt:find("complete:602") < txt:find("complete:601"), "nearer objectives first (" .. txt .. ")")
    check(txt:find("turnin:603") < txt:find("turnin:601"), "the ready quest's nearby hand-in before the far one")
    check(steps and steps[#steps].qid == 699 and steps[#steps].text:find("Not in RUIN Quest Data"), "a quest the database doesn't know is at the end")
    check(type(yards) == "number" and yards > 0, "the walk is measured (" .. tostring(yards) .. " yd)")

    -- in the Guide's picker, first, and it can be started
    local ids = pf.PickerRoutes()
    check(ids[1] == "log", "the Guide's route list starts with Quests in your log")
    local cdb = env.RUIN_PathfinderCharDB
    local savedRoute, savedStep = cdb.route, cdb.step
    pf:StartRoute("log")
    check(cdb.route == "log" and cdb.logRoute and #cdb.logRoute.steps == #steps, "starting it plans it and keeps the plan")
    local r = pf.LogRoute()
    check(r and r.steps == cdb.logRoute.steps, "while you follow it the steps stay as planned")
    -- an empty log: nothing to start
    log = {}
    check(pf.PickerRoutes()[1] ~= "log", "with an empty log it isn't offered")
    cdb.logRoute = nil
    cdb.route, cdb.step = savedRoute, savedStep or 1

    for k, v in pairs(saved) do QB[k] = v end
    Map.PlayerPos = realPos
    errorsSoFar("log route")
end

print("Pathfinder: tab order")
do
    T.openAllSubTabs(alice, "Pathfinder")
    errorsSoFar("Pathfinder tabs")
end

print("Pathfinder: In-Game Navigation switch")
do
    local env = alice.env
    local pf = env.RUIN_API:GetModule("Pathfinder")
    local cdb = env.RUIN_PathfinderCharDB
    local realSet, realGet = env.SetCVar, env.GetCVar
    local cv = { showInGameNavigation = "1" }
    env.SetCVar = function(k, v) cv[k] = tostring(v) end
    env.GetCVar = function(k) return cv[k] end
    pf.SetInGameNavigation(false)
    check(cv.showInGameNavigation == "0" and cdb.autoNav == false, "unticking it turns the game's In-Game Navigation off (nothing drawn in the world)")
    pf.SetInGameNavigation(true)
    check(cv.showInGameNavigation == "1" and cdb.autoNav == true, "ticking it turns it back on")
    local realCombat = env.InCombatLockdown
    env.InCombatLockdown = function() return true end
    pf.SetInGameNavigation(false)
    check(cv.showInGameNavigation == "1", "in combat it waits")
    env.InCombatLockdown = realCombat
    Server.fire(alice, "PLAYER_REGEN_ENABLED")
    check(cv.showInGameNavigation == "0", "and happens when combat ends")
    pf.SetInGameNavigation(true)
    env.SetCVar, env.GetCVar = realSet, realGet
    errorsSoFar("navigation switch")
end
