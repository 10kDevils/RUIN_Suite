-- RUIN module proof-of-concept tests
local here = arg[0]:match("^(.*)/") or "."
dofile(here .. "/harness.lua")

local pass, fail = 0, 0
local function check(cond, label)
    if cond then pass = pass + 1; print("  ok   " .. label)
    else fail = fail + 1; print("  FAIL " .. label) end
end
local function chatHas(c, needle)
    for _, line in ipairs(c.chat) do if line:find(needle, 1, true) then return true end end
    return false
end
local function errorsSoFar(label)
    check(#Server.errors == 0, label .. ": no Lua errors")
    for _, e in ipairs(Server.errors) do print("       " .. e) end
    Server.errors = {}
end

local MODULES = { "RUIN_Finder", "RUIN_Pathfinder", "RUIN_Codex", "RUIN_Exchange", "RUIN_Muster" }

Server.guilds["Ashen Order"] = { { name = "Alice Ash", rank = 0, guid = "Player-1-00000001" } }
Server.guilds["Briar Fang"] = {
    { name = "Cara Cole", rank = 0, guid = "Player-1-00000002" },
    { name = "Eve Ember", rank = 2, guid = "Player-1-00000004" },
}
local alice = Server:NewClient({ name = "Alice Ash", guid = "Player-1-00000001", guild = "Ashen Order", rank = 0, modules = MODULES })
local cara = Server:NewClient({ name = "Cara Cole", guid = "Player-1-00000002", guild = "Briar Fang", rank = 0, modules = MODULES })
local eve = Server:NewClient({ name = "Eve Ember", guid = "Player-1-00000004", guild = "Briar Fang", rank = 2, modules = MODULES })
Server:Advance(10)
errorsSoFar("load core + 5 modules")
check(#alice.env.RUIN_API:GetModules() == 5, "all 5 modules registered")

print("Org setup")
Server:Slash(alice, "key create RUIN")
Server:Slash(alice, "key addguild Briar Fang, 1, Briar")
alice.ns.Org:SendFullKey("Cara Cole")
Server:Advance(3)
cara.env.RUIN_ConfirmDialog.onAccept()
Server:Advance(90)
check(alice.ns.Comms:IsJoined("ORG") and cara.ns.Comms:IsJoined("ORG") and eve.ns.Comms:IsJoined("ORG"), "three clients connected")
errorsSoFar("org setup")

print("Finder")
alice.env.SlashCmdList.RUINFINDER("on dungeon")
Server:Advance(3)
eve.env.SlashCmdList.RUINFINDER("on dungeon")
Server:Advance(4)
check(chatHas(alice, "is also looking for Dungeon"), "Alice alerted that Eve is looking for the same activity")
alice.env.RUIN_API:OpenTab("Finder")
alice.env.RUIN_API:OpenTab("Finder")
errorsSoFar("finder")

print("Muster rally (Warfront's objectives, now in Muster)")
alice.pos = { map = 1411, x = 0.40, y = 0.40 }
alice.env.SlashCmdList.RUINMUSTER("rally Crossroads")
Server:Advance(2)
check(chatHas(cara, "Rally now: Crossroads"), "Cara alerted about the rally")
local rid
for id, ev in pairs(cara.env.RUIN_MusterDB.events) do if ev.title == "Crossroads" then rid = id end end
check(rid and cara.env.RUIN_MusterDB.events[rid].rally and cara.env.RUIN_API.Map:GetPins("Muster")[rid], "rally point pinned on Cara's map")
alice.env.RUIN_API:OpenTab("Muster")
errorsSoFar("muster rally")

print("Pathfinder")
local pf = alice.env.RUIN_API:GetModule("Pathfinder")
pf:StartRoute("vot")
alice.questTitles[4641] = "Your Place In The World"
Server.fire(alice, "QUEST_ACCEPTED", 4641)
check(alice.env.RUIN_PathfinderCharDB.step == 2, "accepting the quest advanced the route")
local tr = alice.env.RUIN_PathfinderTracker
check(tr and tr._scripts.OnUpdate ~= nil, "step change started the shimmer")
tr._scripts.OnUpdate(tr)
Server:Advance(2)
tr._scripts.OnUpdate(tr)
check(tr._scripts.OnUpdate == nil, "shimmer finished and stopped")
Server.fire(alice, "QUEST_TURNED_IN", 4641)
check(alice.env.RUIN_PathfinderCharDB.step == 3, "turning it in advanced again")
cara.env.RUIN_API:GetModule("Pathfinder"):StartRoute("vot")
Server:Advance(2)
cara.env.RUIN_API:GetModule("Pathfinder"):Advance(2)
Server:Advance(15)
check(alice.env.RUIN_PathfinderTracker and alice.env.RUIN_PathfinderTracker.peers:GetText():find("1 RUIN member"), "tracker shows Cara on the same step")
alice.env.RUIN_API:OpenTab("Pathfinder")
errorsSoFar("pathfinder")

print("Codex")
eve.instance = "The Deadmines"
Server.fire(eve, "CHAT_MSG_LOOT", "You receive loot: |cff0070dd|Hitem:5191::::::::|h[Cruel Barb]|h|r.", "Eve Ember")
Server:Advance(3)
check(alice.env.RUIN_CodexDB.drops["The Deadmines"] and alice.env.RUIN_CodexDB.drops["The Deadmines"][5191], "Eve's drop learned by Alice")
local lines = {}
local tip = { GetItem = function() return "Helm", "|cff0070dd|Hitem:100::|h[New Helm]|h|r" end,
              AddLine = function(_, l) lines[#lines + 1] = l end }
for _, hook in ipairs(alice.tooltipHooks) do hook(tip) end
local joined = table.concat(lines, "\n")
check(joined:find("Codex: %+100%% upgrade"), "tooltip shows upgrade line (" .. (lines[1] or "none") .. ")")
alice.env.RUIN_API:OpenTab("Codex")
errorsSoFar("codex")

print("Exchange")
cara.ahResults = { { itemKey = { itemID = 2589 }, minPrice = 4200 } }
Server.fire(cara, "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
Server.fire(cara, "AUCTION_HOUSE_CLOSED")
Server:Advance(3)
check(alice.env.RUIN_ExchangeDB.prices[2589] and alice.env.RUIN_ExchangeDB.prices[2589].p == 4200, "Cara's AH price reached Alice")
Server.fire(eve, "TRADE_SKILL_SHOW")
Server:Advance(6)
local eveCrafts = alice.env.RUIN_ExchangeDB.crafters[eve.guid]
check(eveCrafts and eveCrafts.profs.Alchemy and eveCrafts.profs.Alchemy[1] == "Flask of the Titans", "Eve's recipes reached Alice")
alice.env.SlashCmdList.RUINEXCHANGE("flask")
errorsSoFar("exchange")

print("Muster")
local mu = alice.env.RUIN_API:GetModule("Muster")
local soon = os.date("%Y-%m-%d %H:%M", os.time() + 10 * 60 + 59)
mu:Create("Molten Core", soon, "Raid")
Server:Advance(3)
local id
for eid, ev in pairs(cara.env.RUIN_MusterDB.events) do if ev.title == "Molten Core" then id = eid end end
check(id ~= nil, "Cara received the event")
cara.env.RUIN_API:GetModule("Muster"):SignUp(id, "T")
Server:Advance(3)
check(alice.env.RUIN_MusterDB.events[id].signups[cara.guid] and alice.env.RUIN_MusterDB.events[id].signups[cara.guid].role == "T", "Cara's tank sign-up reached Alice")
Server:Advance(40)
check(chatHas(cara, "Molten Core starts in"), "Cara got the reminder")
alice.env.RUIN_API:OpenTab("Muster")
errorsSoFar("muster")

print("Muster: sightings")
eve.zone, eve.subzone = "The Barrens", "The Crossroads"
eve.env.SlashCmdList.RUINMUSTERINTEL("enemy 8 Horde heading north")
Server:Advance(2)
check(chatHas(alice, "Enemy group") and chatHas(alice, "8 Horde heading north") and chatHas(alice, "The Crossroads"), "enemy sighting reached Alice with location")
alice.env.RUIN_API:OpenTab("Muster")
errorsSoFar("sightings")

print("Practice mode (connected non-officer)")
eve.env.SlashCmdList.RUINMUSTER("practice")
eve.env.RUIN_API:GetModule("Muster"):Create("Practice Raid", os.date("%Y-%m-%d %H:%M", os.time() + 7200), "Raid")
eve.env.SlashCmdList.RUINMUSTER("bounty player Practice Target")
Server:Advance(3)
local leaked = false
for _, ev in pairs(cara.env.RUIN_MusterDB.events) do if ev.title == "Practice Raid" then leaked = true end end
for _, bo in pairs(cara.env.RUIN_MusterDB.bounties) do if bo.target == "Practice Target" then leaked = true end end
check(chatHas(eve, "Practice event posted: Practice Raid") and chatHas(eve, "Bounty posted on player Practice Target") and not leaked,
      "Eve's practice event and bounty stayed on her screen")
eve.env.SlashCmdList.RUINMUSTER("practice")
local left = false
for _, bo in pairs(eve.env.RUIN_MusterDB.bounties) do if bo.practice then left = true end end
check(not left, "turning practice off cleared practice bounties")
errorsSoFar("practice")

print("Core page with modules")
alice.env.RUIN_API:OpenTab("Org")
alice.ns.UI:Refresh()
errorsSoFar("org page")
check(Server.maxLen <= 255, "no addon message over 255 bytes (max " .. Server.maxLen .. ")")


print("Themed pages and animated headers")
do
    local titles = {}
    for _, t in ipairs({ "Org", "Finder", "Pathfinder", "Codex", "Exchange", "Muster", "Settings" }) do
        local opened = alice.env.RUIN_API:OpenTab(t)
        if opened ~= false then titles[#titles + 1] = t end
    end
    check(#titles == 7, "every module page opens (" .. #titles .. "/7)")
    local function tickAll(n)
        local ran = 0
        for _ = 1, n do
            for _, f in ipairs(alice.frames) do
                local fn = f._scripts.OnUpdate
                if fn then
                    local ok, err = pcall(fn, f, 0.05)
                    if not ok then table.insert(Server.errors, "OnUpdate: " .. tostring(err)) end
                    ran = ran + 1
                end
            end
        end
        return ran
    end
    check(tickAll(40) > 0, "header scenes animate")
    alice.ns.db.settings.animations = false
    tickAll(10)
    alice.ns.db.settings.animations = true
    errorsSoFar("themed pages")
    check(alice.ns.ThemeFor("Warfront").title ~= nil, "Warfront theme has a title")
    check(alice.ns.ThemeFor("Nonexistent") ~= nil, "unknown page falls back to a theme")
end


print("Core kit (API level 3)")
do
    local R = alice.env.RUIN_API
    check(R.apiLevel >= 3, "API level 3")
    local s = R.Util.Encode("ROUTE", { id = "x", steps = { { act = "go", text = "Hi" } } })
    local back = R.Util.Decode("ROUTE", s)
    check(back and back.steps[1].text == "Hi", "export string round-trips")
    local _, err = R.Util.Decode("ROUTE", s:sub(1, -3) .. "zz")
    check(err ~= nil, "damaged export string rejected (" .. tostring(err) .. ")")
    local _, err2 = R.Util.Decode("BIS", s)
    check(err2 ~= nil, "wrong kind rejected")
    local got
    R:Subscribe("Test:PING", function(v) got = v end)
    R:Publish("Test:PING", 42)
    check(got == 42, "module events reach subscribers")
    -- map pins on the world map and minimap
    alice.pos = { map = 1411, x = 0.50, y = 0.50 }
    R.Map:SetPin("Test", "a", { map = 1411, x = 0.52, y = 0.50, title = "Pin A", color = { 1, 0, 0 } })
    alice.env.WorldMapFrame._shown = true
    alice.worldMapID = 1411
    Server:Advance(1.2)
    local shown = 0
    for _, f in ipairs(alice.frames) do if f.pin and f._shown and f.pin.title == "Pin A" then shown = shown + 1 end end
    check(shown >= 1, "pin drawn on the world map")
    local txt = R.Map:DistanceText(1411, 0.52, 0.50)
    check(txt and txt:find("80 yd E"), "distance text (" .. tostring(txt) .. ")")
    local x, y = R.Map:Translate(1411, 0.5, 0.5, 1414)
    check(x and math.abs(x - 0.55) < 1e-6 and math.abs(y - 0.65) < 1e-6, "zone pin translates onto its continent")
    alice.worldMapID = 1414
    alice.env.WorldMapFrame._scripts.OnShow()
    R.Map:RemovePin("Test", "a")
    Server:Advance(0.5)
    local W = R.Widgets
    local hud = W.HudFrame("RUIN_TestHud", "Intel", {}, "pos", { "CENTER" })
    check(hud and hud.band ~= nil, "themed HUD frame")
    local parent = alice.env.CreateFrame("Frame")
    local selected
    local tabs = W.SubTabs(parent, { "One", "Two" }, function(i) selected = i end)
    tabs:Select(2)
    check(selected == 2 and tabs.pages[2]:IsShown() and not tabs.pages[1]:IsShown(), "sub-tabs switch pages")
    check(W.RoleIcon("T"):find("PORTRAITROLES") and W.ClassIcon("WARRIOR"):find("CLASSES"), "role and class icons")
    errorsSoFar("core kit")
end

print(("\n%d passed, %d failed, %d addon messages sent"):format(pass, fail, Server.sent))
os.exit(fail == 0 and 0 or 1)
