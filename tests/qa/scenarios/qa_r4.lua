-- QA round 4 (after optimization round 2): deeper OPT2-3 (tracker fit cache) and OPT2-5 (QB.Quest false cache) checks.
-- Run from <build>/tests:  QA_TESTS=<build>/tests RUIN_CORE_DIR=<build>/RUIN_Core texlua qa/run51.lua <this file>
-- Lines starting "size"/"quest" must match between builds; "meas" lines count re-measures (expected to drop on stage).
local here = os.getenv("QA_TESTS") or "."
dofile(here .. "/harness.lua")
local function out(...) print(table.concat({ ... }, " | ")) end
local function r1(n) return n and tostring(math.floor(n * 10 + 0.5) / 10) or "nil" end

Server.guilds["Ashen Order"] = { { name = "Alice Ash", rank = 0, guid = "Player-1-00000001" } }
local alice = Server:NewClient({ name = "Alice Ash", guid = "Player-1-00000001", guild = "Ashen Order", rank = 0,
    modules = { "RUIN_Pathfinder" } })
Server:Advance(10)
local pf = alice.env.RUIN_API:GetModule("Pathfinder")
alice.pos = { map = 1411, x = 0.40, y = 0.68 }
pf:StartRoute("vot")
local tr = alice.env.RUIN_PathfinderTracker
local cdb = alice.env.RUIN_PathfinderCharDB

