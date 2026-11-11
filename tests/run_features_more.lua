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

print("Muster: sightings and timers (from Intel)")
do
    eve.zone, eve.subzone = "The Barrens", "The Crossroads"
    eve.pos = { map = 1411, x = 0.52, y = 0.30 }
    local seen
    alice.env.RUIN_API:Subscribe("Muster:SPOT", function(s) seen = s end)
    eve.env.SlashCmdList.RUINMUSTERINTEL("enemy 8 Horde heading north")
    Server:Advance(2)
    check(chatHas(alice, "Enemy group") and chatHas(alice, "8 Horde heading north"), "enemy sighting reached Alice")
    check(seen and seen.map == 1411 and math.abs(seen.x - 0.52) < 0.001, "sighting published to other modules with its position")
    local pins = alice.env.RUIN_API.Map:GetPins("MusterWorld")
    local pin = next(pins) and pins[next(pins)]
    check(pin and pin.alpha == 1, "fresh report pinned on the map at full strength")
    Server:Advance(20 * 60)
    pins = alice.env.RUIN_API.Map:GetPins("MusterWorld")
    pin = next(pins) and pins[next(pins)]
    check(pin and pin.alpha < 0.5, "pin faded as the report aged (" .. tostring(pin and pin.alpha) .. ")")
    Server:Advance(11 * 60)
    check(next(alice.env.RUIN_API.Map:GetPins("MusterWorld")) == nil, "pin removed after 30 minutes")
    -- under attack
    cara.pos = { map = 1411, x = 0.6, y = 0.6 }
    cara.env.RUIN_Muster_UnderAttack()
    Server:Advance(2)
    check(chatHas(alice, "UNDER ATTACK:"), "under-attack call reached Alice")
    cara.env.RUIN_Muster_UnderAttack()
    check(chatHas(cara, "already called for help"), "under-attack has a one-minute cooldown")
    -- timers (in RUIN Finder since 0.4.1; the old Muster command still works)
    cara.env.SlashCmdList.RUINMUSTERINTEL("timer dragonslayer 3")
    Server:Advance(2)
    check(chatHas(alice, "drops in"), "planned buff drop announced")
    Server:Advance(130)
    check(chatHas(alice, "drops in under a minute"), "one-minute warning")
    Server:Advance(60)
    local rec = alice.env.RUIN_FinderDB.timers.dragonslayer
    check(rec and rec.last and not rec.plan, "buff marked dropped once the time passed")
    alice.env.SlashCmdList.RUINMUSTERINTEL("timer azuregos")
    Server:Advance(2)
    check(cara.env.RUIN_FinderDB.timers.azuregos and cara.env.RUIN_FinderDB.timers.azuregos.last, "boss kill shared")
    T.openAllSubTabs(alice, "Muster")
    errorsSoFar("sightings")
    -- Find group hands a sighting to Finder
    local fi = alice.env.RUIN_API:GetModule("Finder")
    check(fi and fi.QuickList ~= nil, "Finder offers QuickList")
    local ok = fi:QuickList("Raid", "World boss", 4, 8, 28)
    local fdb = alice.env.RUIN_FinderCharDB
    check(ok and fdb.looking and fdb.listing == "Group" and fdb.activity == "Raid" and fdb.needD == 28,
          "QuickList starts a Finder group listing")
    fi:QuickList("Nonsense", "x")
    check(fdb.activity == "Questing", "unknown activity falls back to Questing")
    fdb.looking = false
    -- Muster's own Find group path
    local W = alice.mns and alice.mns.RUIN_Muster and alice.mns.RUIN_Muster.World
    check(W and W.FindGroup, "Muster has Find group")
    if W then
        W.FindGroup("rare", "Hemathion")
        check(fdb.activity == "Questing" and fdb.detail == "Hemathion" and fdb.looking, "Find group on a rare lists Questing")
        W.FindGroup("boss", "")
        check(fdb.activity == "Raid" and fdb.detail == "World boss", "Find group on a boss lists a Raid")
    end
    -- an old RUIN Intel client still reaches Muster
    local seenOld
    alice.env.RUIN_API:Subscribe("Muster:SPOT", function(sp) seenOld = sp end)
    cara.ns.Comms:Send("Intel:SPOT", { k = "rare", x = "Old client", w = "Un'Goro", t = os.time() }, "ORG")
    Server:Advance(2)
    check(seenOld and seenOld.kind == "rare" and seenOld.text == "Old client", "sighting from an old Intel version understood")
    errorsSoFar("find group")
