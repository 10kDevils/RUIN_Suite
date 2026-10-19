-- Continued feature tests; T holds clients and helpers from run_features.lua
local alice, cara, eve, check, chatHas, errorsSoFar = T.alice, T.cara, T.eve, T.check, T.chatHas, T.errorsSoFar

print("Finder")
do
    -- Cara lists her group needing a healer for Dungeon; Eve is looking as a healer.
    local cdb = cara.env.RUIN_FinderCharDB
    cdb.needT, cdb.needH, cdb.needD = 0, 1, 0
    cara.env.SlashCmdList.RUINFINDER("group dungeon")
    Server:Advance(3)
    local edb = eve.env.RUIN_FinderCharDB
    edb.tank, edb.healer, edb.dps = false, true, false
    eve.env.SlashCmdList.RUINFINDER("on dungeon")
    Server:Advance(4)
    check(chatHas(eve, "Match: ") and chatHas(eve, "needs a Healer"), "Eve alerted that Cara's group needs her as healer")
    check(chatHas(cara, "Match: ") and chatHas(cara, "(Healer) is looking for Dungeon"), "Cara alerted that Eve can heal for her group")
    check(eve.env.RUIN_FinderBadge and eve.env.RUIN_FinderBadge:IsShown() and eve.env.RUIN_FinderBadge.text:GetText():find("1 match"), "Eve's badge shows the match (" .. tostring(eve.env.RUIN_FinderBadge and eve.env.RUIN_FinderBadge.text:GetText()) .. ")")
    -- badge right-click stops looking
    eve.env.RUIN_FinderBadge._scripts.OnMouseUp(eve.env.RUIN_FinderBadge, "RightButton")
    check(not edb.looking and not eve.env.RUIN_FinderBadge:IsShown(), "right-click on the badge stops looking")
    -- Muster open slots on the board (Alice posted Molten Core next week with needs)
    local mu = alice.env.RUIN_API:GetModule("Muster")
    local ev = mu:Create("Scarlet run", os.date("%Y-%m-%d %H:%M", os.time() + 5 * 3600), { kind = "Dungeon", size = "5", need = { 1, 1, 3 } })
    Server:Advance(3)
    alice.env.RUIN_API:OpenTab("Finder")
    local found
    for _, f in ipairs(alice.frames) do
        if f.text and f.text.GetText and type(f.text:GetText()) == "string" and f.text:GetText():find("Scarlet run") then found = f end
    end
    check(found ~= nil, "Muster event with open slots shown on the Finder board")
    -- level filter
    alice.env.RUIN_FinderCharDB.levels = "Within 3"
    alice.env.RUIN_API:OpenTab("Finder")
    errorsSoFar("finder")
end

print("Intel")
do
    eve.zone, eve.subzone = "The Barrens", "The Crossroads"
    eve.pos = { map = 1411, x = 0.52, y = 0.30 }
    local seen
    alice.env.RUIN_API:Subscribe("Intel:SPOT", function(s) seen = s end)
    eve.env.SlashCmdList.RUININTEL("enemy 8 Horde heading north")
    Server:Advance(2)
    check(chatHas(alice, "Enemy group") and chatHas(alice, "8 Horde heading north"), "enemy sighting reached Alice")
    check(seen and seen.map == 1411 and math.abs(seen.x - 0.52) < 0.001, "sighting published to other modules with its position")
    local pins = alice.env.RUIN_API.Map:GetPins("Intel")
    local pin = next(pins) and pins[next(pins)]
    check(pin and pin.alpha == 1, "fresh report pinned on the map at full strength")
    Server:Advance(20 * 60)
    pins = alice.env.RUIN_API.Map:GetPins("Intel")
    pin = next(pins) and pins[next(pins)]
    check(pin and pin.alpha < 0.5, "pin faded as the report aged (" .. tostring(pin and pin.alpha) .. ")")
    Server:Advance(11 * 60)
    check(next(alice.env.RUIN_API.Map:GetPins("Intel")) == nil, "pin removed after 30 minutes")
    -- under attack
    cara.pos = { map = 1411, x = 0.6, y = 0.6 }
    cara.env.RUIN_Intel_UnderAttack()
    Server:Advance(2)
    check(chatHas(alice, "UNDER ATTACK:"), "under-attack call reached Alice")
    cara.env.RUIN_Intel_UnderAttack()
    check(chatHas(cara, "already called for help"), "under-attack has a one-minute cooldown")
    -- timers
    cara.env.SlashCmdList.RUININTEL("timer dragonslayer 3")
    Server:Advance(2)
    check(chatHas(alice, "drops in"), "planned buff drop announced")
    Server:Advance(130)
    check(chatHas(alice, "drops in under a minute"), "one-minute warning")
    Server:Advance(60)
    local rec = alice.env.RUIN_IntelDB.timers.dragonslayer
    check(rec and rec.last and not rec.plan, "buff marked dropped once the time passed")
    alice.env.SlashCmdList.RUININTEL("timer azuregos")
    Server:Advance(2)
    check(cara.env.RUIN_IntelDB.timers.azuregos and cara.env.RUIN_IntelDB.timers.azuregos.last, "boss kill shared")
    T.openAllSubTabs(alice, "Intel")
    errorsSoFar("intel")
