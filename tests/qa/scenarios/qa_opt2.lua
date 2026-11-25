-- QA (optimization round 2): prints what OPT2-1..6 touch so two builds can be diffed line by line.
-- Run from <build>/tests:  QA_TESTS=<build>/tests RUIN_CORE_DIR=<build>/RUIN_Core texlua qa/run51.lua /tmp/ruin-qa/opt-2/tools/qa_opt2.lua
-- (the harness is loaded from the build's own tests folder)
local here = os.getenv("QA_TESTS") or "."
dofile(here .. "/harness.lua")
local function out(...) print(table.concat({ ... }, " | ")) end
local function r1(n) return n and tostring(math.floor(n * 10 + 0.5) / 10) or "nil" end

local MODULES = { "RUIN_Finder", "RUIN_Pathfinder", "RUIN_Codex", "RUIN_Exchange", "RUIN_Muster" }
Server.guilds["Ashen Order"] = { { name = "Alice Ash", rank = 0, guid = "Player-1-00000001" } }
Server.guilds["Briar Fang"] = { { name = "Cara Cole", rank = 0, guid = "Player-1-00000002" } }
local alice = Server:NewClient({ name = "Alice Ash", guid = "Player-1-00000001", guild = "Ashen Order", rank = 0, modules = MODULES })
local cara = Server:NewClient({ name = "Cara Cole", guid = "Player-1-00000002", guild = "Briar Fang", rank = 0, modules = MODULES })
Server:Advance(10)
Server:Slash(alice, "key create RUIN")
Server:Slash(alice, "key addguild Briar Fang, 1, Briar")
alice.ns.Org:SendFullKey("Cara Cole")
Server:Advance(20)
cara.env.RUIN_ConfirmDialog.onAccept()
Server:Advance(90)

-- 1. Crypto.Hex / Unhex (OPT2-1)
local C = alice.ns.Crypto
local all = {}
for i = 0, 255 do all[#all + 1] = string.char(i) end
all = table.concat(all)
out("hex", C.Hex(all):sub(1, 64), C.Hex(all):sub(-64), #C.Hex(all))
out("unhex", tostring(C.Unhex(C.Hex(all)) == all), tostring(C.Unhex(C.Hex(all):upper()) == all), tostring(C.Unhex("aBcD") == "\171\205"),
    tostring(C.Unhex("abc")), tostring(C.Unhex("zz")), tostring(C.Unhex("")))
out("sha", C.SHA256Hex("RUIN"), "admin", tostring(alice.ns.Org:IsAdmin()), tostring(cara.ns.Org:IsAdmin()))
out("datakey", tostring(alice.ns.Org:DataKeyHex() ~= nil), tostring(alice.ns.Org:DataKeyHex() == cara.ns.Org:DataKeyHex()))

-- 2. Channel recognition (OPT2-2)
local Comms = alice.ns.Comms
for _, args in ipairs({ { "General - Elwynn" }, { "Trade" }, { nil, 5, "x" } }) do
    out("ours", tostring(Comms.IsOurChannel(unpack(args, 1, 3))))
end
for _, ch in ipairs(Comms.ChannelList()) do
    out("chan", ch.id, ch.name, tostring(Comms.IsOurChannel(ch.name)), tostring(Comms.IsOurChannel(ch.name:upper())), tostring(Comms.IsOurChannel("x", ch.name)))
end

-- 3. Tab order (OPT2-4)
out("tabs", table.concat(alice.ns.UI:TabLabels(), ","))
local mv = {}
for _, e in ipairs(alice.ns.UI:MovableTabs()) do mv[#mv + 1] = e.title end
out("movable", table.concat(mv, ","))
alice.ns.UI:MoveTab(mv[3], -1)
out("moved", table.concat(alice.ns.UI:TabLabels(), ","))

-- 4. Settings page text after peers/roster changes
alice.env.RUIN_ToggleWindow()
alice.env.RUIN_API:OpenTab("Settings")
local S = alice.ns.UI.settings
for _, ev in ipairs({ "PEERS_CHANGED", "ROSTER_UPDATED", "KEY_CHANGED" }) do
    alice.ns:Fire(ev)
    out("settings " .. ev, (S.status:GetText() or ""):gsub("\n", " / "))
    out("about " .. ev, (S.about:GetText() or ""):gsub("\n", " / "))
end

-- 5. Throttle.OthersSending against a full count (OPT2-6)
local T = alice.ns.Throttle
local calls = (function(fn) for i = 1, 60 do local n, v = debug.getupvalue(fn, i); if not n then return end; if n == "calls" then return v end end end)(T.OthersSending)
local function brute(window)
    local now, n = alice.env.GetTime(), 0
    for _, c in pairs(calls or {}) do
        if now - c.t <= window and c.api:find("SendAddonMessage", 1, true) and not tostring(c.who):find("^RUIN") then n = n + 1 end
    end
    return n
end
math.randomseed(7)
local agree = 0
for round = 1, 900 do
    local k = math.random(1, 3)
    if k == 1 then T.Note("C_ChatInfo.SendAddonMessage")
    elseif k == 2 then T.selfSending = true; T.Note("C_ChatInfo.SendAddonMessage"); T.selfSending = nil
    else T.Note("C_GuildInfo.GuildRoster") end
    if round % 7 == 0 then Server:Advance(math.random() * 2) end
    local w = math.random(1, 6)
    if T.OthersSending(w) == brute(w) then agree = agree + 1 end
end
out("others", "agree " .. agree .. "/900", T.OthersSending(3), T.OthersSending(60))

-- 6. Pathfinder tracker size and texts through route steps, tabs, moves, docking (OPT2-3)
local pf = alice.env.RUIN_API:GetModule("Pathfinder")
alice.pos = { map = 1411, x = 0.40, y = 0.68 }
pf:StartRoute("vot")
local tr = alice.env.RUIN_PathfinderTracker
local function snap(label)
    pf.UpdateTracker()
    out("tracker " .. label, r1(tr:GetWidth()), r1(tr:GetHeight()), r1(tr.step:GetWidth()), tostring(tr:IsShown()),
        (tr.title:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""), ((tr.step:GetText() or ""):gsub("\n", " / "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")),
        tostring(tr.dist:GetText()))
end
snap("start")
snap("again")
for i = 1, 12 do
    pf:Advance(1)
    snap("step " .. i)
    if i % 3 == 0 then
        alice.pos = { map = 1411, x = 0.40 + i * 0.01, y = 0.68 }
        tr.nav._scripts.OnUpdate(tr.nav, 0.1)
        snap("moved " .. i)
        Server:Advance(10)
        snap("ticked " .. i)
    end
end
pf:Advance(-5)
snap("back 5")
alice.logIds = { [4641] = true }
alice.questTitles[4641] = "Your Place In The World"
alice.questObjectives = { [4641] = { { text = "Talk to Gornek", finished = false } } }
alice.trackedQuest = 4641
local cdb = alice.env.RUIN_PathfinderCharDB
cdb.trackerTab = "tracked"
snap("tracked")
alice.questObjectives = { [4641] = { { text = "Talk to Gornek", finished = true }, { text = "Kill 10 very long named boars of the eastern valley of trials near the cave", finished = false },
    { text = "Collect 8 Scorpid Tails", finished = false }, { text = "Something else that is quite long too, so it wraps", finished = false } } }
Server.fire(alice, "QUEST_LOG_UPDATE")
snap("tracked long")
alice.questObjectives = { [4641] = { { text = "Done", finished = true } } }
Server.fire(alice, "QUEST_LOG_UPDATE")
snap("tracked short")
cdb.trackerTab = "route"
snap("route again")
if alice.ns.Minimap and alice.ns.Minimap.SetDock then
    pcall(alice.ns.Minimap.SetDock, "on")
    snap("docked")
    pcall(alice.ns.Minimap.SetDock, "off")
    snap("undocked")
end
tr:SetSize(200, 40)                -- something else changed the size: refit
snap("resized")

-- 6b. The same with a text layout model (the simulator's frames don't size text):
-- width and height are kept, text height follows the text length and width.
do
    local W_, H_ = tr:GetWidth(), tr:GetHeight()
    tr.GetWidth = function() return W_ end
    tr.GetHeight = function() return H_ end
    tr.SetSize = function(_, w, h) W_, H_ = w, h end
    local sw, font = 100, { "Fonts\\FRIZQT__.TTF", 12, "" }
    local step = tr.step
    step.SetWidth = function(_, w) sw = w end
    step.GetWidth = function() return sw end
    step.GetFont = function() return font[1], font[2], font[3] end
    step.GetStringHeight = function(self)
        local t = self:GetText() or ""
        if t == "" then return 0 end
        local per = font[2] * 0.5
        local lines = 0
        for line in (t .. "\n"):gmatch("([^\n]*)\n") do lines = lines + math.max(1, math.ceil(#line * per / math.max(1, sw))) end
        return lines * (font[2] + 2)
    end
    local function sw2(fs) fs.GetStringWidth = function(self) return #(self:GetText() or "") * 5 end end
    sw2(tr.title); sw2(tr.dist)
    local function snap2(label)
        pf.UpdateTracker()
        out("model " .. label, r1(W_), r1(H_), r1(sw))
    end
    pf:Advance(-20)
    snap2("start")
    snap2("again")
    for i = 1, 12 do
        pf:Advance(1); snap2("step " .. i)
        if i % 4 == 0 then
            alice.pos = { map = 1411, x = 0.40 + i * 0.013, y = 0.69 }
            tr.nav._scripts.OnUpdate(tr.nav, 0.1)
            snap2("moved " .. i)
        end
    end
    pf:Advance(-6); snap2("back")
    font[2] = 16; snap2("bigger font")
    snap2("bigger font again")
    font[2] = 12; snap2("font back")
    W_, H_ = 333, 50; snap2("resized by something else")
    snap2("again")
    tr.step:SetText(""); snap2("empty text")
    snap2("again")
end

-- 7. QuestDB lookups of quests that aren't in the database (OPT2-5)
local QB = pf.QB
out("quest", tostring(QB.Quest(987654)), tostring(QB.Quest(987654)), tostring(QB.Quest("x")), tostring(QB.Quest(4641) and QB.Quest(4641).name))
out("errors", #Server.errors, table.concat(Server.errors, " // "))
