-- RUIN Party Dungeon Signal tests (Core 0.5.1): scoring, party channel, security.
-- Runs after run_features_*.lua and shares T.
local alice, cara, eve, check, chatHas, errorsSoFar = T.alice, T.cara, T.eve, T.check, T.chatHas, T.errorsSoFar
local Server = Server

print("Party dungeon signal: scoring")
do
    local PP = alice.ns.PartyPlan
    check(PP ~= nil, "Core has a PartyPlan module")
    check(PP.ShortName("The Deadmines") == "DM" and PP.ShortName("Wailing Caverns") == "WC", "built-in short names")
    check(PP.ShortName("Hall of Thanes") == "HT" and PP.ShortName("Ruins of Lordaeron") == "RL", "initials skip the, of and and")
    check(PP.ShortName("Temple of the Moon Lords") == "TML", "unknown dungeons fall back to initials ")
    check(PP.ShortName("") == "?", "an empty name is safe")

    -- gear is the primary decider
    check(PP.Classify("need", 0) == "N", "a gear upgrade among the next steps is a Need")
    check(PP.Classify("need", 5) == "N", "a Need stays a Need with quests")
    check(PP.Classify("could", 0) == "C", "a later gear drop alone is a Could use")
    check(PP.Classify(nil, 1) == "C" and PP.Classify(nil, 7) == "C", "any number of open quests alone is a Could use")
    check(PP.Classify("could", 1) == "N", "open quests plus a gear drop equal one Need")
    check(PP.Classify(nil, 0) == nil, "nothing there, nothing shared")

    check(PP.Weight("N") == 2 and PP.Weight("C") == 1 and PP.Weight(nil) == 0, "Need 2, Could use 1")
    local function rep(...) return { d = { ... } } end
    local rows = PP.Tally({
        a = rep({ n = "DM", k = "N", q = 0 }), b = rep({ n = "DM", k = "N", q = 2 }),
        c = rep({ n = "DM", k = "C", q = 1 }), d = rep({ n = "WC", k = "C", q = 0 }),
    })
    check(rows[1].short == "DM" and rows[1].heat == 5 and rows[1].need == 2 and rows[1].could == 1, "Heat = 2 x Need + 1 x Could use (2x2 + 1 = 5)")
    check(rows[1].tier.name == "Loud" and rows[2].tier.name == "Quiet", "5 is Loud, 1 is Quiet")
    check(PP.TierFor(0) == nil and PP.TierFor(2).name == "Quiet" and PP.TierFor(3).name == "Noticed" and PP.TierFor(7).name == "Loud" and PP.TierFor(8).name == "Full party", "tier boundaries")

    -- quests are only a final tie-breaker, at half a Could use each
    local tie = PP.Tally({
        a = rep({ n = "AAA", k = "C", q = 0 }), b = rep({ n = "ZZZ", k = "C", q = 3 }),
    })
    check(tie[1].short == "ZZZ" and tie[1].heat == tie[2].heat and tie[1].tie == 1.5, "equal heat: more open quests wins, at 0.5 each")
    check(tie[1].tier.name == tie[2].tier.name, "the quest tie-breaker never changes the tier")
end

-- a fake planner for each player
local function fakePlanner(env, spec)
    local P = { char = { class = "WARRIOR", spec = "Arms", mode = "group" }, profile = {} }
    function P.Render() end
    function P.Plan() return spec.plan end
    function P.GroupGoals() return {} end
    function P.WindowDungeons() return spec.dungeons or {} end
    function P.QuestNext(id) return nil, spec.done and spec.done[id] and "completed" or "available" end
    env.RuinousForeverPlanner = P
    return P
end
local function item(id, act) return { id = id, name = "Item " .. id, mode = "group", activity = act } end
local function step(id, act, priority) return { id = "t" .. id, kind = "group", priority = priority or 35, item = item(id, act) } end