-- text layout model -------------------------------------------------------
local W_, H_ = 320, 66
tr.GetWidth = function() return W_ end
tr.GetHeight = function() return H_ end
tr.SetSize = function(_, w, h) W_, H_ = w, h end
local fonts = { step = { "F", 12, "" }, title = { "F", 10, "" }, dist = { "F", 10, "" } }
local sw, measures, blank = 100, 0, 0
local function plain(t) return ((t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local step = tr.step
step.SetWidth = function(_, w) sw = w; measures = measures + 1 end
step.GetWidth = function() return sw end
for k, fs in pairs({ step = tr.step, title = tr.title, dist = tr.dist }) do
    local f = fonts[k]
    fs.GetFont = function() return f[1], f[2], f[3] end
    fs.SetFont = function(_, a, b, c) f[1], f[2], f[3] = a, b, c end
    fs.GetStringWidth = function(self) return #plain(self:GetText()) * f[2] * 0.45 end
end
step.GetStringHeight = function(self)
    if blank > 0 then blank = blank - 1; return 0 end     -- "not laid out yet"
    local t = plain(self:GetText())
    if t == "" then return 0 end
    local f = fonts.step
    local lines = 0
    for line in (t .. "\n"):gmatch("([^\n]*)\n") do lines = lines + math.max(1, math.ceil(#line * f[2] * 0.45 / math.max(1, sw))) end
    return lines * (f[2] + 2)
end
local function snap(label)
    measures = 0
    pf.UpdateTracker()
    out("size " .. label, r1(W_), r1(H_), r1(sw))
    print("meas " .. label .. " " .. measures)
end

snap("start"); snap("again")
-- long and short steps
for i = 1, 11 do pf:Advance(1); snap("step " .. i) end
pf:Advance(-11); snap("back to 1")
-- a very long step text set directly (custom route note) and back
local orig = tr.step:GetText()
local long = string.rep("A very long route note that keeps going ", 12)
pf.UpdateTracker()
tr.step.SetTextOrig = tr.step.SetTextOrig or tr.step.SetText
-- tracked tab with growing/shrinking objectives
alice.logIds = { [4641] = true, [788] = true }
alice.questTitles = alice.questTitles or {}
alice.questTitles[4641] = "Your Place In The World"
alice.questTitles[788] = "Cutting Teeth"
alice.questObjectives = { [4641] = { { text = "Talk to Gornek", finished = false } },
    [788] = { { text = "Mottled Boar slain: 0/10", finished = false } } }
cdb.userQuest = 4641
cdb.trackerTab = "tracked"
snap("tracked 1 obj")
alice.questObjectives[4641] = { { text = "Talk to Gornek", finished = true },
    { text = "Kill 10 very long named boars of the eastern valley of trials near the cave mouth", finished = false },
    { text = "Collect 8 Scorpid Tails", finished = false }, { text = "Something else that is quite long too, so it wraps around", finished = false } }
Server.fire(alice, "QUEST_LOG_UPDATE"); snap("tracked 4 obj")
alice.questObjectives[4641][3].text = "Collect 8 Scorpid Tails: 7/8 and a much longer progress line here"
Server.fire(alice, "QUEST_LOG_UPDATE"); snap("objective text longer")
alice.questObjectives[4641] = { { text = "Done", finished = true } }
Server.fire(alice, "QUEST_LOG_UPDATE"); snap("tracked 1 obj again")
cdb.userQuest = 788; snap("tracked other quest")
cdb.trackerTab = "route"; snap("route tab")
cdb.trackerTab = "tracked"; snap("tracked tab")
cdb.trackerTab = "route"; snap("route tab 2")
-- distance text getting longer / shorter (same step)
tr.dist:SetText("5 yards"); snap("dist short")
tr.dist:SetText("Durotar - Valley of Trials, 1234 yards away"); snap("dist long")
tr.dist:SetText("5 yards"); snap("dist short again")
-- arrow tick moves the distance, then the 10 s ticker
alice.pos = { map = 1411, x = 0.55, y = 0.60 }
if tr.nav and tr.nav._scripts and tr.nav._scripts.OnUpdate then tr.nav._scripts.OnUpdate(tr.nav, 0.1) end
Server:Advance(11); out("size after ticker", r1(W_), r1(H_), r1(sw))
-- dock/undock (retired: no-op dock, but OnDockChanged refits)
if alice.ns.Minimap and alice.ns.Minimap.SetDock then
    alice.ns.Minimap.SetDock("top"); out("size docked", r1(W_), r1(H_), r1(sw))
    alice.ns.Minimap.SetDock("off"); out("size undocked", r1(W_), r1(H_), r1(sw))
end
-- look change
if pf.SetTrackerStyle then for _, st in ipairs({ "dark", "blizzard", "ruin" }) do pcall(pf.SetTrackerStyle, st) end end
snap("after look change")
-- fonts: each of the three alone
fonts.step[2] = 16; snap("step font 16"); snap("step font 16 again")
fonts.step[2] = 12; snap("step font back")
fonts.title[2] = 18; snap("title font 18")
fonts.title[2] = 10; snap("title font back")
fonts.dist[2] = 20; tr.dist:SetText("Durotar - Valley of Trials"); snap("dist font 20")
fonts.dist[2] = 10; snap("dist font back")
fonts.step[1] = "G"; snap("step font file")
fonts.step[1] = "F"; fonts.step[3] = "OUTLINE"; snap("step outline")
fonts.step[3] = ""; snap("step plain")
-- outside resize, including to the same size it had
W_, H_ = 200, 40; snap("resized smaller by something else")
W_, H_ = 900, 300; snap("resized bigger by something else")
-- text not laid out at first: measure 0, then real
blank = 100; pf:Advance(1); snap("not laid out")
blank = 0; snap("laid out now")
snap("laid out again")
-- the step changes but ends up with the same text as before (route complete)
pf:Advance(50); snap("complete"); pf:Advance(1); snap("complete again")
-- route stopped and restarted
pf:StartRoute("vot"); snap("restarted")
out("errors", #Server.errors, table.concat(Server.errors, " // "))

-- OPT2-5 ------------------------------------------------------------------
local undoDB = dofile(here .. "/fake_questdb.lua")(alice, {})
local QB = pf.QB
local D = alice.env.RUIN_QuestData
out("quest has", tostring(QB.Has()), tostring(D ~= nil and D.q ~= nil))
local miss = 999991
out("quest miss", tostring(QB.Quest(miss)), tostring(QB.Quest(miss)))
local any
any = 9001
out("quest hit", tostring(any ~= nil), tostring(any and QB.Quest(any) and QB.Quest(any).id == any))
-- a quest added to the data after a lookup (not done by shipped code: data is static)
if D and D.q and any then
    D.q[miss] = D.q[any]
    print("late-row " .. tostring(QB.Quest(miss) ~= nil))   -- expected to differ: base true, stage false
    QB.Forget()
    out("quest after Forget", tostring(QB.Quest(miss) ~= nil))
    D.q[miss] = nil
    QB.Forget()
    out("quest gone after Forget", tostring(QB.Quest(miss)))
    -- database detached, looked up, attached late
    local saved = alice.env.RUIN_QuestData
    alice.env.RUIN_QuestData = nil
    QB.Forget()
    out("quest no db", tostring(QB.Has()), tostring(QB.Quest(any)), tostring(QB.Quest(miss)))
    alice.env.RUIN_QuestData = saved
    out("quest db attached late", tostring(QB.Has()), tostring(QB.Quest(any) ~= nil))
    -- ForgetSpots doesn't touch the quest cache in either build
    QB.ForgetSpots(any)
    out("quest after ForgetSpots", tostring(QB.Quest(any) ~= nil), tostring(QB.Quest(miss)))
    -- a lookup that errors is not remembered
    local real = D.q
    D.q = setmetatable({}, { __index = function() error("boom") end })
    QB.Forget()
    out("quest error", tostring(QB.Quest(any)))
    D.q = real
    QB.Forget()
    out("quest after error", tostring(QB.Quest(any) ~= nil))
end
out("errors end", #Server.errors)