end

print("Muster: rally points and bounties (from Warfront)")
do
    local mu = alice.env.RUIN_API:GetModule("Muster")
    alice.pos = { map = 1411, x = 0.40, y = 0.40 }
    local ev = mu:Rally("Crossroads")
    Server:Advance(2)
    check(ev and ev.rally and alice.env.RUIN_API.Map:GetPins("Muster")[ev.id], "rally pinned on the map")
    check(cara.env.RUIN_API.Map:GetPins("Muster")[ev.id], "Cara's map shows it too")
    -- an Intel enemy sighting near the rally contests it
    eve.pos = { map = 1411, x = 0.402, y = 0.40 }
    eve.env.SlashCmdList.RUININTEL("enemy 5 Horde riders")
    Server:Advance(2)
    check(chatHas(alice, "Crossroads rally point is contested: 5 Horde riders"), "Intel sighting contests the rally point")
    check(alice.env.RUIN_MusterDB.events[ev.id].contested ~= nil, "event marked contested")
    -- a posted event can carry a rally point too
    local later = mu:Create("Tarren Mill push", os.date("%Y-%m-%d %H:%M", os.time() + 3600), { kind = "PvP", rally = true })
    Server:Advance(2)
    check(later and later.rally and cara.env.RUIN_MusterDB.events[later.id].rally, "event posted with a rally point")
    -- bounty: posted by Alice, claimed by Eve, witnessed by Cara
    alice.env.SlashCmdList.RUINMUSTER("bounty guild Bloodfang (50g)")
    Server:Advance(2)
    check(chatHas(cara, "Bounty on guild Bloodfang (50g)"), "bounty reached Cara")
    cara.pos = { map = 1411, x = 0.401, y = 0.40 }
    eve.target, eve.targetGuild, eve.targetDead = "Grok", "Bloodfang", false
    eve.env.SlashCmdList.RUINMUSTER("claim")
    check(chatHas(eve, "still alive"), "can't claim a living enemy")
    eve.targetDead = true
    eve.env.RUIN_Muster_Claim()
    Server:Advance(2)
    check(chatHas(cara, "Did you see"), "Cara, standing nearby, is asked to witness")
    eve.env.SlashCmdList.RUINMUSTER("confirm")
    check(not chatHas(alice, "Bounty confirmed"), "Eve can't confirm her own kill")
    cara.env.SlashCmdList.RUINMUSTER("confirm")
    Server:Advance(2)
    check(chatHas(alice, "Bounty confirmed: ") and chatHas(alice, "Grok"), "confirmed bounty announced to RUIN")
    Server:Advance(11 * 60)
    check(not chatHas(alice, "Lua"), "rally contest wears off quietly")
    T.openAllSubTabs(alice, "Muster")
    T.openAllSubTabs(eve, "Muster")
    errorsSoFar("muster rally and bounties")
