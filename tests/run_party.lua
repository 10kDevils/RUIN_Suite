-- RUIN Party Dungeon Signal tests (Core 0.5.1): scoring, the planner's signal,
-- the party channel, the strip, and security. Runs after run_features_*.lua and shares T.
local alice, cara, eve, check, chatHas, errorsSoFar = T.alice, T.cara, T.eve, T.check, T.chatHas, T.errorsSoFar
local Server = Server

print("Party dungeon signal: names and scoring")
do
    local PP = alice.ns.PartyPlan
    check(PP ~= nil, "Core has a PartyPlan module")
    check(PP.Key("The Deadmines") == "DM" and PP.Key("Deadmines") == "DM" and PP.Key("Wailing Caverns") == "WC", "built-in keys, with or without \"The\"")
    check(PP.Key("Scarlet Monastery Graveyard") == "SMGY" and PP.Key("Scarlet Monastery Cathedral") == "SMCATH", "each Scarlet Monastery wing has its own key")
    check(PP.Key("Hall of Thanes") == "HT" and PP.Key("Excavation Site: Wetlands") == "EXCAV" and PP.Key("City of Dalaran") == "DAL", "WoW Forever dungeons have keys")
    check(PP.Key("Shaper's Terrace") ~= PP.Key("Sunken Temple"), "no two dungeons share a key")
    check(PP.Key("Temple of the Moon Lords") == "TML", "an unknown dungeon falls back to initials")
    check(PP.Key("") == "?" and PP.Key("'''") == "?", "an empty or odd name is safe")
    check(PP.FullName("SMLIB") == "Scarlet Monastery Library", "keys turn back into full names for the tooltip")

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
    local tie = PP.Tally({ a = rep({ n = "AAA", k = "C", q = 0 }), b = rep({ n = "ZZZ", k = "C", q = 3 }) })
    check(tie[1].short == "ZZZ" and tie[1].heat == tie[2].heat and tie[1].tie == 1.5, "equal heat: more open quests wins, at 0.5 each")
    check(tie[1].tier.name == tie[2].tier.name, "the quest tie-breaker never changes the tier")

    -- the wire format
    local enc = PP.Encode({ { n = "DM", k = "N", q = 2, i = { 273298, 5191, 5193, 9999 } } })
    check(enc[1] == "DM:N:2:273298,5191,5193", "a dungeon is one short string, at most three items (" .. tostring(enc[1]) .. ")")
    local dec = PP.Decode({ "DM:N:2:273298,5191", "DM:N:9:1", "SFK:C:1:12345678", "BFD:C:3:", "RFC:N:1:" })
    check(#dec == 3 and dec[1].n == "DM" and dec[1].q == 2 and #dec[1].i == 2, "decoding keeps one entry per dungeon and reads at most four")
    check(dec[2] and dec[2].n == "SFK" and #dec[2].i == 0, "an item id that is too long is dropped")
    check(dec[3] and dec[3].n == "BFD" and dec[3].k == "C" and dec[3].q == 3, "and the clean entries are kept")
    check(#PP.Decode({ "dm:N:1:", "WC:X:1:", ("A"):rep(70), {} }) == 0 and #PP.Decode("DM:N:1:") == 0, "lowercase keys, unknown kinds, long strings and tables are dropped")
end

---------------------------------------------------------------------------
-- A planner that answers like Ruinous Forever Planner does (same function
-- names and shapes: Plan steps "target-<id>", DungeonQuestRows states).
local function fakePlanner(env, spec)
    local P = { char = { class = "WARRIOR", spec = "Arms", mode = spec.mode or "group" }, profile = {} }
    P.EfficiencyData = { dungeons = spec.all or spec.dungeons or {} }
    function P.Render() end
    function P.Plan() return spec.plan or {} end
    function P.GroupGoals() return {} end
    function P.WindowDungeons() return spec.dungeons or {} end
    function P.DungeonQuestRows(d)
        local rows = {}
        for _, q in ipairs(d.quests or {}) do rows[#rows + 1] = { quest = q, state = q.state or "in log" } end
        return rows
    end
    function P.QuestObservation(id) return { active = spec.active and spec.active[id] or false, completed = false } end
    function P.UpgradeEstimate(g) local p = spec.est and spec.est[g.id]; return p and { percent = p } or { text = "Upgrade estimate unavailable" } end
    env.RuinousForeverPlanner = P
    return P
end
local function item(id, act, extra)
    local it = { id = id, name = "Item " .. id, mode = "group", activity = act }
    for k, v in pairs(extra or {}) do it[k] = v end
    return it
end
local function step(id, act, priority, prefix, extra)
    return { id = (prefix or "target-") .. id, kind = prefix == "prepare-" and "preparation" or "group", priority = priority or 35, item = item(id, act, extra) }
end
local DUNGEONS = {
    { id = "the-deadmines", name = "The Deadmines", min = 17, max = 26, quests = {} },
    { id = "wailing-caverns", name = "Wailing Caverns", min = 17, max = 24, quests = {} },
    { id = "shadowfang-keep", name = "Shadowfang Keep", min = 22, max = 30, quests = {} },
    { id = "scarlet-monastery", name = "Scarlet Monastery", min = 30, max = 40, quests = {} },
    { id = "scarlet-monastery-graveyard", name = "Scarlet Monastery Graveyard", min = 30, max = 38, quests = {} },
    { id = "excavation-site", name = "Excavation Site: Wetlands", min = 26, max = 31, quests = {} },
    { id = "gnomeregan", name = "Gnomeregan", min = 29, max = 38, quests = {} },
}

print("Party dungeon signal: reading the planner")
do
    local PP = alice.ns.PartyPlan
    local d = PP.DungeonFor
    check(d({ activity = "Cookie, The Deadmines" }, DUNGEONS).id == "the-deadmines", "\"Cookie, The Deadmines\" is the Deadmines")
    check(d({ activity = "Bloodmage Thalnos, Scarlet Monastery Graveyard" }, DUNGEONS).id == "scarlet-monastery-graveyard", "the longest matching name wins (Graveyard, not Scarlet Monastery)")
    check(d({ activity = "A quest of the Excavation Site, in the Wetlands" }, DUNGEONS).id == "excavation-site", "a quest label finds Excavation Site: Wetlands")
    check(d({ activity = "Trash mobs, Razorfen Kraul" }, DUNGEONS) == nil, "an unknown dungeon matches nothing")
    check(d({ activity = "anything", dungeonID = "gnomeregan" }, DUNGEONS).id == "gnomeregan", "the planner's dungeonID wins")

    local quests = {
        { id = 1, state = "in log" }, { id = 2, state = "completed" }, { id = 3, state = "blocked" },
        { id = 4, state = "check prerequisites" }, { id = 5, state = "future / minimum unknown" },
        { id = 6, state = "future / minimum unknown", minLevel = 40 },
    }
    local dm = { id = "the-deadmines", name = "The Deadmines", quests = quests }
    local P = fakePlanner(alice.env, { dungeons = { dm }, active = { [5] = true, [6] = true } })
    check(PP.OpenQuests(P, dm) == 2, "open quests: in the log (also when the planner can't confirm the level); not done, blocked, not yet picked up, or too high")
    PP.COUNT_AVAILABLE_QUESTS = true
    check(PP.OpenQuests(P, dm) == 3, "with COUNT_AVAILABLE_QUESTS, quests you could pick up count too")
    PP.COUNT_AVAILABLE_QUESTS = false

    -- a realistic plan: solo purchases first, then group targets at 25/35, future at 55
    P = fakePlanner(alice.env, {
        all = DUNGEONS,
        dungeons = { DUNGEONS[1], DUNGEONS[2], DUNGEONS[3], { id = "gnomeregan", name = "Gnomeregan", quests = { { id = 30, state = "in log" } } } },
        plan = {
            { id = "levelfirst-1", kind = "levelFirst", priority = 22, item = item(1, "Cookie, The Deadmines") },
            { id = "target-2", kind = "solo", priority = 25, item = { id = 2, mode = "solo", name = "Bought" } },
            step(3, "Cookie, The Deadmines", 25),
            step(4, "Mutanus the Devourer, Wailing Caverns", 55),
            step(5, "Arugal, Shadowfang Keep", 35),
            step(6, "Rethilgore, Shadowfang Keep", 35),
            step(7, "Trash mobs, Razorfen Kraul", 55),
            step(8, "Sneed, The Deadmines", 35),
            step(9, "Mr. Smite, The Deadmines", 35),
            step(10, "Cookie, The Deadmines", 35),
            step(11, "Edwin VanCleef, The Deadmines", 35),
            { id = "owned-12", kind = "owned", priority = 10, item = item(12, "Cookie, The Deadmines") },
            step(13, "Lord Cobrahn, Wailing Caverns", 35, nil, { id = 13 }),
        },
        est = { [13] = -1.5 },
    })
    local out = PP.Collect(P)
    local by = {}
    for _, e in ipairs(out) do by[e.n] = e end
    check(out[1] and out[1].n == "DM" and out[1].k == "N", "the dungeon with the most current upgrades comes first (DM)")
    check(by.DM and #by.DM.i == 3 and by.DM.i[1] == 3, "up to three items, the most urgent first, no level-first or owned steps")
    check(by.SFK and by.SFK.k == "N", "a current-level target (priority 35) is a Need even after solo steps")
    check(by.WC and by.WC.k == "C" and by.WC.i[1] == 4, "a future-level drop is a Could use; one the planner measured as no better is left out")
    check(by.RFK and by.RFK.k == "C", "a dungeon the planner's list doesn't know is named from its label (Razorfen Kraul)")
    check(#out == PP.MAX_DUNGEONS and not by.GNOMER, "at most four dungeons: gear comes first, so quests-only Gnomeregan is the one dropped")
    local text = alice.ns.Serialize({ v = 1, ap = 1, d = PP.Encode(out) })
    check(#text < 180, "a full report fits one addon message with room to spare (" .. #text .. " bytes)")

    -- solo profile: the planner adds 5 to group steps; in a party that 5 is taken back
    P = fakePlanner(alice.env, { all = DUNGEONS, mode = "solo", plan = { step(20, "Cookie, The Deadmines", 30, "prepare-"), step(21, "Arugal, Shadowfang Keep", 60, "prepare-") } })
    out = PP.Collect(P)
    check(out[1] and out[1].n == "DM" and out[1].k == "N" and out[2] and out[2].k == "C", "a solo profile still reports a Need for a current-level group target")

    P = fakePlanner(alice.env, { all = DUNGEONS, dungeons = { { id = "gnomeregan", name = "Gnomeregan", quests = { { id = 30 }, { id = 31 } } } }, plan = {} })
    out = PP.Collect(P)
    check(out[1] and out[1].n == "GNOMER" and out[1].k == "C" and out[1].q == 2, "quests alone in Gnomeregan are a Could use")

    -- open quests turn a later gear drop into a Need
    P = fakePlanner(alice.env, { all = DUNGEONS, dungeons = { { id = "the-deadmines", name = "The Deadmines", quests = { { id = 40 } } } }, plan = { step(22, "Cookie, The Deadmines", 55) } })
    out = PP.Collect(P)
    check(out[1] and out[1].n == "DM" and out[1].k == "N" and out[1].q == 1, "open quests plus a later gear drop in the Deadmines are a Need")
end

---------------------------------------------------------------------------
print("Party dungeon signal: the real Ruinous Forever Planner")
do
    local RFP = os.getenv("RFP_DIR")
    local fh = RFP and io.open(RFP .. "/RuinousForeverPlanner.toc")
    if not fh then
        print("  skip  RFP_DIR not set")
    else
        fh:close()
        Server.guilds["Real Testers"] = { { name = "Rita Real", rank = 0, guid = "Player-1-00000041" } }
        local rita = Server:NewClient({ name = "Rita Real", guid = "Player-1-00000041", guild = "Real Testers", rank = 0, modules = { "RUIN_Codex" } })
        Server:Advance(5)
        local level, inLog = 24, {}
        rita.env.UnitLevel = function() return level end
        rita.env.UnitFactionGroup = function() return "Alliance" end
        rita.env.GetInventoryItemID = function() return nil end
        rita.env.GetInventoryItemLink = function() return nil end
        rita.env.C_Container = { GetContainerNumSlots = function() return 16 end, GetContainerItemID = function() return nil end,
                                 GetContainerItemInfo = function() return nil end, GetContainerItemLink = function() return nil end }
        rita.env.C_QuestLog = rita.env.C_QuestLog or {}
        rita.env.C_QuestLog.IsQuestFlaggedCompleted = function() return false end
        rita.env.C_QuestLog.IsOnQuest = function(id) return inLog[id] or false end
        local function loadPlanner()
            local P = {}
            for line in io.lines(RFP .. "/RuinousForeverPlanner.toc") do
                local f = line:match("^%s*([%w_]+%.lua)%s*$")
                if f then
                    local chunk = assert(loadfile(RFP .. "/" .. f)); setfenv(chunk, rita.env)
                    local ok, err = pcall(chunk, "RuinousForeverPlanner", P)
                    if not ok then print("       load " .. f .. ": " .. tostring(err)) end
                end
            end
            P.Init(); P.Scan()
            P.char.mode = "group"
            return P
        end
        local PP = rita.ns.PartyPlan
        local P
        local function report() local by = {}; for _, e in ipairs(PP.Collect(P)) do by[e.n] = e end; return by end
        -- level 18 first (levels only go up in the game; the planner keeps your progress)
        level = 18
        P = loadPlanner()
        local by = report()
        check(by.DM and by.DM.k == "N", "level 18, empty slots: the Deadmines is a Need")
        local could = 0
        for _, e in pairs(by) do if e.k == "C" then could = could + 1 end end
        check(could >= 1, "and future-level dungeons are only Could use (" .. could .. ")")
        P.char.mode = "solo"
        by = report()
        check(by.DM and by.DM.k == "N", "a solo profile in a party still reports the Deadmines as a Need")
        local text = rita.ns.Serialize({ v = 1, ap = 1, d = PP.Encode(PP.Collect(P)) })
        check(#text < 200, "a real report fits one addon message (" .. #text .. " bytes)")

        level = 24
        P = loadPlanner()
        by = report()
        check(by.DM and by.DM.k == "N" and by.BFD and by.BFD.k == "N", "level 24: the Deadmines and Blackfathom Deeps are Needs")
        for k in pairs(by) do if #k > 8 or not k:match("^%u[%u%d]*$") then check(false, "every key is a clean short name (" .. k .. ")") end end
        -- put a Deadmines quest in the log
        local dmQuest
        for _, d in ipairs(P.EfficiencyData.dungeons) do
            if d.id == "the-deadmines" then for _, q in ipairs(d.quests) do if q.faction ~= "Horde" and q.minLevel and q.minLevel <= level then dmQuest = dmQuest or q.id end end end
        end
        inLog[dmQuest or 0] = true
        P.Scan()
        by = report()
        check(dmQuest and by.DM and by.DM.q == 1, "a Deadmines quest in the log counts as one open quest (" .. tostring(dmQuest) .. ")")
        check((by.WC and by.WC.q or 0) == 0, "quests merely available elsewhere do not count")
        check(PP.ShortName("The Deadmines") == "DM" and PP.ShortName("Hall of Thanes") == "HOT" and PP.Key("Hall of Thanes") == "HT",
            "with Codex, the name you see is Codex's (HOT) while the key stays HT for everyone")
        check(rita.env.RUIN_API:GetModule("Codex"):DungeonWhere("the deadmines") == "Moonbrook, Westfall", "Codex says where the entrance is")
        errorsSoFar("real planner")
    end
end

---------------------------------------------------------------------------
-- Five players in one party. Fay has Core but no planner, so she hears the
-- party but never reports.
Server.guilds["Party Testers"] = {
    { name = "Dan Dusk", rank = 0, guid = "Player-1-00000051" },
    { name = "Fay Fern", rank = 0, guid = "Player-1-00000052" },
}
local dan = Server:NewClient({ name = "Dan Dusk", guid = "Player-1-00000051", guild = "Party Testers", rank = 0, modules = {} })
local fay = Server:NewClient({ name = "Fay Fern", guid = "Player-1-00000052", guild = "Party Testers", rank = 0, modules = {} })
Server:Advance(5)
local party = { alice, cara, eve, dan, fay }
local function joinParty(list)
    party = list
    for _, c in ipairs({ alice, cara, eve, dan, fay }) do
        local inIt = false
        for _, o in ipairs(list) do if o == c then inIt = true end end
        c.partyOf = inIt and "p1" or nil
        c.env.IsInGroup = function() return c.partyOf ~= nil and #party > 1 end
        c.env.IsInRaid = function() return c.inRaid or false end
        c.env.GetNumGroupMembers = function() return c.partyOf and #party or 0 end
        c.realUnitName = c.realUnitName or c.env.UnitName
        c.env.UnitName = function(u)
            local i = tonumber((u or ""):match("^party(%d)$"))
            if i then
                if not c.partyOf then return nil end
                local others = {}
                for _, o in ipairs(party) do if o ~= c then others[#others + 1] = o end end
                return others[i] and others[i].name
            end
            return c.realUnitName(u)
        end
        c.ns.Planner.P = function() return c.env.RuinousForeverPlanner end
    end
    for _, c in ipairs({ alice, cara, eve, dan, fay }) do Server.fire(c, "GROUP_ROSTER_UPDATE") end
end
-- count what each client hands to the game, by message kind
for _, c in ipairs({ alice, cara, eve, dan, fay }) do
    local real = c.env.C_ChatInfo.SendAddonMessage
    c.kinds = {}
    c.env.C_ChatInfo.SendAddonMessage = function(prefix, text, ...)
        local r = real(prefix, text, ...)
        if r == 0 then local k = text:match("^%d\030([%u]+)\030"); if k then c.kinds[k] = (c.kinds[k] or 0) + 1 end end
        return r
    end
end
local function kindsSent(c, k) return c.kinds[k] or 0 end
local function postsIn(c, needle)
    local n = 0
    for _, m in ipairs(c.sentChat or {}) do if (m[2] == "PARTY" or m[2] == "INSTANCE_CHAT") and m[1]:find(needle, 1, true) then n = n + 1 end end
    return n
end
local function allPosts(needle) local n = 0; for _, c in ipairs({ alice, cara, eve, dan, fay }) do n = n + postsIn(c, needle) end; return n end

print("Party dungeon signal: five players, one party")
do
    for _, c in ipairs({ alice, cara, eve, dan, fay }) do c.env.RuinousForeverPlanner = nil end
    fakePlanner(alice.env, { all = DUNGEONS, plan = { step(1, "Cookie, The Deadmines", 25) } })
    fakePlanner(cara.env, { all = DUNGEONS, plan = { step(2, "Sneed, The Deadmines", 35) } })
    fakePlanner(eve.env, { all = DUNGEONS, plan = { step(3, "Mr. Smite, The Deadmines", 55) },
                           dungeons = { { id = "the-deadmines", name = "The Deadmines", quests = { { id = 9 } } } } })
    fakePlanner(dan.env, { all = DUNGEONS, plan = { step(4, "Edwin VanCleef, The Deadmines", 55), step(5, "Arugal, Shadowfang Keep", 35) } })
    joinParty({ alice, cara, eve, dan, fay })
    Server:Advance(10)
    for _, c in ipairs(party) do c.ns.PartyPlan:Update() end
    Server:Advance(30)

    local PP = alice.ns.PartyPlan
    local row = PP.rows and PP.rows[1]
    check(row and row.short == "DM", "everyone's strip leads with the Deadmines")
    check(row and row.need == 3 and row.could == 1, "Alice and Cara need it, Eve's quests plus a later drop make a Need, Dan could use it")
    check(row and row.heat == 7 and row.tier.name == "Loud", "heat 2+2+2+1 = 7: Loud")
    check(PP.reporting == 4 and PP.size == 5, "Fay has no planner: 4 of 5 reporting")
    check(PP.Line(row, PP.size, PP.reporting) == "3 of 5 need DM (4 of 5 reporting)", "the line says who is missing (" .. PP.Line(row, PP.size, PP.reporting) .. ")")
    local same = true
    for _, c in ipairs(party) do
        local r = c.ns.PartyPlan.rows and c.ns.PartyPlan.rows[1]
        if not (r and r.short == "DM" and r.heat == 7) then same = false end
    end
    check(same, "all five see the same heat, Fay included")
    check(PP.rows[2] and PP.rows[2].short == "SFK" and PP.rows[2].tier.name == "Quiet", "Shadowfang Keep is second and quiet")
    check(allPosts("need DM") == 1 and postsIn(alice, "[RUIN] 3 of 5 need DM") == 1, "exactly one player (the first name) posts it to party chat")
    check(chatHas(cara, "Your party: 3 of 5 need DM (4 of 5 reporting) (Loud)") and chatHas(fay, "Your party: 3 of 5 need DM"), "one toast tells each player, once the party has settled")
    check(not chatHas(cara, "(Noticed)"), "no \"Noticed\" toast on the way up while reports were still arriving")

    -- the strip
    local st = PP.PipStates(row, PP.size, PP.reporting)
    check(table.concat(st, ",") == "need,need,need,could,none", "dots: three filled, one ring, Fay's faint ring (" .. table.concat(st, ",") .. ")")
    check(table.concat(PP.PipStates({ need = 1, could = 0 }, 3, 3), ",") == "need,nothing,nothing", "a player who reports nothing there gets a grey ring")
    local strip = PP.strip
    check(strip and strip.rows[1].row == row and strip.rows[1].key:GetText() == "DM" and strip.rows[1].pulse == true, "the strip shows DM and pulses at Loud")
    check(strip.rows[1].count:GetText() == "3/5", "with a 3/5 count")
    check(strip.rows[2].row and strip.rows[2].row.short == "SFK" and not strip.rows[2].pulse, "and Shadowfang Keep below it, still")

    -- the tooltip names everyone, with item links and quests
    local lines = {}
    alice.env.GameTooltip = { SetOwner = function() end, AddLine = function(_, t) lines[#lines + 1] = t end, Show = function() end, Hide = function() end }
    alice.env.C_Item = { GetItemInfo = function(id) return "Item " .. id, "|cff1eff00|Hitem:" .. id .. "|h[Item " .. id .. "]|h|r" end }
    PP.Tooltip(strip.rows[1], row)
    local tip = table.concat(lines, "\n")
    check(lines[1] == "The Deadmines (DM) - 3 of 5 need it", "tooltip title (" .. tostring(lines[1]) .. ")")
    check(tip:find("Alice Ash needs it: |cff1eff00|Hitem:1|h[Item 1]|h|r", 1, true), "my own line with the item as a link")
    check(tip:find("Eve Ember needs it: |cff1eff00|Hitem:3|h[Item 3]|h|r; 1 quest", 1, true), "Eve's line shows her quest")
    check(tip:find("Dan Dusk could use it", 1, true) and tip:find("Fay Fern has no RUIN report", 1, true), "Dan could use it; Fay has no report")
    check(tip:find("Entrance: Moonbrook, Westfall", 1, true), "Codex adds the entrance")

    -- Run it? says it in party chat; it never repeats the auto-post within the cooldown
    local before = postsIn(cara, "[RUIN] 3 of 5 need DM")
    cara.ns.PartyPlan.strip.rows[1].run._scripts.OnClick(cara.ns.PartyPlan.strip.rows[1].run)
    check(postsIn(cara, "[RUIN] 3 of 5 need DM") == before + 1, "Run it? posts the line for whoever clicks it")

    -- combat fades the strip
    alice.env.UnitAffectingCombat = function() return true end
    local alpha
    strip.SetAlpha = function(_, a) alpha = a end
    strip._scripts.OnUpdate(strip, 0.1)
    check(alpha == 0.35, "in combat the strip fades")
    alice.env.UnitAffectingCombat = function() return false end
    strip._scripts.OnUpdate(strip, 0.1)
    check(alpha == 1, "and comes back after")

    -- a fifth Need makes it a full party
    fakePlanner(dan.env, { all = DUNGEONS, plan = { step(4, "Edwin VanCleef, The Deadmines", 35) } })
    dan.ns.PartyPlan:Update()
    Server:Advance(30)
    row = PP.rows[1]
    check(row.heat == 8 and row.tier.name == "Full party" and allPosts("need DM") == 2, "4 Need = heat 8: Full party, and one more post (" .. allPosts("need DM") .. ")")
    errorsSoFar("five players")
end

print("Party dungeon signal: switches")
do
    local PP = alice.ns.PartyPlan
    PP:Command("off")
    check(alice.ns.db.settings.partySignal == false and not PP:Enabled() and (PP.rows and #PP.rows == 0), "/ruin party off: no strip, nothing shared")
    local sent = Server.sent
    PP:Update(); PP:Send(true); Server:Advance(2)
    check(Server.sent == sent, "and nothing is sent while off")
    PP:Command("on")
    check(PP:Enabled(), "/ruin party on turns it back on")
    PP:Command("post off")
    check(alice.ns.db.settings.partyAutoPost == false and not PP:AutoPost(), "/ruin party post off stops the party chat post")
    PP:Command("post on")
    -- the Planner page checkboxes write the same settings
    alice.ns.Planner:AddPage()
    alice.env.RUIN_API:OpenTab("Planner")
    T.openAllSubTabs(alice, "Planner")
    errorsSoFar("switches")
end

print("Party dungeon signal: Retail chat lockdown and instances")
do
    local PP = alice.ns.PartyPlan
    -- instance: no toasts, no automatic post; Run it? still works
    for _, c in ipairs(party) do c.env.IsInInstance = function() return true end; c.ns.PartyPlan.rows = {} end
    for _, c in ipairs(party) do
        local P = c.env.RuinousForeverPlanner
        if P then P.char.mode = "group" end
    end
    local postsBefore = allPosts("need")
    fakePlanner(fay.env, { all = DUNGEONS, plan = { step(6, "Arugal, Shadowfang Keep", 35) } })
    fakePlanner(eve.env, { all = DUNGEONS, plan = { step(7, "Rethilgore, Shadowfang Keep", 35) } })
    fakePlanner(cara.env, { all = DUNGEONS, plan = { step(8, "Arugal, Shadowfang Keep", 25) } })
    for _, c in ipairs(party) do c.ns.PartyPlan:Update() end
    Server:Advance(30)
    local sfk
    for _, r in ipairs(PP.rows) do if r.short == "SFK" then sfk = r end end
    check(sfk and sfk.tier.level >= 3, "Shadowfang Keep gets loud inside the instance (heat " .. tostring(sfk and sfk.heat) .. ")")
    check(allPosts("need SFK") == 0 and not chatHas(alice, "need SFK"), "inside an instance: no toast and no automatic post")
    alice.env.LE_PARTY_CATEGORY_INSTANCE = 2
    alice.env.IsInGroup = function(cat) return true end
    check(PP:Post(sfk, true) and postsIn(alice, "need SFK") == 1 and alice.sentChat[#alice.sentChat][2] == "INSTANCE_CHAT",
        "Run it? inside a dungeon finder group uses instance chat")
    alice.env.IsInGroup = function() return alice.partyOf ~= nil and #party > 1 end
    alice.env.LE_PARTY_CATEGORY_INSTANCE = nil
    for _, c in ipairs(party) do c.env.IsInInstance = function() return false end end

    -- chat lockdown (an encounter, a key, a PvP match): nothing is said, party messages drop, the rest waits
    local locked = true
    alice.env.C_ChatInfo.InChatMessagingLockdown = function() return locked end
    check(PP.ChatLocked(), "the lockdown is seen")
    local n = #(alice.sentChat or {})
    check(PP:Post(sfk, true) == false and #(alice.sentChat or {}) == n and chatHas(alice, "Party chat is locked by the game"), "Run it? during a lockdown says why and sends nothing")
    local pp0, q0 = kindsSent(alice, "PARTYPLAN"), kindsSent(alice, "PLANQ")
    alice.ns.Comms:Send("PARTYPLAN", { v = 1, ap = 0, d = {} }, "PARTY")
    alice.ns.Comms:Send("PLANQ", {}, "ORG")
    Server:Advance(3)
    check(kindsSent(alice, "PARTYPLAN") == pp0 and kindsSent(alice, "PLANQ") == q0, "addon messages are held during the lockdown")
    locked = false
    Server:Advance(3)
    check(kindsSent(alice, "PLANQ") == q0 + 1 and kindsSent(alice, "PARTYPLAN") == pp0, "afterwards the org message goes, the stale party one does not")
    alice.env.C_ChatInfo.InChatMessagingLockdown = nil
    alice.env.C_RestrictedActions = { IsAddOnRestrictionActive = function(t) return t == 1 end }
    alice.env.Enum.AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 }
    check(PP.ChatLocked(), "an encounter restriction counts as locked too")
    alice.env.C_RestrictedActions = nil

    -- the game refuses one send with AddOnMessageLockdown: it stays queued and goes later
    alice.env.Enum.SendAddonMessageResult.AddOnMessageLockdown = 11
    local real = alice.env.C_ChatInfo.SendAddonMessage
    local refused = 0
    alice.env.C_ChatInfo.SendAddonMessage = function(...) if refused == 0 then refused = 1; return 11 end return real(...) end
    local q1 = kindsSent(alice, "PLANQ")
    alice.ns.Comms:Send("PLANQ", {}, "ORG")
    Server:Advance(3)
    check(refused == 1 and kindsSent(alice, "PLANQ") == q1 + 1, "a message refused during a lockdown is sent once it lifts")
    alice.env.C_ChatInfo.SendAddonMessage = real

    -- secret values: ignored, no error
    alice.env.issecretvalue = function(v) return v == "Cara Cole" end
    local before = PP.reports["caracole"] and PP.reports["caracole"].t
    cara.ns.PartyPlan:Send(true)
    Server:Advance(25)
    check((PP.reports["caracole"] and PP.reports["caracole"].t) == before, "a message whose sender is a secret value is ignored")
    alice.env.issecretvalue = nil

    -- Retail: nothing in the party signal registers a restricted event
    local src = io.open((arg[0]:match("^(.*)/") or ".") .. "/../RUIN_Core/PartyPlan.lua"):read("*a")
    local bad = {}
    alice.ns.CLIENT = "retail"
    for ev in src:gmatch('RegisterEvent%("([%u_]+)"') do if not alice.ns:CanRegisterEvent(ev) then bad[#bad + 1] = ev end end
    alice.ns.CLIENT = "forever"
    check(#bad == 0, "no restricted Retail event is registered (" .. table.concat(bad, ",") .. ")")
    errorsSoFar("lockdown")
end

print("Party dungeon signal: security")
do
    local PP = alice.ns.PartyPlan
    local key = "caracole"
    -- a stranger who is not in my group
    Server.guilds["Nowhere"] = { { name = "Stan Stranger", rank = 0, guid = "Player-1-00000077" } }
    local stan = Server:NewClient({ name = "Stan Stranger", guid = "Player-1-00000077", guild = "Nowhere", rank = 0, modules = {} })
    stan.partyOf = "p1"
    stan.env.IsInGroup = function() return true end
    stan.env.IsInRaid = function() return false end
    stan.env.GetNumGroupMembers = function() return 2 end
    stan.env.UnitName = function(u) return u == "party1" and "Alice Ash" or "Stan Stranger" end
    Server:Advance(5)
    local heat = PP.rows[1].heat
    stan.ns.Comms:Send("PARTYPLAN", { v = 1, ap = 1, d = { "DM:N:9:", "SFK:N:9:" } }, "PARTY")
    Server:Advance(5)
    check(PP.rows[1].heat == heat and not PP.reports["stanstranger"], "a report from someone outside my group changes nothing")

    -- party members may be strangers: only party kinds are accepted over party chat
    local got = {}
    alice.ns.Comms:Register("TESTKIND", function(_, sender, scope) got[#got + 1] = scope end)
    cara.ns.Comms:Send("TESTKIND", { x = 1 }, "PARTY")
    cara.ns.Comms:Send("TESTKIND", { x = 1 }, "PEER", "Alice Ash")
    Server:Advance(3)
    check(#got == 1 and got[1] == "PEER", "other message kinds over party chat are dropped")

    -- one entry per dungeon: a duplicate can't double a player's weight
    cara.ns.Comms:Send("PARTYPLAN", { v = 1, ap = 0, d = { "WC:N:0:", "WC:N:0:", "WC:N:0:" } }, "PARTY")
    Server:Advance(3)
    local wc
    for _, r in ipairs(PP.rows) do if r.short == "WC" then wc = r end end
    check(wc and wc.heat == 2 and wc.need == 1, "a dungeon listed three times counts once")

    -- oversized and malformed fields
    Server:Advance(25)
    local junk = { ("X"):rep(200), "DM:N:99999:", "DM:Q:1:", { n = "DM", k = "N" }, 42, "RFC:N:1:" .. ("1"):rep(120) }
    cara.ns.Comms:Send("PARTYPLAN", { v = 1, ap = "yes", d = junk, extra = ("y"):rep(600) }, "PARTY")
    Server:Advance(10)
    local rep = PP.reports[key]
    check(rep and #rep.d == 0 and rep.ap == false, "oversized and malformed entries are dropped (a long message over several parts is still read)")

    -- a flood: at most four reports per sender every 20 seconds
    Server:Advance(25)
    for i = 1, 20 do cara.ns.Comms:Send("PARTYPLAN", { v = 1, ap = 0, d = { (i <= 4 and "RFC" or "BFD") .. ":N:0:" } }, "PARTY") end
    Server:Advance(25)
    rep = PP.reports[key]
    check(rep and rep.d[1] and rep.d[1].n == "RFC", "a flood of reports: the extras are ignored (" .. tostring(rep and rep.d[1] and rep.d[1].n) .. ")")
    Server:Advance(25)
    local a0 = kindsSent(alice, "PARTYPLAN")
    for _ = 1, 15 do cara.ns.Comms:Send("PARTYPLANQ", {}, "PARTY") end
    Server:Advance(30)
    local answers = kindsSent(alice, "PARTYPLAN") - a0
    check(answers >= 1 and answers <= 2, "a flood of requests gets one or two answers, not one per request (" .. answers .. ")")

    -- the report's own fields never decide who sent it
    Server:Advance(25)
    cara.ns.Comms:Send("PARTYPLAN", { v = 1, ap = 0, name = "Eve Ember", sender = "Eve Ember", d = { "ZF:N:0:" } }, "PARTY")
    Server:Advance(3)
    check(PP.reports[key] and PP.reports[key].d[1].n == "ZF" and not (PP.reports["eveember"] and PP.reports["eveember"].d[1] and PP.reports["eveember"].d[1].n == "ZF"), "a name inside the data is ignored: the game's sender name counts")

    -- someone leaves halfway through a long message
    Server:Advance(25)
    cara.ns.Comms:Send("PARTYPLAN", { v = 1, ap = 0, d = { "ULDA:N:0:" }, pad = ("z"):rep(700) }, "PARTY")
    Server:Advance(0.15)
    joinParty({ alice, eve, dan, fay })
    Server:Advance(10)
    check(not PP.reports[key], "when someone leaves, their report goes, even one that was still arriving")
    for _, r in ipairs(PP.rows) do if r.short == "ULDA" then check(false, "a half-sent report from someone who left counts") end end

    -- a raid: no party signal at all
    alice.inRaid = true
    check(PP.Roster() == nil and not PP:InGroup("Eve Ember"), "in a raid there is no party signal")
    alice.inRaid = false

    -- leaving the party clears the strip
    joinParty({})
    Server:Advance(5)
    check(#(PP.rows or {}) == 0, "leaving the party clears the strip")
    for _, c in ipairs({ alice, cara, eve, dan, fay }) do c.partyOf = nil end
    errorsSoFar("party security")
end
