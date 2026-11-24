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
    check(#s15 >= 1 and #s15 <= 3 and s15[1].startLevel <= 15 and not s15[1].id:find("_alt"), "at 15 the 12-18 bracket's best route comes first (" .. tostring(s15[1] and s15[1].id) .. ")")
    env.UnitLevel = function() return 1 end
    env.UnitRace = function() return "Dwarf", "Dwarf", 3 end
    local ids1 = {}
    for _, x in ipairs(Plan.Suggested()) do ids1[#ids1 + 1] = x.id end
    check(Plan.Suggested()[1].id == "a_01_coldridge_valley", "at level 1 a dwarf is sent to Coldridge Valley first")
    env.UnitRace = function() return "Human", "Human", 1 end
    check(Plan.Suggested()[1].id == "a_01_northshire_valley", "and a human to Northshire Valley")
    -- the low levels stay at home: your race's own zone next, and no other race's
    env.UnitLevel = function() return 8 end
    local s8, other = Plan.Suggested(), false
    for _, x in ipairs(s8) do if x.id == "a_06_dun_morogh" or x.id == "a_06_teldrassil" then other = true end end
    check(s8[1] and s8[1].id == "a_06_elwynn_forest" and not other, "at 8 a human is sent on in Elwynn Forest, not another race's zone")
    env.UnitLevel = function() return 60 end
    check(#Plan.Suggested() >= 1, "at 60 the last routes still show")
    -- routes planned to follow one route are suggested only after that route
    local function has(lvl, id)
        env.UnitLevel = function() return lvl end
        for _, x in ipairs(Plan.Suggested()) do if x.id == id then return true end end
        return false
    end
    local keepRoute, keepPrev = db.route, db.prevRoute
    db.route, db.prevRoute = nil, nil
    local kid
    env.UnitRace = function() return "Human", "Human", 1 end
    for _, x in ipairs(P.Routes) do if x.follows and x.follows ~= "a_06_elwynn_forest" then kid = x; break end end
    check(kid and not has(kid.startLevel + 1, kid.id), "a follow-on route isn't suggested to someone who didn't play its route")
    db.prevRoute = kid and kid.follows
    check(kid and has(kid.startLevel + 1, kid.id), "it is after you played that route")
    -- the move from home: with no route played, your own home's next route comes first
    db.prevRoute = nil
    env.UnitRace = function() return "NightElf", "NightElf", 4 end
    env.UnitLevel = function() return 12 end
    local s12 = Plan.Suggested()
    check(s12[1] and s12[1].follows == "a_06_teldrassil", "at 12 a night elf is sent on from Teldrassil (" .. tostring(s12[1] and s12[1].id) .. ")")
    local tel = PF:GetRoute("a_06_teldrassil")
    check(tel.steps[#tel.steps].text:find("move on to", 1, true), "when home runs out of quests its last step says where to move on to")
    db.route, db.prevRoute = keepRoute, keepPrev
    env.UnitLevel, env.UnitRace = saved.UnitLevel, saved.UnitRace

    -- each starting route goes on at home, and keeps to home
    for start, home in pairs({ a_01_northshire_valley = "a_06_elwynn_forest", a_01_coldridge_valley = "a_06_dun_morogh",
                               a_01_shadowglen = "a_06_teldrassil", a_01_zephras_isle = "a_06_zephras_isle" }) do
        local sr, hr = PF:GetRoute(start), PF:GetRoute(home)
        check(sr and hr and #sr.next == 1 and sr.next[1] == home and #hr.zones == 1,
            start .. " goes on to " .. home .. ", which stays in one zone")
    end

    -- Start next
    local r = PF:GetRoute(s15[1].id)
    local nexts = Plan.Next(r)
    check(#nexts >= 1 and #nexts <= 3 and nexts[1].startLevel >= 17, "a route names the routes to start after it (" .. tostring(nexts[1] and nexts[1].id) .. ")")
    check(r.steps[#r.steps].next and r.steps[#r.steps].text:find("Start next", 1, true), "its last step says so")
    -- the first route named carries on from where this route's character is: it repeats none of its quests
    local function repeatsAfter(a, b)
        local did, n = {}, 0
        for _, s in ipairs(a.steps) do if s.act == "turnin" and s.qid then did[s.qid] = true end end
        for _, s in ipairs(b.steps) do if s.act == "turnin" and s.qid and did[s.qid] then n = n + 1 end end
        return n
    end
    local worst, worstAt = 0, ""
    for _, x in ipairs(P.Routes) do
        local first = x.plan and Plan.Next(x)[1]
        if first and repeatsAfter(x, first) > worst then worst, worstAt = repeatsAfter(x, first), x.id .. " > " .. first.id end
    end
    check(worst <= 5, "no route's first Start next repeats more than a few quests it turned in (" .. worst .. " " .. worstAt .. ")")
    -- a planned route id that was renamed in an update still finds its route
    local renamed = PF:GetRoute("a_57_winterspring")
    check(renamed and renamed.id:find("^a_57_"), "a renamed route id (a_57_winterspring) finds the new route")
    check(PF:GetRoute("a_99_never_was") == nil, "an id that never was finds nothing")

    -- session budget
    local dusk = PF:GetRoute("a_24_duskwood")
    local stop = Plan.StopAt(dusk, 1, 60)
    local t0 = dusk.steps[1].t
    check(stop and dusk.steps[stop.step].t - t0 <= 60 and (dusk.steps[stop.step + 1].t or 999) - t0 > 60 and stop.level >= 24,
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
    check(Plan.BudgetLabel(0) == "Session" and Plan.BudgetLabel(90) == "1.5 h" and Plan.BudgetLabel(30) == "30 min"
        and Plan.BudgetChoice(0) == "Whole route" and Plan.BudgetChoice(120) == "Play 2 h", "session labels read naturally")
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