end

print("Pathfinder")
do
    local pf = alice.env.RUIN_API:GetModule("Pathfinder")
    -- waypoint arrow toward step 1 of Valley of Trials (Durotar 43.3, 68.5)
    alice.pos = { map = 1411, x = 0.40, y = 0.68 }
    pf:StartRoute("vot")
    local tr = alice.env.RUIN_PathfinderTracker
    tr.nav._scripts.OnUpdate(tr.nav, 0.1)
    check(tr.arrow:IsShown() and tr.dist:GetText():find("yards"), "arrow points to the step with a distance (" .. tostring(tr.dist:GetText()) .. ")")
    check(alice.env.RUIN_API.Map:GetPins("Pathfinder").step ~= nil, "current step pinned on the map")
    -- in another zone the tracker names the zone instead
    alice.pos = { map = 1429, x = 0.5, y = 0.5 }
    tr.nav._scripts.OnUpdate(tr.nav, 0.1)
    check(not tr.arrow:IsShown() and tr.dist:GetText():find("Durotar"), "outside the zone the tracker names it")
    alice.pos = { map = 1411, x = 0.40, y = 0.68 }
    -- recorder: accept, complete, turn in, plus a note
    pf:SetRecording(true)
    alice.questTitles[501] = "Lazy Peons"
    Server.fire(alice, "QUEST_ACCEPTED", 501)
    alice.questLog = { { title = "Lazy Peons", id = 501, complete = true } }
    Server.fire(alice, "QUEST_LOG_UPDATE")
    alice.questLog = {}
    Server.fire(alice, "QUEST_TURNED_IN", 501)
    pf:RecordStep("note", nil, "Train at the Den")
    local rec = alice.env.RUIN_PathfinderDB.rec
    check(#rec.steps == 4 and rec.steps[1].act == "accept" and rec.steps[2].act == "complete" and rec.steps[3].act == "turnin"
          and rec.steps[1].at and rec.steps[1].at.zone == "Durotar", "recorder wrote accept, complete, turn in and the place")
    rec.title = "Peon Wake-up"
    local r = pf:SaveRecording()
    check(r and alice.env.RUIN_PathfinderDB.custom[r.id] and #r.steps == 4, "recording saved as a route")
    -- export / import round trip
    local s = alice.env.RUIN_API.Util.Encode("ROUTE", { title = r.title, faction = r.faction, author = r.author, steps = r.steps })
    local cp = cara.env.RUIN_API:GetModule("Pathfinder"):ImportRoute(s)
    check(cp and cp.title == "Peon Wake-up" and #cp.steps == 4, "route imported from a string")
    -- share with RUIN lands in Eve's inbox
    pf:ShareRoute(r.id)
    Server:Advance(8)
    local inbox = eve.env.RUIN_PathfinderDB.inbox
    check(#inbox == 1 and inbox[1].route.title == "Peon Wake-up" and chatHas(eve, "shared a route"), "shared route reached Eve's inbox")
    -- follow: Eve follows Alice's route
    pf:StartRoute(r.id)
    Server:Advance(2)
    local ep = eve.env.RUIN_API:GetModule("Pathfinder")
    local cid = r.id
    eve.env.RUIN_PathfinderDB.custom[cid] = inbox[1].route
    inbox[1].route.id = cid
    ep:Follow(alice.guid)
    pf:Advance(2)
    Server:Advance(3)
    check(eve.env.RUIN_PathfinderCharDB.route == cid and eve.env.RUIN_PathfinderCharDB.step == 3, "Eve's tracker follows Alice to step 3")
    check(eve.env.RUIN_PathfinderTracker.peers:GetText():find("Following Alice"), "tracker says who she follows")
    T.openAllSubTabs(alice, "Pathfinder")
    T.openAllSubTabs(eve, "Pathfinder")
    errorsSoFar("pathfinder")
end

print("Codex")
do
    local cx = alice.env.RUIN_API:GetModule("Codex")
    local function tipLines(c, link)
        local lines = {}
        local tip = { GetItem = function() return "x", link end, AddLine = function(_, l) lines[#lines + 1] = l end }
        for _, hook in ipairs(c.tooltipHooks) do hook(tip) end
        return table.concat(lines, "\n")
    end
    local helm = "|cff0070dd|Hitem:100::|h[New Helm]|h|r"
    check(tipLines(alice, helm):find("Codex: %+100%% upgrade over your head|r .*%(Arms%)"), "upgrade line names the spec's weights")
    alice.env.SlashCmdList.RUINCODEX("spec protection")
    check(alice.env.RUIN_CodexDB.spec == "Protection", "spec override set")
    check(tipLines(alice, helm):find("%(Protection%)"), "tooltip now uses Protection weights")
    alice.env.SlashCmdList.RUINCODEX("spec auto")
    -- officer best-in-slot list reaches Cara and marks the item on her tooltip
    cx:SetBis("WARRIOR", "Arms", "1-29", 1, 100)
    cx:SendBis("WARRIOR", "Arms", "1-29")
    Server:Advance(4)
    check(cara.env.RUIN_CodexDB.bis["WARRIOR:Arms:1-29"] and cara.env.RUIN_CodexDB.bis["WARRIOR:Arms:1-29"].i[1] == 100, "best-in-slot list reached Cara")
    check(tipLines(cara, helm):find("RUIN best%-in%-slot for Arms %(1%-29%)"), "Cara's tooltip marks it best-in-slot")
    -- export / import
    local s = alice.env.RUIN_API.Util.Encode("BIS", { c = "WARRIOR", s = "Fury", b = "30-44", i = { [1] = 100 } })
    cx:ImportBis(s)
    check(alice.env.RUIN_CodexDB.bis["WARRIOR:Fury:30-44"] and alice.env.RUIN_CodexDB.bis["WARRIOR:Fury:30-44"].i[1] == 100, "best-in-slot list imported from a string")
    -- next upgrades: the BiS helm and a learned drop
    eve.instance = "The Deadmines"
    Server.fire(eve, "CHAT_MSG_LOOT", "You receive loot: |cff0070dd|Hitem:5191::::::::|h[Cruel Barb]|h|r.", "Eve Ember")
    Server:Advance(3)
    local ups = cara.env.RUIN_API:GetModule("Codex"):Upgrades(10)
    local ids = {}
    for _, e in ipairs(ups) do ids[e.id] = e end
    check(ids[100] and ids[100].pct and ids[100].sources[1]:find("best%-in%-slot"), "upgrades list includes the best-in-slot helm")
    check(ids[5191] and ids[5191].sources[1]:find("Deadmines"), "and the drop RUIN learned in the Deadmines")
    -- raid planning posts a Muster event
    local ev = cx:PlanRaid(alice.mns.RUIN_Codex.Raids[1], os.date("%Y-%m-%d %H:%M", os.time() + 86400), 20)
    Server:Advance(3)
    check(ev and cara.env.RUIN_MusterDB.events[ev.id] and cara.env.RUIN_MusterDB.events[ev.id].need[3] == 12, "raid planned in Codex posted to Muster with 20-player needs")
    T.openAllSubTabs(alice, "Codex")
    T.openAllSubTabs(eve, "Codex")
    errorsSoFar("codex")
end

print("Exchange")
do
    local ex = alice.env.RUIN_API:GetModule("Exchange")
    local day = 86400
    local now = alice.env.GetServerTime()
    -- a week of older prices, then today's: trend up
    ex:OnPrices({ t = now - 9 * day, l = { 2589, 4000 } }, "Cara Cole")
    ex:OnPrices({ t = now - 8 * day, l = { 2589, 4000 } }, "Cara Cole")
    ex:OnPrices({ t = now - 2 * day, l = { 2589, 4800 } }, "Cara Cole")
    ex:OnPrices({ t = now, l = { 2589, 5000 } }, "Cara Cole")
    local avg, pct = ex:Trend(2589)
    check(avg and math.abs(avg - 4900) < 1 and pct and pct > 20, "7-day average and trend (" .. tostring(avg) .. ", " .. tostring(pct) .. ")")
    local lines = {}
    local tip = { GetItem = function() return "x", "|cffffffff|Hitem:2589::|h[Linen Cloth]|h|r" end, AddLine = function(_, l) lines[#lines + 1] = l end }
    for _, hook in ipairs(alice.tooltipHooks) do hook(tip) end
    check(table.concat(lines, "\n"):find("RUIN 7%-day: avg"), "tooltip shows the 7-day trend")
    -- profession leveling plan from known recipes and RUIN prices
    Server.fire(alice, "TRADE_SKILL_SHOW")
    Server:Advance(4)
    local plan = alice.env.RUIN_ExchangeDB.plans.Alchemy
    check(plan and #plan.list == 2 and plan.list[1].name == "Minor Healing Potion", "cheapest skill-up first (" .. tostring(plan and plan.list[1] and plan.list[1].name) .. ")")
    check(plan.skill == 120 and plan.list[2].perPoint == 10000, "orange flask costs 2 cloth per point")
    -- craft requests alert crafters who know the recipe
    Server.fire(eve, "TRADE_SKILL_SHOW")
    Server:Advance(6)
    cara.env.SlashCmdList.RUINEXCHANGE("request |cff1eff00|Hitem:13510::|h[Flask of the Titans]|h|r -- have mats, 5g tip")
    Server:Advance(3)
    check(chatHas(eve, "needs Flask of the Titans, and you can make it (Alchemy)"), "Eve, an alchemist, alerted to the request")
    local open = 0
    for _ in pairs(alice.env.RUIN_ExchangeDB.requests) do open = open + 1 end
    check(open == 1, "request on Alice's board")
    local rid = next(cara.env.RUIN_ExchangeDB.requests)
    cara.env.RUIN_API:GetModule("Exchange"):CloseRequest(rid)
    Server:Advance(3)
    check(next(alice.env.RUIN_ExchangeDB.requests) == nil, "closing the request clears it everywhere")
    -- bag sweep
    alice.bag = {
        { hyperlink = "|cffffffff|Hitem:2589::|h[Linen Cloth]|h|r", stackCount = 5, isBound = false },
        { hyperlink = "|cff0070dd|Hitem:100::|h[New Helm]|h|r", stackCount = 1, isBound = true },
        { hyperlink = "|cff9d9d9d|Hitem:3300::|h[Rabbit's Foot]|h|r", stackCount = 3, isBound = false },
    }
    local items, ahTotal, vendorTotal = ex:SweepBags()
    local by = {}
    for _, it in ipairs(items) do by[it.id] = it.label end
    check(by[2589] == "ah" and by[100] == "keep" and by[3300] == "vendor", "bag sweep: cloth to the AH, helm upgrade kept, junk vendored")
    check(ahTotal == 25000 and vendorTotal == 12, "bag sweep totals")
    alice.env.SlashCmdList.RUINEXCHANGE("bags")
    T.openAllSubTabs(alice, "Exchange")
    errorsSoFar("exchange")
end

print("Minimap pins")
do
    local R = alice.env.RUIN_API
    alice.pos = { map = 1411, x = 0.50, y = 0.50 }
    R.Map:SetPin("Test", "near", { map = 1411, x = 0.51, y = 0.50, title = "Near" })     -- 40 yd east
    R.Map:SetPin("Test", "far", { map = 1411, x = 0.70, y = 0.50, title = "Far" })       -- 800 yd east: edge
    local driver
    for _, f in ipairs(alice.frames) do
        if f._scripts.OnUpdate and not f.pin then
            local ok = pcall(f._scripts.OnUpdate, f, 0.2)
        end
    end
    local near, far
    for _, f in ipairs(alice.frames) do
        if f.pin and f._shown and f.pin.title == "Near" and f:GetParent() ~= alice.worldCanvas then near = f end
        if f.pin and f._shown and f.pin.title == "Far" then far = f end
    end
    check(near ~= nil and far ~= nil, "minimap shows near and far pins")
    R.Map:ClearPins("Test")
    errorsSoFar("minimap pins")
end
