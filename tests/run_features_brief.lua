-- RUIN 0.3.1 tests: the RUIN Companion brief's look and features
-- (tabs, Guild page, community links, Overlord, Gear Path, leveling checklist,
-- class track, recorder). Runs after run_features_more.lua and shares T.
local alice, cara, eve, check, chatHas, errorsSoFar = T.alice, T.cara, T.eve, T.check, T.chatHas, T.errorsSoFar

print("RUIN window and tabs (brief layout)")
do
    local labels = alice.ns.UI:TabLabels()
    check(table.concat(labels, ",") == "Codex,Pathfinder,Guild,Finder,Muster,Intel,Exchange,Settings",
        "tabs carry module names: Codex, Pathfinder, Guild ... Settings (" .. table.concat(labels, ",") .. ")")
    local R = alice.env.RUIN_API
    check(R:OpenTab("Codex") and R:OpenTab("Pathfinder") and R:OpenTab("Muster"), "module pages open by name")
    check(R.appName == "RUIN Gaming Companion App" and alice.ns.APP_NAME == "RUIN Gaming Companion App", "the app is named RUIN Gaming Companion App")
    check(R:OpenTab("Guild") and R:OpenTab("Org") and R:OpenTab("Settings"), "Guild (alias Org) and Settings open")
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
    alice.env.RUIN_API:OpenTab("Guild")
    alice.ns.UI:Refresh()
    errorsSoFar("guild page")
end

print("Gear Path (Codex)")
do
    local cx = alice.env.RUIN_API:GetModule("Codex")
    local src = cx.ParseSource("quest 15m Duskwood")
    check(src and src.k == "quest" and src.m == 15 and src.z == "Duskwood", "officer source note parses")
    cx:SetBis("WARRIOR", "Arms", "1-29", 1, 100, src)
    cx:SendBis("WARRIOR", "Arms", "1-29")
    Server:Advance(4)
    local list = cara.env.RUIN_CodexDB.bis["WARRIOR:Arms:1-29"]
    check(list and list.src and list.src[1] and list.src[1].m == 15, "the source and minutes reached Cara")

    local ccx = cara.env.RUIN_API:GetModule("Codex")
    local path, sum = ccx:GearPath()
    local byId = {}
    for _, e in ipairs(path) do byId[e.id] = e end
    local helm, barb = byId[100], byId[5191]
    check(helm and helm.kind == "quest" and helm.minutes == 15 and helm.tag == "Quick" and not helm.estimated,
        "the BiS helm: quest, 15 minutes, Quick, officer-set")
    check(helm and helm.confidenceLabel == "High", "officer-set source counts as high confidence")
    check(barb and barb.kind == "dungeon" and barb.tag == "Medium" and barb.solo == false and barb.estimated,
        "the Deadmines drop: dungeon, Medium, needs a group, estimated time")
    check(path[1] and path[1].id == 100, "time efficient puts the quick quest reward first")
    local solo = ccx:GearPath({ group = false })
    local hasBarb = false
    for _, e in ipairs(solo) do if e.id == 5191 then hasBarb = true end end
    check(not hasBarb, "Solo only hides the dungeon drop")
    local groupOnly = ccx:GearPath({ solo = false })
    check(groupOnly[1] and groupOnly[1].id == 5191 and #groupOnly == 1, "Group only shows just the dungeon drop")
    check(sum.total == 1 and sum.collected == 0 and sum.next and sum.next.id == 100, "collected 0/1, next upgrade named")
    check(ccx.TimeTag(10) == "Quick" and ccx.TimeTag(45) == "Medium" and ccx.TimeTag(60) == "Long", "Quick / Medium / Long thresholds")
    -- an old 0.3.0 list without sources still ranks, with estimated times
    cara.env.RUIN_CodexDB.bis["WARRIOR:Arms:1-29"].src = nil
    local again = ccx:GearPath()
    local h2
    for _, e in ipairs(again) do if e.id == 100 then h2 = e end end
    check(h2 and h2.kind == "unknown" and h2.estimated, "lists without sources still work, marked as estimates")
    T.openAllSubTabs(cara, "Codex")
    cara.env.SlashCmdList.RUINCODEX("path")
    cara.env.SlashCmdList.RUINCODEX("journal")
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
    alice.env.QuestieLoader = { ImportModule = function(_, name)
        if name == "QuestieDB" then
            return { GetQuest = function(id) return id == 176 and { Starts = { NPC = { 68 } }, Finisher = { Id = 69 } } or nil end,
                     GetNPC = function(id) return { spawns = { [12] = { { id == 68 and 42.1 or 45.0, 65.5 } } } } end }
        end
        return { GetUiMapIdByAreaId = function() return 1429 end }
    end }
    local spot = pf.QuestieSpot(176, "start")
    check(spot and spot.map == 1429 and math.abs(spot.x - 0.421) < 0.001, "Questie gives the quest giver's spot")
    local fin = pf.QuestieSpot(176, "finish")
    check(fin and math.abs(fin.x - 0.45) < 0.001, "and where it's handed in")
    local shared = alice.env.RUIN_API.Util.Decode("ROUTE", alice.env.RUIN_API.Util.Encode("ROUTE", { title = "t", steps = { last } }))
    local back = cara.env.RUIN_API:GetModule("Pathfinder"):ImportRoute(alice.env.RUIN_API.Util.Encode("ROUTE", shared))
    check(back and back.steps[1].qid == 176 and back.steps[1].t == nil, "shared routes keep quest IDs but not recorded times")
    pf:SetRecording(false)
    check(not alice.env.RUIN_PathfinderRecBadge:IsShown(), "badge hides when recording stops")
    T.openAllSubTabs(alice, "Pathfinder")
    errorsSoFar("leveling")
end
