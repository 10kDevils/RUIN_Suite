-- RUIN 0.3.1 tests: the RUIN Companion brief's look and features
-- (tabs, Guild page, community links, Overlord, Gear Path, leveling checklist,
-- class track, recorder). Runs after run_features_more.lua and shares T.
local alice, cara, eve, check, chatHas, errorsSoFar = T.alice, T.cara, T.eve, T.check, T.chatHas, T.errorsSoFar

print("RUIN window and tabs (brief layout)")
do
    local labels = alice.ns.UI:TabLabels()
    check(table.concat(labels, ",") == "Guild,Finder,Muster,Pathfinder,Codex,Exchange,Options",
        "tabs in order: Guild, Finder, Muster, Pathfinder, Codex, Exchange, Options (" .. table.concat(labels, ",") .. ")")
    local R = alice.env.RUIN_API
    check(R:OpenTab("Codex") and R:OpenTab("Pathfinder") and R:OpenTab("Muster"), "module pages open by name")
    check(R.appName == "RUIN Gaming Companion App" and alice.ns.APP_NAME == "RUIN Gaming Companion App", "the app is named RUIN Gaming Companion App")
    check(R:OpenTab("Guild") and R:OpenTab("Org") and R:OpenTab("Settings") and R:OpenTab("Options") and R:OpenTab("Finder") and R:OpenTab("Muster"), "Guild (alias Org), Settings/Options, and modules open by name")
    alice.env.SlashCmdList.RUIN("settings")
    alice.env.SlashCmdList.RUIN("guild")
    check(R.apiLevel >= 4 and R:GetClient() == "forever", "API level 4 and the client is detected as WoW Forever")
    local found = false
    for _, line in ipairs(alice.chat) do if line:find("[RUIN]", 1, true) then found = true end end
    check(found, "chat lines use the [RUIN] tag")
    errorsSoFar("window and tabs")
end

print("Widgets from the brief")
do
    local W = alice.env.RUIN_API.Widgets
    local p = W.Pill(alice.env.UIParent, 60)
    p:SetTag("Quick")
    check(p.text:GetText() == "Quick", "a pill shows its tag")
    check(W.TagText("Long"):find("Long"), "tag text for list lines")
    local bar = W.Progress(alice.env.UIParent, 200, 8)
    bar:SetValue(4 / 6)
    check(math.abs(bar.value - 4 / 6) < 0.001, "progress bar keeps its value")
    local b = W.Button(alice.env.UIParent, "Solo", 70)
    b:LockHighlight()
    check(b.locked == true and b:GetText() == "Solo", "buttons lock as selected and keep their text")
    check(W.MARKERS.quest and W.MARKERS.turnin and W.MARKERS.class, "one marker color set for the whole suite")
    errorsSoFar("widgets")
end

