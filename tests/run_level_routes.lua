-- Pathfinder's planned levelling routes: Suggested for you, Start next, the
-- session time budget, class quests, Find group for group quests, and
-- following your party leader's step. Runs inside run_features.lua.
local alice, cara, check, errorsSoFar = T.alice, T.cara, T.check, T.errorsSoFar

print("Pathfinder: planned levelling routes")
do
    local env = alice.env
    local R = env.RUIN_API
    local PF = R:GetModule("Pathfinder")
    local P = alice.mns.RUIN_Pathfinder
    local Plan = P.Plan
    local db = env.RUIN_PathfinderCharDB
    check(Plan and Plan.Suggested, "Pathfinder has the planner's extras")

    -- Suggested for you
    local saved = { UnitLevel = env.UnitLevel, UnitRace = env.UnitRace }
    env.UnitLevel = function() return 15 end
    local s15 = Plan.Suggested()
    check(#s15 >= 1 and #s15 <= 3 and s15[1].id == "a_12_darkshore", "at 15 the 12-18 bracket's best route comes first (" .. tostring(s15[1] and s15[1].id) .. ")")
    env.UnitLevel = function() return 1 end
    env.UnitRace = function() return "Dwarf", "Dwarf", 3 end
    local ids1 = {}
    for _, x in ipairs(Plan.Suggested()) do ids1[#ids1 + 1] = x.id end
    check(Plan.Suggested()[1].id == "a_01_coldridge_valley", "at level 1 a dwarf is sent to Coldridge Valley first")
    env.UnitRace = function() return "Human", "Human", 1 end
    check(Plan.Suggested()[1].id == "a_01_northshire_valley", "and a human to Northshire Valley")
    env.UnitLevel = function() return 60 end
    check(#Plan.Suggested() >= 1, "at 60 the last routes still show")
    env.UnitLevel, env.UnitRace = saved.UnitLevel, saved.UnitRace

    -- Start next
    local r = PF:GetRoute("a_12_darkshore")
    local nexts = Plan.Next(r)
    check(#nexts >= 1 and #nexts <= 3 and nexts[1].startLevel >= 17, "a route names the routes to start after it (" .. tostring(nexts[1] and nexts[1].id) .. ")")
    check(r.steps[#r.steps].next and r.steps[#r.steps].text:find("Start next", 1, true), "its last step says so")

    -- session budget
    local dusk = PF:GetRoute("a_24_duskwood")
    local stop = Plan.StopAt(dusk, 1, 60)
    check(stop and dusk.steps[stop.step].t <= 60 and (dusk.steps[stop.step + 1].t or 999) > 60 and stop.level >= 24,
        "an hour from the start stops at the last step within the hour (step " .. tostring(stop and stop.step) .. ")")
    check(Plan.StopAt(dusk, 1, 0) == nil and Plan.StopAt({ steps = {} }, 1, 60) == nil, "no budget, or no times, means no stop")
    check(Plan.MinutesLeft(dusk, 1) == dusk.minutes - dusk.steps[1].t and Plan.MinutesLeft(dusk, #dusk.steps) == 0,
        "minutes left counts from your step to the route's end")
    PF:StartRoute("a_24_duskwood")
    Plan.SetBudget(30)
    local bs = Plan.BudgetStop()
    local from = db.budgetFrom or db.step
    check(bs and bs.step >= from and dusk.steps[bs.step].t - dusk.steps[from].t <= 30, "a 30-minute session from where you are")
    local toasts = #(alice.chat or {})
    db.step = bs.step + 1
    Plan.CheckBudget()
    check(db.budgetToldAt == bs.step, "passing the stop step tells you once")
    Plan.CheckBudget()
    check(db.budgetToldAt == bs.step, "and only once")
    check(Plan.BudgetLabel(0) == "Session: whole route" and Plan.BudgetLabel(90) == "Session: 1.5 h" and Plan.BudgetLabel(30) == "Session: 30 min",
        "session labels read naturally")
    Plan.SetBudget(0)
    check(Plan.BudgetStop() == nil, "Whole route turns the budget off")

    -- class quests (a made-up database: a warrior quest at 10, a mage one, one already done)
    local QB = P.QB
    local realQB = { Has = QB.Has, Field = QB.Field, ForMe = QB.ForMe, Done = QB.Done, InLog = QB.InLog, Prereqs = QB.Prereqs, Quest = QB.Quest }
    local realData, realClass, realLevel = env.RUIN_QuestData, env.UnitClass, env.UnitLevel
    local F = { [5001] = { requiredClasses = 1, requiredLevel = 10, name = "Bartleby the Drunk" },
                [5002] = { requiredClasses = 128, requiredLevel = 10, name = "Mage business" },
                [5003] = { requiredClasses = 1, requiredLevel = 4, name = "Old warrior quest" } }
    env.RUIN_QuestData = { q = { [5001] = {}, [5002] = {}, [5003] = {} } }
    QB.Has = function() return true end
    QB.Field = function(q, f) return F[q] and F[q][f] end
    QB.ForMe = function() return true end
    QB.Done = function(q) return q == 5003 end
    QB.InLog = function() return false end
    QB.Prereqs = function() return {} end
    QB.Quest = function(q) return F[q] and { name = F[q].name, starts = { "Lyria Du Lac" } } end
    env.UnitClass = function() return "Warrior", "WARRIOR", 1 end
    env.UnitLevel = function() return 9 end
    Plan.ForgetClassQuests()
    local cq = Plan.NextClassQuest()
    check(cq and cq.qid == 5001 and cq.giver == "Lyria Du Lac", "the next class quest is your class's, not done, near your level")
    for k, v in pairs(realQB) do QB[k] = v end
    env.RUIN_QuestData, env.UnitClass, env.UnitLevel = realData, realClass, realLevel
    Plan.ForgetClassQuests()

    -- group quests: Find group lists you on Finder's board
    local step = dusk.steps[db.step] or dusk.steps[1]
    local qid
    for i = db.step, #dusk.steps do if dusk.steps[i].qid then db.step = i; qid = dusk.steps[i].qid; break end end
    local realTag = env.C_QuestLog.GetQuestTagInfo
    env.C_QuestLog.GetQuestTagInfo = function(q) return q == qid and { tagName = "Elite" } or nil end
    local gq, gname, tag = Plan.GroupStep()
    check(gq == qid and tag == "Elite", "an Elite quest on your step is a group quest")
    local ok = Plan.FindGroup()
    local fdb = env.RUIN_FinderCharDB
    check(ok and fdb.activity == "Questing" and fdb.listing == "Group", "Find group lists you on RUIN Finder's board for it")
    env.C_QuestLog.GetQuestTagInfo = function() return nil end
    check(Plan.GroupStep() == nil, "a solo quest isn't")
    env.C_QuestLog.GetQuestTagInfo = realTag

    -- party sync: in Cara's party on the same route, Alice follows her step
    local realGroup = { IsInGroup = env.IsInGroup, UnitInParty = env.UnitInParty, UnitIsGroupLeader = env.UnitIsGroupLeader }
    env.IsInGroup = function() return true end
    env.UnitInParty = function(n) return n == "Cara Cole" end
    env.UnitIsGroupLeader = function(n) return n == "Cara Cole" end
    db.partySync = true
    Plan.OnPeerStep({ g = "Player-1-00000002", gu = "Briar Fang", r = "a_24_duskwood", s = 5 }, "Cara Cole")
    check(db.follow == "Player-1-00000002", "in a party on the same route, you follow the leader's step")
    env.IsInGroup = function() return false end
    Server.fire(alice, "GROUP_ROSTER_UPDATE")
    check(db.follow == nil, "leaving the party stops it")
    db.partySync = false
    env.IsInGroup = function() return true end
    Plan.OnPeerStep({ g = "Player-1-00000002", gu = "Briar Fang", r = "a_24_duskwood", s = 5 }, "Cara Cole")
    check(db.follow == nil, "with Follow my party leader off, nothing follows")
    db.partySync = true
    for k, v in pairs(realGroup) do env[k] = v end

    -- the Guide with a planned route open, on its last step (Start next shows)
    db.step = #dusk.steps
    R:OpenTab("Pathfinder")
    T.openAllSubTabs(alice, "Pathfinder")
    PF:ClearRoute()
    errorsSoFar("planned routes")
end