print("Party dungeon signal: collecting the planner's signal")
do
    local PP = alice.ns.PartyPlan
    alice.ns.Planner.P = function() return alice.env.RuinousForeverPlanner end
    local P = fakePlanner(alice.env, {
        plan = { step(11, "The Deadmines", 35), step(12, "Wailing Caverns", 55), step(13, "Shadowfang Keep", 35) },
        dungeons = { { name = "The Deadmines", quests = { { id = 1 }, { id = 2 } } }, { name = "Gnomeregan", quests = { { id = 3 } } } },
        done = { [2] = true },
    })
    local out = PP.Collect(P)
    local by = {}
    for _, e in ipairs(out) do by[e.n] = e end
    check(by.DM and by.DM.k == "N" and by.DM.q == 1, "a top gear step in the Deadmines is a Need, with its 1 open quest (done quests do not count)")
    check(by.WC and by.WC.k == "C", "a future-level gear drop is only a Could use")
    check(by.GNOMER and by.GNOMER.k == "C" and by.GNOMER.q == 1, "quests alone in Gnomeregan are a Could use")
    check(#out <= PP.MAX_DUNGEONS, "a report holds at most four dungeons")
    local text = alice.ns.Serialize({ v = 1, ap = 1, d = PP.Strip(out) })
    check(#text < 200, "a full report fits one addon message (" .. #text .. " bytes)")
end

print("Party dungeon signal: five players, one channel")
do
    local PP = alice.ns.PartyPlan
    local names = { alice, cara, eve }
    local roster = {}      -- the shared party: client -> party list of others
    for _, c in ipairs(names) do
        c.partyOf = "p1"
        c.env.IsInGroup = function() return c.inGroup ~= false end
        c.env.IsInRaid = function() return c.inRaid or false end
        c.env.GetNumGroupMembers = function() return #names end
        local realName = c.env.UnitName
        c.env.UnitName = function(u)
            local i = tonumber((u or ""):match("^party(%d)$"))
            if i then
                local others = {}
                for _, o in ipairs(names) do if o ~= c then others[#others + 1] = o end end
                return others[i] and others[i].name
            end
            return realName(u)
        end
        c.ns.Planner.P = function() return c.env.RuinousForeverPlanner end
    end
    local function plan(c, spec) fakePlanner(c.env, spec) end
    plan(alice, { plan = { step(1, "The Deadmines") } })
    plan(cara, { plan = { step(2, "The Deadmines") } })
    plan(eve, { plan = { step(3, "The Deadmines", 55) }, dungeons = { { name = "The Deadmines", quests = { { id = 9 } } } } })

    for _, c in ipairs(names) do c.ns.PartyPlan:Update() end
    Server:Advance(30)
    for _, c in ipairs(names) do c.ns.PartyPlan:Update() end
    Server:Advance(30)

    local rows = alice.ns.PartyPlan.rows or {}
    check(rows[1] and rows[1].short == "DM", "everyone's strip leads with the Deadmines")
    check(rows[1] and rows[1].need == 3, "all three count (Eve's quests + a future gear drop equal a Need): need=" .. tostring(rows[1] and rows[1].need))
    check(rows[1] and rows[1].heat == 6 and rows[1].tier.name == "Loud", "heat 6 is Loud")
    local same = true
    for _, c in ipairs({ cara, eve }) do
        local r = c.ns.PartyPlan.rows and c.ns.PartyPlan.rows[1]
        if not (r and r.short == "DM" and r.heat == 6) then same = false end
    end
    check(same, "everyone sees the same heat")
    local posted = 0
    for _, c in ipairs(names) do
        for _, m in ipairs(c.sentChat or {}) do if m[2] == "PARTY" and m[1]:find("need DM", 1, true) then posted = posted + 1 end end
    end
    check(posted == 1, "exactly one player posts it to party chat (" .. posted .. ")")
    check(chatHas(alice, "Your party needs 3 of 3 need DM") or chatHas(alice, "need DM"), "a toast tells each player")

    -- security: a message from someone who is not in my group is ignored
    local before = cara.ns.PartyPlan.rows[1].heat
    cara.env.CHAT_FAKE = true
    local stranger = Server:NewClient({ name = "Stan Stranger", guid = "Player-1-00000077", guild = "Nowhere", rank = 0, modules = {} })
    stranger.partyOf = "p1"
    stranger.env.IsInGroup = function() return true end
    stranger.env.IsInRaid = function() return false end
    stranger.env.GetNumGroupMembers = function() return 2 end
    stranger.env.UnitName = function(u) return u == "party1" and "Cara Cole" or "Stan Stranger" end
    stranger.ns.Comms:Send("PARTYPLAN", { v = 1, ap = 1, d = { { n = "DM", k = "N", q = 99, i = {} }, { n = "DM", k = "N", q = 99, i = {} } } }, "PARTY", nil, 2)
    Server:Advance(5)
    check(cara.ns.PartyPlan.rows[1].heat == before, "a stranger's report (not in my group) changes nothing")

    -- raids and the off switch
    alice.inRaid = true
    check(alice.ns.PartyPlan.Roster() == nil, "no party signal in a raid")
    alice.inRaid = false
    alice.ns.db.settings.partySignal = false
    check(not alice.ns.PartyPlan:Enabled(), "one switch turns it off")
    alice.ns.PartyPlan:Command("on")
    check(alice.ns.PartyPlan:Enabled(), "/ruin party on turns it back on")
    alice.ns.PartyPlan:Command("post off")
    check(alice.ns.db.settings.partyAutoPost == false, "/ruin party post off stops the party chat post")
    alice.ns.PartyPlan:Command("post on")

    -- leaving the group clears the tally
    for _, c in ipairs(names) do c.inGroup = false; Server.fire(c, "GROUP_ROSTER_UPDATE") end
    Server:Advance(5)
    check((alice.ns.PartyPlan.rows or {})[1] == nil, "leaving the party clears the strip")
    for _, c in ipairs(names) do c.inGroup = nil; c.partyOf = nil end
    errorsSoFar("party dungeon signal")
end