print("Guild page: links, roster, Overlord")
do
    local Org = alice.ns.Org
    local list = Org.ParseLinks("Discord = https://discord.gg/ruin\nWebsite = https://ruin.example\nnot a link line")
    check(#list == 2 and list[1].label == "Discord", "links parse from Name = address lines")
    local revBefore = Org:Get().rev
    local ok = Org:SetLinks(list)
    Server:Advance(20)
    check(ok and alice.ns.Org:Get().rev == revBefore + 1, "the admin's links bump the key")
    local cl = cara.ns.Org:GetLinks()
    check(#cl == 2 and cl[2].url == "https://ruin.example", "links reached Cara with the key")
    local el = eve.ns.Org:GetLinks()
    check(#el == 2, "and Eve, a member of another guild")
    local ok2, err = cara.ns.Org:SetLinks({ { label = "Spam", url = "x" } })
    check(not ok2 and err, "only the org admin sets links")
    check(alice.ns.Escape("a|cffff0000b") == "a||cffff0000b", "player text is escaped before display")

    local rows, counts = alice.ns.UI:GuildRows()
    local sawCara = false
    for _, r in ipairs(rows) do if r.name and r.name:find("Cara") and r.tag == "Briar" then sawCara = true end end
    check(sawCara and counts.ruin >= 3, "roster lists RUIN members of other guilds with their tag")

    check(alice.ns.UI:FindOverlord() == nil, "no Overlord installed")
    local opened = false
    alice.env.SLASH_OVERLORD1 = "/ov"
    alice.env.SlashCmdList.OVERLORD = function(msg) opened = msg end
    Server:Advance(31)
    check(alice.ns.UI:FindOverlord() ~= nil, "Overlord found by its /ov command")
    alice.ns.UI:OpenOverlord()
    check(opened == "show", "Open runs /ov show")
    check(alice.env.RUIN_API:HasOverlord(), "modules can ask whether Overlord is installed")
    -- found through the AddOns list even when no /ov command can be seen (0.3.8)
    local addons = { { "Overlord", "|cffff4040Overlord|r Forever", true, nil } }
    local function stubAddOns(env)
        env.C_AddOns = {
            GetNumAddOns = function() return #addons end,
            GetAddOnInfo = function(i) local a = addons[i]; return a[1], a[2], "", true, a[4] end,
            IsAddOnLoaded = function(i) return addons[i][3] end,
            GetAddOnMetadata = env.GetAddOnMetadata,
        }
    end
    stubAddOns(cara.env)
    check(cara.ns.UI:OverlordState() == "loaded" and cara.env.RUIN_API:HasOverlord(), "Overlord in the AddOns list and loaded counts as installed without /ov")
    stubAddOns(eve.env)
    addons[1][3], addons[1][4] = false, "DISABLED"
    check(eve.ns.UI:OverlordState() == "off" and not eve.env.RUIN_API:HasOverlord(), "switched off in the AddOns list: installed, not loaded")
    eve.chat = {}
    eve.ns.UI:OpenOverlord()
    check(chatHas(eve, "not loaded"), "Open explains it is switched off")
    eve.env.SlashCmdList.RUIN("overlord")
    check(chatHas(eve, "AddOns list entry") and chatHas(eve, "installed, not loaded"), "/ruin overlord reports what RUIN sees")
    addons[1][3], addons[1][4] = true, nil
    check(eve.ns.UI:OverlordState() == "loaded", "turned on: loaded")
    alice.env.RUIN_API:OpenTab("Guild")
    alice.ns.UI:Refresh()
    errorsSoFar("guild page")
end

print("Codex 0.3.10: gear tracking left for a gear addon")
do
    local cx = cara.env.RUIN_API:GetModule("Codex")
    check(cx.GearPath == nil and cx.SetBis == nil, "Gear Path and best-in-slot lists are gone")
    cara.env.SlashCmdList.RUINCODEX("path")
    check(chatHas(cara, "have left Codex"), "/codex path says where they went")
    cara.env.SlashCmdList.RUINCODEX("journal")
    T.openAllSubTabs(cara, "Codex")
    errorsSoFar("gear path")
end

print("Leveling (Pathfinder)")
do
    local pf = alice.env.RUIN_API:GetModule("Pathfinder")
    alice.chat = {}
    pf:StartRoute("vot")
    check(chatHas(alice, "Waypoint set:") and chatHas(alice, "yards"), "starting a route announces the waypoint in yards")
    -- recorder: badge, mark, level-ups and gear
    pf:SetRecording(true)
    check(alice.env.RUIN_PathfinderRecBadge and alice.env.RUIN_PathfinderRecBadge:IsShown(), "Recording: ON badge shows")
    alice.env.SlashCmdList.RUINPATH("mark Kill Gorlash at the shore")
    local steps = alice.env.RUIN_PathfinderDB.rec.steps
    local last = steps[#steps]
    check(last and last.act == "note" and last.text == "Kill Gorlash at the shore" and last.t, "/path mark keeps the note's case and a timestamp")
    Server.fire(alice, "PLAYER_LEVEL_UP", 12)
    last = steps[#steps]
    check(last and last.text == "Reached level 12" and last.level == 12, "level-ups are recorded")
    check(chatHas(alice, "Level 12: new spells"), "trainer reminder on an even level")
    Server.fire(alice, "CHAT_MSG_LOOT", "You receive item: |cff0070dd|Hitem:100::|h[New Helm]|h|r.", "Alice Ash")
    last = steps[#steps]
    check(last and last.item == 100 and last.text:find("New Helm"), "gear received while recording becomes a step with its item")
    alice.env.SlashCmdList.RUINPATH("rec")
    check(chatHas(alice, "Recorder ") , "/path rec prints the recorder status")
    -- class and trainer steps survive sharing
    local s = alice.env.RUIN_API.Util.Encode("ROUTE", { title = "Warlock 1-10 (test)", steps = {
        { act = "class", quest = "Class test quest" }, { act = "trainer", text = "Train at level 4" } } })
    local r = cara.env.RUIN_API:GetModule("Pathfinder"):ImportRoute(s)
    check(r and #r.steps == 2 and r.steps[1].act == "class" and r.steps[2].act == "trainer", "class quest and trainer steps import")
    -- quest IDs are recorded, and Questie (when installed) places accept and turn-in steps
    alice.questTitles[176] = "Wanted: Hogger"
    Server.fire(alice, "QUEST_ACCEPTED", 176)
    last = steps[#steps]
    check(last and last.act == "accept" and last.qid == 176, "accepting a quest records its ID")
    T.fakeQuestie(alice, { quests = { [176] = { name = "Wanted: Hogger", level = 11, starts = { 68 }, ends = { 69 } } },
        npcs = { [68] = { name = "Wanted poster", spawns = { [12] = { { 42.1, 65.5 } } } },
                 [69] = { name = "Marshal Dughan", spawns = { [12] = { { 45.0, 65.5 } } } } }, area = { [12] = 1429 } })
    local QB = alice.mns.RUIN_Pathfinder.QB
    local spot = QB.Spot(176, "start")
    check(spot and spot.map == 1429 and math.abs(spot.x - 0.421) < 0.001, "Questie gives the quest giver's spot")
    local fin = QB.Spot(176, "finish")
    check(fin and math.abs(fin.x - 0.45) < 0.001, "and where it's handed in")
    alice.env.QuestieLoader, alice.env.Questie = nil, nil
    QB.Forget()
    local shared = alice.env.RUIN_API.Util.Decode("ROUTE", alice.env.RUIN_API.Util.Encode("ROUTE", { title = "t", steps = { last } }))
    local back = cara.env.RUIN_API:GetModule("Pathfinder"):ImportRoute(alice.env.RUIN_API.Util.Encode("ROUTE", shared))
    check(back and back.steps[1].qid == 176 and back.steps[1].t == nil, "shared routes keep quest IDs but not recorded times")
    pf:SetRecording(false)
    check(not alice.env.RUIN_PathfinderRecBadge:IsShown(), "badge hides when recording stops")
    T.openAllSubTabs(alice, "Pathfinder")
    errorsSoFar("leveling")
end

print("Page colors and controls (Core 0.3.12)")
do
    local W = alice.env.RUIN_API.Widgets
    local themes = alice.ns.THEMES
    check(W.SchemeFor(themes.Guild).core and W.SchemeFor(themes.Settings).core, "Guild and Options keep RUIN's own colors")
    local fs = W.SchemeFor(themes.Finder)
    check(not fs.core and fs.accent[1] > fs.accent[3], "a module page takes its addon's color (Finder is pink)")
    check(W.SchemeFor(themes.Muster) ~= W.SchemeFor(themes.Codex), "each module has its own scheme")
    -- a widget finds its page's colors through its parents
    local page = alice.env.CreateFrame("Frame")
    page.ruinTheme = themes.Muster
    local child = alice.env.CreateFrame("Frame")
    child.GetParent = function() return page end
    check(W.ThemeOf(child) == themes.Muster, "widgets find their page's theme")
    -- check box label hides with the box; placeholder text
    local c = W.Check(page, "Test", function() return true end, function() end)
    check(c.label and c.mark, "RUIN-style check box with a label")
    local e = W.EditBox(page, 100, nil, "Type here")
    check(e.hint and e.hint:GetText() == "Type here", "text boxes carry a hint")
    local b = W.Cycle(page, 100, { "A", "B" }, function() return "A" end, function() end, "Pick: ")
    b.format = function(v) return v .. "!" end
    b:Refresh()
    check(b:GetText() == "Pick: A!", "choice buttons can format their value")
    local btn = W.Button(page, "Alerts", 80)
    local pop = W.Popover(btn, 200, 100, "Alert me for")
    check(pop and not pop:IsShown(), "popover starts closed")
    btn._scripts.OnClick(btn)
    check(pop:IsShown(), "its button opens it")
    -- Options shows members only what they can use
    eve.env.RUIN_API:OpenTab("Options")
    alice.env.RUIN_API:OpenTab("Options")
    errorsSoFar("page colors")
end

print("Tab order (Options) and the Codex journal (Core 0.3.13, Codex 0.3.9)")
do
    local UI = alice.ns.UI
    check(table.concat(UI:TabLabels(), ",") == "Guild,Finder,Muster,Pathfinder,Codex,Exchange,Options", "usual tab order")
    check(UI:MoveTab("Muster", -1) and UI:MoveTab("Muster", -1), "Muster moved to the front")
    check(table.concat(UI:TabLabels(), ",") == "Muster,Guild,Finder,Pathfinder,Codex,Exchange,Options", "tab strip follows your order")
    check(alice.env.RUIN_DB.settings.tabOrder[1] == "Muster", "order saved in RUIN Core's settings")
    check(not UI:MoveTab("Muster", -1), "can't move past the first place")
    check(not UI:MoveTab("Settings", -1), "Options stays last")
    alice.env.SlashCmdList.RUIN("tabs reset")
    check(table.concat(UI:TabLabels(), ",") == "Guild,Finder,Muster,Pathfinder,Codex,Exchange,Options" and alice.env.RUIN_DB.settings.tabOrder == nil, "/ruin tabs reset restores it")
    -- Codex: Journal last, dungeons and raids both plan runs in Muster
    local cx = alice.env.RUIN_API:GetModule("Codex")
    local dg = alice.mns.RUIN_Codex.Dungeons[1]
    local ev = cx:PlanRun(dg, os.date("%Y-%m-%d %H:%M", os.time() + 2 * 86400), nil, false)
    check(ev and ev.kind == "Dungeon" and ev.size == 5 and ev.need[1] == 1 and ev.need[3] == 3, "a dungeon run posts to Muster as a 5-player event")
    local raid = alice.mns.RUIN_Codex.Raids[1]
    local rv = cx:PlanRun(raid, os.date("%Y-%m-%d %H:%M", os.time() + 3 * 86400), 40, true)
    check(rv and rv.kind == "Raid" and rv.size == 40, "a raid run keeps its size")
    alice.env.SlashCmdList.RUINCODEX("raids")
    alice.env.SlashCmdList.RUINCODEX("deadmines")
    T.openAllSubTabs(alice, "Codex")
    errorsSoFar("tab order and journal")
end

print("Pathfinder: officer routes (Pathfinder 0.3.12)")
do
    local pa, pc, pe = alice.env.RUIN_API:GetModule("Pathfinder"), cara.env.RUIN_API:GetModule("Pathfinder"), eve.env.RUIN_API:GetModule("Pathfinder")
    check(alice.env.RUIN_API:IsOfficerName("Cara Cole") and not alice.env.RUIN_API:IsOfficerName("Nobody Here"), "Core tells officers apart")
    check(#alice.mns.RUIN_Pathfinder.Routes >= 14, "the new Alliance routes are built in (" .. #alice.mns.RUIN_Pathfinder.Routes .. ")")

    local r = pa:PublishRoute("elwynn_1_10")
    Server:Advance(40)
    check(r and r.official and not r.official.approved, "an officer publishes a route")

    local got = eve.env.RUIN_PathfinderDB.official[r.id]
    check(got and got.official and got.official.by == "Alice Ash" and #got.steps == #r.steps and got.builtin == "elwynn_1_10", "it reaches a member with the officer mark")
    -- a member can't publish, and a member's message is ignored
    check(pe:PublishRoute("westfall_10_15") == nil, "members can't publish")
    eve.env.RUIN_API:GetModule("Pathfinder"):Send("OFFICIAL", { id = "ofake", title = "Fake", steps = { { act = "note", text = "x" } }, ot = os.time() }, "ORG")
    Server:Advance(40)
    check(cara.env.RUIN_PathfinderDB.official.ofake == nil, "a non-officer's route push is ignored")
    -- approving a shared route
    eve.env.RUIN_PathfinderDB.custom.cme = { id = "cme", title = "Eve's Duskwood", author = "Eve Ember", steps = { { act = "note", text = "go" } } }
    pe:ShareRoute("cme")
    Server:Advance(40)
    local inbox = alice.env.RUIN_PathfinderDB.inbox[1]
    check(inbox and inbox.route.title == "Eve's Duskwood", "Alice got Eve's shared route")
    local copyId
    for id in pairs(alice.env.RUIN_PathfinderDB.custom) do copyId = id end
    local tmp = alice.mns.RUIN_Pathfinder
    local added = { title = inbox.route.title, author = "Eve Ember", steps = inbox.route.steps }
    alice.env.RUIN_PathfinderDB.custom.capprove = added; added.id = "capprove"
    local ap = pa:PublishRoute("capprove", "Eve Ember")
    Server:Advance(40)
    check(ap and ap.official.approved, "publishing a member's route marks it officer-approved")
    check(cara.env.RUIN_PathfinderDB.official[ap.id] and cara.env.RUIN_PathfinderDB.official[ap.id].official.approved, "approved route reaches everyone")
    -- withdraw
    pa:WithdrawRoute(r.id)
    Server:Advance(40)
    check(eve.env.RUIN_PathfinderDB.official[r.id] == nil, "withdrawn from everyone")
    T.openAllSubTabs(alice, "Pathfinder")
    T.openAllSubTabs(eve, "Pathfinder")
    errorsSoFar("officer routes")
end

print("Pathfinder: quest IDs, Questie and shared quests (Pathfinder 0.3.13)")
do
    local P = alice.mns.RUIN_Pathfinder
    local pa, pe = alice.env.RUIN_API:GetModule("Pathfinder"), eve.env.RUIN_API:GetModule("Pathfinder")
    -- every quest step of the Alliance routes carries its quest ID
    local missing = 0
    for _, r in ipairs(P.Routes) do
        if r.faction == "Alliance" and r.id ~= "zephras_1_12" then
            for _, s in ipairs(r.steps) do
                if (s.act == "accept" or s.act == "complete" or s.act == "turnin") and not s.qid then missing = missing + 1 end
            end
        end
    end
    check(missing == 0, "Alliance route quest steps all have quest IDs (" .. missing .. " without)")
    local function routeOf(id) for _, r in ipairs(P.Routes) do if r.id == id then return r end end end
    local rr = routeOf("redridge_15_22")
    local solomon
    for _, s in ipairs(rr.steps) do if s.qid == 120 and s.act == "accept" then solomon = s end end
    check(solomon and solomon.at and solomon.at.x < 27, "Redridge uses Forever's redrawn map (Magistrate Solomon at " .. tostring(solomon and solomon.at.x) .. ")")
    local wf = routeOf("westfall_10_15")
    check(wf.steps[2].qid == 36 and wf.steps[4].act == "turnin" and wf.steps[4].qid == 36, "Westfall Stew is delivered to Salma first")
    -- quests you've done tick themselves off
    local done = { [783] = true }
    alice.env.C_QuestLog.IsQuestFlaggedCompleted = function(id) return done[id] or false end
    alice.questLog = { { title = "Kobold Camp Cleanup", id = 7, complete = false } }
    pa:StartRoute("elwynn_1_10")
    local step = alice.env.RUIN_PathfinderCharDB.step
    check(step == 4, "a finished quest and one already in the log are skipped (step " .. step .. ")")
    pa:Advance(-1)
    Server.fire(alice, "QUEST_LOG_UPDATE")
    check(alice.env.RUIN_PathfinderCharDB.step == 3, "stepping back by hand isn't undone by the skipping")
    pa:Advance(1)
    check(alice.env.RUIN_PathfinderCharDB.step == 4, "and forward again works")
    -- shared quest status
    eve.questLog = { { title = "Kobold Camp Cleanup", id = 7, complete = true }, { title = "Brotherhood of Thieves", id = 18, complete = false } }
    pe:ShareQuests(true)
    pa:ShareQuests(true)
    Server:Advance(10)
    local have, ready = pa:WhoHas(7)
    check(#have == 1 and have[1] == "Eve Ember" and #ready == 1, "Alice sees Eve has Kobold Camp Cleanup, ready to hand in")
    local h2 = pe:WhoHas(7)
    check(#h2 == 1 and h2[1] == "Alice Ash", "and Eve sees Alice has it")
    -- Questie: a step without a place gets one, and a draft route for the zone
    T.fakeQuestie(alice, {
        quests = { [7] = { name = "Kobold Camp Cleanup", level = 2, starts = { 197 }, ends = { 197 }, zone = 12,
                           obj = { { Type = "monster", Id = 6, Text = "Kobold Vermin slain" } } },
                   [33] = { name = "Wolves Across the Border", level = 2, starts = { 196 }, ends = { 196 }, zone = 12,
                            obj = { { Type = "monster", Id = 299, Text = "Young Wolf" } } } },
        npcs = { [197] = { name = "Marshal McBride", spawns = { [12] = { { 48.9, 41.6 } } } },
                 [196] = { name = "Eagan Peltskinner", spawns = { [12] = { { 48.9, 40.2 } } } },
                 [6] = { name = "Kobold Vermin", spawns = { [12] = { { 48.9, 36.4 }, { 49.5, 36.1 } } } },
                 [299] = { name = "Young Wolf", spawns = { [12] = { { 46.4, 38.7 } } } } },
        area = { [12] = 1429 } })
    local QB = P.QB
    check(QB.Has() and QB.Quest(7).starts[1] == "Marshal McBride" and QB.Quest(7).objectives[1] == "Kobold Vermin slain", "Questie's quest details are read")
    alice.pos = { map = 1429, x = 0.48, y = 0.40 }
    local o = QB.Spot(7, "objective", 1429, 0.48, 0.40)
    check(o and math.abs(o.y - 0.361) < 0.01, "the nearest target spawn is found")
    alice.env.UnitLevel = function() return 2 end
    local draft = pa:DraftFromQuestie()
    check(draft and #draft.steps >= 5 and draft.steps[1].act == "accept" and draft.steps[#draft.steps].act == "turnin"
          and draft.steps[1].qid and alice.env.RUIN_PathfinderDB.custom[draft.id], "a route is drafted from Questie for the zone")
    -- the Quests page and tooltips
    alice.env.RUIN_API:OpenTab("Pathfinder")
    T.openAllSubTabs(alice, "Pathfinder")
    local tipLines = {}
    local tip = { AddLine = function(_, l) tipLines[#tipLines + 1] = l end }
    alice.mns.RUIN_Pathfinder.QB.Forget()
    errorsSoFar("pathfinder questie")
    alice.env.QuestieLoader, alice.env.Questie = nil, nil
    QB.Forget()
    alice.env.C_QuestLog.IsQuestFlaggedCompleted = nil
    alice.questLog = {}
    eve.questLog = {}
end

print("Muster: day list and hour / minute / AM-PM boxes (Core 0.3.15, Muster 0.3.8)")
do
    local W = alice.env.RUIN_API.Widgets
    local p = W.WhenPicker(alice.env.UIParent)
    local t = p:GetTime()
    local d = os.date("*t", t)
    local tm = os.date("*t", os.time() + 86400)
    check(d.hour == 20 and d.min == 0 and d.day == tm.day, "starts as tomorrow, 8:00 PM")
    check(p.day:GetText():match("^%a%a%a %d+/%d+$") and p.ampm:GetText() == "PM" and p.hour:GetText() == "8" and p.min:GetText() == "00",
        "the day reads like Wed 10/21 (" .. p.day:GetText() .. "), with hour, minute and PM")
    p.day:Open()
    check(p.day.menu:IsShown() and p.day.items[1]:GetText():find("^Today"), "the day list opens with Today first")
    p.day.items[3]._scripts.OnClick(p.day.items[3])
    p.hour:SetText("9"); p.min:SetText("30")
    p.ampm:Open(); p.ampm.items[1]._scripts.OnClick(p.ampm.items[1])
    local t2 = os.date("*t", p:GetTime())
    local in2 = os.date("*t", os.time() + 2 * 86400)
    check(t2.day == in2.day and t2.hour == 9 and t2.min == 30 and not p.day.menu:IsShown(), "picking a day and 9:30 AM gives that time")
    p.hour:SetText("13")
    check(p:GetTime() == nil, "an hour past 12 is refused")
    p.ampm:Open(); p.ampm.items[2]._scripts.OnClick(p.ampm.items[2]); p.hour:SetText("12"); p.min:SetText("00")
    check(os.date("*t", p:GetTime()).hour == 12, "12 PM is noon")
    -- the New event form posts at the picked time
    local mu = alice.mns.RUIN_Muster.MusterUI
    alice.env.RUIN_API:OpenTab("Muster")
    mu.formOpen = true
    mu.when.day.items = mu.when.day.items or {}
    mu.when:SetTime(os.time() + 3 * 86400)
    local before = 0
    for _ in pairs(alice.env.RUIN_MusterDB.events) do before = before + 1 end
    local post = mu.postBtn
    mu.titleBox:SetText("Picker test")
    post._scripts.OnClick(post)
    local ev
    for _, e in pairs(alice.env.RUIN_MusterDB.events) do if e.title == "Picker test" then ev = e end end
    check(ev and math.abs(ev.at - mu.when:GetTime()) < 1, "the form posts the event at the picked time")
    mu.when:SetTime(os.time() - 86400 * 0 - 3600)
    errorsSoFar("when picker")
end