end

print("Muster: rally points and bounties (from Warfront)")
do
    local mu = alice.env.RUIN_API:GetModule("Muster")
    alice.pos = { map = 1411, x = 0.40, y = 0.40 }
    local ev = mu:Rally("Crossroads")
    Server:Advance(2)
    check(ev and ev.rally and alice.env.RUIN_API.Map:GetPins("Muster")[ev.id], "rally pinned on the map")
    check(cara.env.RUIN_API.Map:GetPins("Muster")[ev.id], "Cara's map shows it too")
    -- an enemy sighting near the rally contests it
    eve.pos = { map = 1411, x = 0.402, y = 0.40 }
    eve.env.SlashCmdList.RUINMUSTERINTEL("enemy 5 Horde riders")
    Server:Advance(2)
    check(chatHas(alice, "Crossroads rally point is contested: 5 Horde riders"), "enemy sighting contests the rally point")
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
    -- double-clicking the tracker opens Pathfinder (one click doesn't)
    local opened
    local realOpen = pf.OpenTab
    pf.OpenTab = function(...) opened = true; return realOpen(...) end
    tr._scripts.OnMouseUp(tr, "LeftButton")
    check(not opened, "one click on the tracker doesn't open Pathfinder")
    tr._scripts.OnMouseUp(tr, "LeftButton")
    pf.OpenTab = realOpen
    check(opened, "a double-click opens Pathfinder")
    check(tr.open == nil and tr.clear and tr.clear.icon, "no Open button; a little x instead of Clear")
    alice.pos = { map = 1411, x = 0.40, y = 0.68 }
    -- the game's waypoint (3D pin in the world) sits on the step
    check(alice.waypoint and alice.waypoint.uiMapID == 1411 and math.abs(alice.waypoint.position.x - 0.433) < 0.001
          and alice.superTracked == true, "the step gets the game's waypoint, super-tracked so its 3D pin shows")
    local printed = {}
    local realPrint = pf.Print
    pf.Print = function(_, m) printed[#printed + 1] = m end
    alice.env.SlashCmdList.RUINPATH("nav")
    pf.Print = realPrint
    check(#printed >= 8 and table.concat(printed, "\n"):find("offset:"), "/path nav reports each link from the step to the arrow and the pin")
    -- a waypoint you place yourself isn't cleared by Pathfinder
    local mine = alice.env.UiMapPoint.CreateFromCoordinates(1411, 0.1, 0.1)
    alice.waypoint = mine
    pf:ClearRoute()
    check(alice.waypoint == mine, "clearing the route leaves your own waypoint alone")
    pf:StartRoute("vot")
    tr = alice.env.RUIN_PathfinderTracker
    -- a quest step whose quest is in your log is tracked the game's way (super-tracked)
    alice.logIds = { [4641] = true }
    alice.questTitles[4641] = "Your Place In The World"
    alice.questObjectives = { [4641] = { { text = "Talk to Gornek", finished = false } } }
    pf:Advance(1)
    check(alice.trackedQuest == 4641 and alice.waypoint == nil, "a quest in your log is super-tracked, and Pathfinder's map waypoint is lifted")
    -- the RUIN pin rides the game's navigation frame and names the tracked quest
    local navFrame = alice.env.CreateFrame("Frame")
    navFrame.GetCenter = function() return 400, 300 end
    navFrame.GetEffectiveScale = function() return 1 end
    alice.navFrame = navFrame
    Server.fire(alice, "NAVIGATION_FRAME_CREATED")
    local pinFrame = pf.Pin.Frame()
    local drive = pf.Pin.Driver
    check(pinFrame ~= nil, "the RUIN pin attaches to the game's navigation")
    drive._scripts.OnUpdate(drive, 0.1)
    check(pinFrame:IsShown() and pinFrame.title._text == "Your Place In The World" and pinFrame.dist._text:find("140 yd")
          and pinFrame.obj._text:find("Talk to Gornek"), "it shows the quest, the distance and its objectives")
    alice.navClamped = true
    drive._scripts.OnUpdate(drive, 0.1)
    check(pinFrame.arrow:IsShown(), "off screen it waits at the edge with an arrow")
    alice.navClamped = false
    -- inside the quest's area (the game says in range), or nearer than the set distance, it steps aside
    drive._scripts.OnUpdate(drive, 0.6)
    alice.navState = 2
    drive._scripts.OnUpdate(drive, 0.2)
    check(pinFrame:IsShown() and pinFrame.fade > 0.5 and pinFrame.fade < 0.7, "entering the quest's area the pin starts to fade")
    drive._scripts.OnUpdate(drive, 0.4)
    check(not pinFrame:IsShown(), "and is gone after half a second")
    alice.navState = 0
    -- in the quest's objective area (near its mobs' spawn points) it always hides, whatever the options
    local QB = pf.QB
    local realHas, realSpots = QB.Has, QB.Spots
    QB.Has = function() return true end
    QB.Spots = function(q, which) return which == "objective" and q == 4641 and { { map = 1411, x = 0.41, y = 0.68 } } or {} end
    alice.env.RUIN_PathfinderCharDB.pinHideInArea = false
    drive._scripts.OnUpdate(drive, 0.6)
    drive._scripts.OnUpdate(drive, 0.6)
    check(not pinFrame:IsShown(), "inside the quest's objective area the pin always hides")
    alice.pos = { map = 1411, x = 0.60, y = 0.40 }
    Server:Advance(1)
    drive._scripts.OnUpdate(drive, 0.6)
    check(pinFrame:IsShown(), "and comes back when you leave it")
    QB.Has, QB.Spots = realHas, realSpots
    alice.env.RUIN_PathfinderCharDB.pinHideInArea = true
    alice.pos = { map = 1411, x = 0.40, y = 0.68 }
    Server:Advance(1)
    alice.navDistance = 10
    drive._scripts.OnUpdate(drive, 0.6)
    check(not pinFrame:IsShown(), "it also stays hidden within the hide distance")
    local pdb = alice.env.RUIN_PathfinderCharDB
    pdb.pinHideInArea = false
    drive._scripts.OnUpdate(drive, 0.6)
    check(pinFrame:IsShown(), "unless that option is off")
    pdb.pinHideInArea = true
    alice.navDistance = nil
    -- settings: objectives and walking time can be left off the pin
    pdb.pinObjectives, pdb.pinWalk = false, false
    pf.RefreshPin()
    drive._scripts.OnUpdate(drive, 0.1)
    check(pinFrame.obj._text == "" and not pinFrame.dist._text:find("sec"), "objectives and walking time follow their options")
    pdb.pinObjectives, pdb.pinWalk = true, true
    -- the waypoint no longer depends on the tracker's arrow option
    pdb.arrow = false
    pf.RefreshPin()
    check(alice.trackedQuest == 4641, "turning off the tracker arrow leaves the waypoint alone")
    pdb.arrow = true
    -- the key bindings reach Pathfinder
    check(alice.env.BINDING_NAME_RUIN_PATH_NEXT == "Next step" and type(alice.env.RUIN_PathfinderBinding) == "function", "key bindings are named")
    -- the tracker's tabs: Route works as before, Tracked shows the tracked quest
    check(tr.tabs and #tr.tabs == 2 and tr.tabs[1].text._text == "Route" and tr.tabs[2].text._text == "Tracked", "the tracker has Route and Tracked tabs")
    -- the quest Pathfinder tracks for a step isn't "yours": Tracked has nothing and can't be picked
    check(tr.tabs[1].ok and not tr.tabs[2].ok, "with no quest of yours tracked the Tracked tab is greyed out")
    tr.tabs[2]._scripts.OnClick(tr.tabs[2])
    check(tr.title._text:find("Valley of Trials"), "and clicking it does nothing")
    -- you pick a quest in the objective tracker: it's yours, and the Tracked tab opens
    alice.logIds[788] = true
    alice.questTitles[788] = "Cutting Teeth"
    alice.questObjectives[788] = { { text = "Mottled Boar slain: 3/10", finished = false } }
    alice.env.C_SuperTrack.SetSuperTrackedQuestID(788)
    Server.fire(alice, "SUPER_TRACKING_CHANGED")
    Server:Advance(1)
    check(tr.tabs[2].ok and tr.title._text:find("Tracked") and tr.title._text:find("Cutting Teeth") and tr.step._text:find("Mottled Boar"),
          "picking a quest makes it your tracked quest and shows it on Tracked")
    check(alice.trackedQuest == 788 and alice.waypoint == nil, "the world pin follows your quest while Tracked is selected")
    tr.tabs[1]._scripts.OnClick(tr.tabs[1])
    check(alice.trackedQuest == 4641 and tr.title._text:find("Valley of Trials"), "Route: the world pin follows the route's step again")
    tr.tabs[2]._scripts.OnClick(tr.tabs[2])
    check(alice.trackedQuest == 788, "Tracked: back to your quest")
    alice.questLog = { { title = "Your Place In The World", id = 4641 }, { title = "Cutting Teeth", id = 788 } }
    tr.next._scripts.OnClick(tr.next)
    check(alice.trackedQuest == 4641 and tr.title._text:find("Your Place"), "> on Tracked tracks the next quest in your log")
    tr.prev._scripts.OnClick(tr.prev)
    check(alice.trackedQuest == 788, "< goes back")
    tr.clear._scripts.OnClick(tr.clear)
    check(alice.env.RUIN_PathfinderCharDB.userQuest == nil and not tr.tabs[2].ok and tr.title._text:find("Valley of Trials"),
          "the x on Tracked stops tracking your quest and goes back to the route")
    check(alice.trackedQuest == 4641, "and the world pin is the route's again")
    alice.questLog = {}
    -- a quest the game can't place falls back to Pathfinder's waypoint
    alice.navFrame = nil
    Server.fire(alice, "NAVIGATION_FRAME_DESTROYED")
    check(not pinFrame:IsShown(), "the pin goes away with the game's navigation")
    -- it finds the navigation frame by itself too, without the event (and comes back after hiding)
    alice.navFrame = navFrame
    drive._scripts.OnUpdate(drive, 0.6)
    drive._scripts.OnUpdate(drive, 0.1)
    check(pinFrame:IsShown(), "it picks the navigation frame up on its own and shows again")
    alice.navFrame = nil
    drive._scripts.OnUpdate(drive, 0.6)
    Server:Advance(4)
    tr.nav._scripts.OnUpdate(tr.nav, 3.5)
    check(alice.trackedQuest == nil and alice.waypoint and alice.waypoint.uiMapID == 1411, "no navigation for the quest: back to a waypoint on the spot")
    pf:Advance(-1)
    alice.logIds = nil
    -- the tracker's Clear button leaves the route without starting another
    tr.clear._scripts.OnClick(tr.clear)
    check(alice.env.RUIN_PathfinderCharDB.route == nil and not tr:IsShown()
          and alice.env.RUIN_API.Map:GetPins("Pathfinder").step == nil, "Clear leaves the route, hides the tracker and drops the pin")
    check(alice.waypoint == nil, "and clears the waypoint Pathfinder placed")
    alice.env.SlashCmdList.RUINPATH("clear")
    pf:StartRoute("vot")
    tr = alice.env.RUIN_PathfinderTracker
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
    check(eve.env.RUIN_PathfinderTracker.title:GetText():find("following Alice"), "tracker says who she follows")
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
    -- "Equip: Increases damage and healing done by magical spells..." counts for casters
    local IS = alice.mns.RUIN_Codex.ItemStats
    local st = {}
    check(IS.ParseLine("Equip: Increases damage and healing done by magical spells and effects by up to 12.", st) and st.SP == 12 and st.HEAL == 12,
        "spell damage and healing lines are read")
    local st2 = {}
    IS.ParseLine("+7 Shadow Spell Damage", st2)
    IS.ParseLine("Equip: Improves your chance to get a critical strike with spells by 1%.", st2)
    check(st2.SP_SHADOW == 7 and st2.CRIT == 14, "school damage and crit percent lines too")
    -- every wording of spell damage and healing bonuses
    local cases = {
        { "Equip: Increases healing done by spells and effects by up to 22.", 0, 22 },
        { "Equip: Increases healing done by magical spells and effects by up to 33.", 0, 33 },
        { "Equip: Increases healing done by up to 44 and damage done by up to 15 for all magical spells and effects.", 15, 44 },
        { "Equip: Increases damage done by magical spells and effects by up to 9.", 9, 0 },
        { "Equip: Increases spell damage by up to 11.", 11, 0 },
        { "Equip: Increases spell power by 14.", 14, 14 },
        { "+7 Damage and Healing Spells", 7, 7 },
        { "+11 Healing Spells", 0, 11 },
        { "+13 Spell Damage", 13, 0 },
        { "Spell Damage and Healing +30", 30, 30 },
        { "Enchanted: +30 Spell Damage and Healing", 30, 30 },
        { "Healing Spells +55", 0, 55 },
        { "|cff00ff00Equip: Increases damage and healing done by magical spells and effects by up to 1,024.|r", 1024, 1024 },
        { "Equip: Increases damage and healing done by magical spells and effects of all party members within 30 yards by up to 33.", 33, 33 },
        { "Equip: Increases the damage and healing of your spells by up to 9.", 9, 9 },
        { "Equip: Increases the healing of your spells by up to 18.", 0, 18 },
    }
    local allRead = true
    for _, c in ipairs(cases) do
        local t = {}
        local ok = IS.ParseLine(c[1], t)
        if not (ok and (t.SP or 0) == c[2] and (t.HEAL or 0) == c[3]) then
            allRead = false
            print("       not read right: " .. c[1] .. " -> SP " .. tostring(t.SP) .. ", HEAL " .. tostring(t.HEAL))
        end
    end
    check(allRead, "spell damage and healing bonuses are read in every wording (" .. #cases .. " cases)")
    local t3 = {}
    check(IS.ParseLine("Equip: Increases the damage done by Frost spells and effects by up to 12.", t3) and t3.SP_FROST == 12 and not t3.SP,
        "a one-school bonus in other words is that school's damage")
    local t4 = {}
    check(not IS.ParseLine("Equip: Improves your chance to get a critical strike with spells by 1%.", t4) or not t4.SP, "crit lines are not spell damage")
    check(not IS.ParseLine("Use: Increases damage and healing done by magical spells and effects by up to 175 for 20 sec.", {}),
        "Use: effects are not counted as stats")
    check(not IS.ParseLine("Equip: Increases the healing of your Lesser Healing Wave spell by 20.", {}), "one spell's modifier is not general healing")

    -- end to end: a robe whose spell damage is only on its tooltip is an upgrade for a caster
    local env = alice.env
    local realClass, realStats, realTip, realLink = env.UnitClass, env.GetItemStats, env.C_TooltipInfo, env.GetInventoryItemLink
    env.UnitClass = function() return "Mage", "MAGE" end
    alice.env.RUIN_CodexDB.spec = "Fire"
    env.GetItemInfoInstant = function() return 0, "Armor", "Cloth", "INVTYPE_ROBE" end
    env.GetInventoryItemLink = function() return "|cff1eff00|Hitem:300::|h[Old Robe]|h|r" end
    env.GetItemStats = function(link)
        if tostring(link):find("item:301") then return { ITEM_MOD_INTELLECT_SHORT = 8 } end      -- the API misses its Equip: line
        if tostring(link):find("item:302") then return { ITEM_MOD_INTELLECT_SHORT = 8, ITEM_MOD_SPELL_HEALING_DONE = 40 } end
        return { ITEM_MOD_INTELLECT_SHORT = 12 }
    end
    env.C_TooltipInfo = { GetHyperlink = function(link)
        if tostring(link):find("301") then
            return { lines = { { leftText = "Robe of the Magi" }, { leftText = "+8 Intellect" },
                { leftText = "Equip: Increases damage and healing done by magical spells and effects by up to 20." } } }
        end
        return { lines = { { leftText = "Robe" }, { leftText = "+12 Intellect" } } }
    end }
    alice.mns.RUIN_Codex.ItemStats.Forget()
    local pct = cx:Compare("|cff1eff00|Hitem:301::|h[Robe of the Magi]|h|r")
    check(type(pct) == "number" and pct > 50 and cx:IsUpgrade(301) == true, "a robe with +20 spell damage on its tooltip beats +12 Intellect for a Fire mage (" .. tostring(pct) .. ")")
    check(cx:IsUpgrade(302) == false, "healing on a Fire mage's robe doesn't make it an upgrade")
    alice.env.RUIN_CodexDB.spec = "Auto"
    env.UnitClass = function() return "Priest", "PRIEST" end
    alice.env.RUIN_CodexDB.spec = "Holy"
    alice.mns.RUIN_Codex.ItemStats.Forget()
    check(cx:IsUpgrade(302) == true and cx:IsUpgrade(301) == true, "for a Holy priest both the healing and the damage-and-healing robe are upgrades (the long API name counts too)")
    alice.env.RUIN_CodexDB.spec = "Auto"
    env.UnitClass, env.GetItemStats, env.C_TooltipInfo, env.GetInventoryItemLink = realClass, realStats, realTip, realLink
    env.GetItemInfoInstant = function() return 0, "Armor", "Plate", "INVTYPE_HEAD" end
    alice.mns.RUIN_Codex.ItemStats.Forget()

    -- the ranged slot: wands, bows, guns and thrown count their damage per second
    do
        local items = {   -- id -> equip slot, stats from the item API, tooltip lines
            [401] = { "INVTYPE_RANGEDRIGHT", { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 14.5 } },                 -- wand, no stats
            [402] = { "INVTYPE_RANGEDRIGHT", { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 9.0 } },                  -- weaker wand
            [403] = { "INVTYPE_RANGED", { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 20.0, ITEM_MOD_AGILITY_SHORT = 3 } },  -- bow
            [404] = { "INVTYPE_RANGED", { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 15.0, ITEM_MOD_AGILITY_SHORT = 3 } },  -- older bow
            [405] = { "INVTYPE_RANGEDRIGHT", {}, { "Lesser Magic Wand", "(11.3 damage per second)" } },    -- dps only on the tooltip
            [406] = { "INVTYPE_THROWN", { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 12.0 } },
        }
        local worn = {}   -- slot -> id
        local function idOf(link) return tonumber(tostring(link):match("item:(%d+)")) end
        local saved = { env.UnitClass, env.GetItemStats, env.C_TooltipInfo, env.GetInventoryItemLink, env.GetItemInfoInstant }
        env.GetItemInfoInstant = function(link) local it = items[idOf(link) or 0]; return idOf(link), "Weapon", "", it and it[1] or "INVTYPE_HEAD" end
        env.GetItemStats = function(link) local it = items[idOf(link) or 0]; return it and it[2] or {} end
        env.C_TooltipInfo = { GetHyperlink = function(link)
            local it = items[idOf(link) or 0]
            local lines = {}
            for _, l in ipairs(it and it[3] or { "Item" }) do lines[#lines + 1] = { leftText = l } end
            return { lines = lines }
        end }
        env.GetInventoryItemLink = function(_, slot) return worn[slot] and ("|cffffffff|Hitem:" .. worn[slot] .. "::|h[x]|h|r") or nil end
        local function as(class, spec) env.UnitClass = function() return class, class:upper() end; alice.env.RUIN_CodexDB.spec = spec; alice.mns.RUIN_Codex.ItemStats.Forget() end

        as("Mage", "Frost")
        check(cx:Compare(401) == "empty" and cx:IsUpgrade(401) == true, "a wand with no stats is an upgrade for a mage with nothing in the ranged slot")
        worn[18] = 402
        local pct = cx:Compare(401)
        check(type(pct) == "number" and math.floor(pct + 0.5) == 61, "a 14.5 DPS wand is +61% over a 9 DPS wand for a mage (" .. tostring(pct) .. ")")
        check(cx:IsUpgrade(402) == false, "the wand you wear is not an upgrade over itself")
        pct = cx:Compare(405)
        check(type(pct) == "number" and pct > 0, "a wand whose damage is only on its tooltip line is read too (" .. tostring(pct) .. ")")
        as("Hunter", "Marksmanship")
        worn[18] = 404
        pct = cx:Compare(403)
        check(type(pct) == "number" and pct > 25, "a hunter's better bow is a clear upgrade over the ranged slot (" .. tostring(pct) .. ")")
        local W = alice.mns.RUIN_Codex.SpecWeights
        check(W.HUNTER.Marksmanship.RDPS > W.HUNTER.Marksmanship.DPS * 3, "hunters weigh their ranged weapon's damage far above their melee weapon's")
        as("Warrior", "Arms")
        pct = cx:Compare(403)
        check(type(pct) == "number" and pct > 0, "a warrior's better bow is still an upgrade for the ranged slot (" .. tostring(pct) .. ")")
        worn[18] = nil
        check(cx:Compare(406) == "empty", "thrown weapons go in the ranged slot")
        local ws = W.WARRIOR.Arms
        check(ws.RDPS and ws.RDPS < ws.DPS / 5, "warriors weigh a ranged weapon's damage low: it only pulls")
        local missing = {}
        for class, specs in pairs(W) do
            for spec, w in pairs(specs) do
                local wands = class == "MAGE" or class == "WARLOCK" or class == "PRIEST"
                local guns = class == "HUNTER" or class == "WARRIOR" or class == "ROGUE"
                if (wands or guns) and not w.RDPS then missing[#missing + 1] = class .. " " .. spec end
            end
        end
        check(#missing == 0, "every spec that can use a ranged weapon has a ranged weight (" .. table.concat(missing, ", ") .. ")")
        local S = cx.SLOTS
        local all = true
        for _, loc in ipairs({ "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CHEST", "INVTYPE_ROBE", "INVTYPE_WAIST",
            "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_FINGER", "INVTYPE_TRINKET", "INVTYPE_CLOAK",
            "INVTYPE_WEAPON", "INVTYPE_2HWEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND", "INVTYPE_SHIELD",
            "INVTYPE_HOLDABLE", "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN", "INVTYPE_RELIC" }) do
            if not S[loc] then all = false; print("       no slot for " .. loc) end
        end
        check(all and S.INVTYPE_RANGED[1] == 18 and S.INVTYPE_RANGEDRIGHT[1] == 18 and S.INVTYPE_RELIC[1] == 18, "every gear slot is checked, the ranged slot included (18 on Forever)")
        env.UnitClass, env.GetItemStats, env.C_TooltipInfo, env.GetInventoryItemLink, env.GetItemInfoInstant = saved[1], saved[2], saved[3], saved[4], saved[5]
        alice.env.RUIN_CodexDB.spec = "Auto"
        alice.mns.RUIN_Codex.ItemStats.Forget()
    end
    -- boss loot in the Journal: the sample list, marked with what RUIN looted
    eve.instance = "The Deadmines"
    Server.fire(eve, "CHAT_MSG_LOOT", "You receive loot: |cff0070dd|Hitem:5191::::::::|h[Cruel Barb]|h|r.", "Eve Ember")
    Server:Advance(3)
    local CN = cara.mns.RUIN_Codex
    local dm
    for _, d in ipairs(CN.Dungeons) do if d.id == "dm" then dm = d end end
    local loot = CN.Loot.For(dm)
    local vc
    for _, b in ipairs(loot.bosses) do if b.name == "Edwin VanCleef" then vc = b end end
    check(vc and #vc.items == 4 and vc.items[2].id == 5191 and not loot.verified, "the Deadmines sample lists VanCleef's loot, unverified")
    check(cara.env.RUIN_CodexDB.drops["The Deadmines"][5191], "Eve's drop reached Cara")
    -- another addon adds a loot list; malformed entries are skipped
    local ok = cara.env.RUIN_API:GetModule("Codex"):AddLoot("Shadowfang Keep", { source = "test", verified = true,
        bosses = { ["Rethilgore"] = { 6220, "junk", { 6641, 12.5 } } } })
    local sfk
    for _, d in ipairs(CN.Dungeons) do if d.id == "sfk" then sfk = d end end
    local l2 = CN.Loot.For(sfk)
    check(ok and l2.verified and l2.bosses[1].name == "Rethilgore" and #l2.bosses[1].items == 2 and l2.bosses[1].items[2].chance == 12.5,
        "AddLoot takes a list by instance name and skips what isn't an item")
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
    check(table.concat(lines, "\n"):find("AH 7%-day avg:"), "tooltip shows the 7-day trend")
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
