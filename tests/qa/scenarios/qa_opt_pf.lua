-- QA round 3: OPT-4/5 (Pathfinder reminders) driven by the real 2 s ticker.
-- Prints a timeline of reminder lines so two builds can be compared.
dofile("/home/claude/stage/tests/harness.lua")
local pass, fail = 0, 0
local function check(cond, label)
    if cond then pass = pass + 1; print("  ok   " .. label)
    else fail = fail + 1; print("  FAIL " .. label) end
end
Server.guilds["Ashen Order"] = { { name = "Alice Ash", rank = 0, guid = "Player-1-00000001" } }
local alice = Server:NewClient({ name = "Alice Ash", guid = "Player-1-00000001", guild = "Ashen Order", rank = 0,
    modules = { "RUIN_Pathfinder" } })
Server:Advance(10)
local env = alice.env
local pf = env.RUIN_API:GetModule("Pathfinder")
local QB = pf.QB
local Map = env.RUIN_API.Map
local px, py = 0.10, 0.10
Map.PlayerPos = function() return 1429, px, py end
local level = 10
env.UnitLevel = function() return level end
local function at(x, y) return { { map = 1429, x = x, y = y } } end
local world = {
    [501] = { name = "Wolves at the Gate", start = at(0.30, 0.30), obj = at(0.80, 0.80), giver = "Marshal Gryan", req = 1 },
    [502] = { name = "Kobold Candles", start = at(0.60, 0.20), obj = at(0.15, 0.70), giver = "William Pestle", req = 1 },
    [503] = { name = "Candle Wax", start = at(0.62, 0.22), obj = at(0.151, 0.701), giver = "Remy Two Times", req = 1 },
    [504] = { name = "Bandit Bounty", start = at(0.50, 0.50), obj = at(0.40, 0.90), giver = "Deputy Willem", req = 12 },
    [505] = { name = "Second Step", start = at(0.70, 0.60), obj = at(0.90, 0.10), giver = "Guard Thomas", req = 1 },
}
local have = {}
QB.Has = function() return true end
QB.Spots = function(q, which) local w = world[q]; return w and (which == "start" and w.start or which == "objective" and w.obj) or {} end
QB.Spot = function(q, which) return QB.Spots(q, which)[1] end
QB.InLog = function(q) return have[q] and true or false, false end
QB.Done = function() return false end
QB.Quest = function(q) local w = world[q]; return w and { id = q, name = w.name, starts = { w.giver }, level = 10, req = w.req } end
local zone = { { id = 502, level = 10 }, { id = 503, level = 10 } }
QB.ZoneQuests = function() return zone end
QB.AreaOf = function() return 12 end
QB.Prereqs = function() return {} end
local cdb, adb = env.RUIN_PathfinderCharDB, env.RUIN_PathfinderDB
adb.custom["qa"] = { id = "qa", name = "QA", steps = {
    { act = "accept", quest = "Wolves at the Gate", qid = 501 },
    { act = "accept", quest = "Bandit Bounty", qid = 504 },
    { act = "complete", quest = "Wolves at the Gate", qid = 501 },
    { act = "accept", quest = "Second Step", qid = 505 } } }
cdb.route, cdb.step = "qa", 1
pf.ResetReminders()
local t0 = Server.time
local seen = 0
local function newLines()
    local out = {}
    for i = seen + 1, #alice.chat do
        local l = tostring(alice.chat[i])
        if l:find("walked past", 1, true) or l:find("targets are here", 1, true) then
            out[#out + 1] = l
            print(("    [t=%6.1f] %s"):format(Server.time - t0, (l:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))))
        end
    end
    seen = #alice.chat
    return out
end
local function has(lines, s) for _, l in ipairs(lines) do if l:find(s, 1, true) then return true end end return false end
local function walk(points, dt)
    local acc = {}
    for _, p in ipairs(points) do px, py = p[1], p[2]; Server:Advance(dt or 2); for _, l in ipairs(newLines()) do acc[#acc + 1] = l end end
    return acc
end
newLines()

print("A: moving past a route giver (ticker)")
local l = walk({ { 0.30, 0.25 }, { 0.30, 0.29 }, { 0.30, 0.302 }, { 0.30, 0.33 }, { 0.30, 0.38 }, { 0.30, 0.45 }, { 0.30, 0.50 } })
check(has(l, "You walked past") and has(l, "Wolves at the Gate"), "walking past without it reminds")
local n = 0; for _, x in ipairs(l) do if x:find("walked past", 1, true) then n = n + 1 end end
check(n == 1, "once (" .. n .. ")")
l = walk({ { 0.30, 0.30 }, { 0.30, 0.45 } })
check(not has(l, "walked past"), "not again")

print("B: standing still in two zone quests' target area")
l = walk({ { 0.15, 0.70 } }, 0.5)
Server:Advance(1.6); for _, x in ipairs(newLines()) do l[#l + 1] = x end
Server:Advance(2); for _, x in ipairs(newLines()) do l[#l + 1] = x end
Server:Advance(2); for _, x in ipairs(newLines()) do l[#l + 1] = x end
check(has(l, "Kobold Candles") and has(l, "Candle Wax"), "both reminders while standing still")
Server:Advance(30)
l = newLines()
check(#l == 0, "and nothing more while still (" .. #l .. ")")

print("C: options toggled while standing still")
pf.ResetReminders()
cdb.remindArea = false; cdb.remindPickups = false
px, py = 0.80, 0.80        -- in 501's target area (on route, not in log)
Server:Advance(6); l = newLines()
check(#l == 0, "options off: nothing")
cdb.remindArea = true
local tOn = Server.time
Server:Advance(2.05); l = newLines()
check(has(l, "Wolves at the Gate") and has(l, "on your route"), "turning area reminders on while still works at the next check")
-- pickups toggled on while standing still beyond the giver after having been near
pf.ResetReminders()
cdb.remindPickups = false; cdb.remindArea = false
px, py = 0.30, 0.302; Server:Advance(2.05); px, py = 0.30, 0.302; Server:Advance(2)
cdb.remindPickups = true
Server:Advance(2.05); l = newLines()     -- near the giver: marked near, no reminder
px, py = 0.30, 0.45
Server:Advance(2.05); l = newLines()
check(has(l, "walked past"), "pick-up reminder after turning pick-ups on and walking off")
cdb.remindArea, cdb.remindPickups = true, true

print("D: level-up while standing still in a route quest's area")
pf.ResetReminders()
px, py = 0.40, 0.90        -- 504's targets (req 12)
Server:Advance(6); l = newLines()
check(not has(l, "Bandit Bounty"), "level 10: no reminder for a level 12 quest")
level = 12
local tLv = Server.time
Server:Advance(2.05); l = newLines()
check(has(l, "Bandit Bounty"), "level 12: reminder at the next check (standing still)")

print("E: taking a quest (QUEST_LOG_UPDATE) clears the pick-up")
pf.ResetReminders()
px, py = 0.30, 0.302; Server:Advance(2.05); newLines()
have[501] = true
Server.fire(alice, "QUEST_LOG_UPDATE")
px, py = 0.30, 0.45; Server:Advance(2.05); l = newLines()
check(not has(l, "Wolves at the Gate"), "quest taken just before walking off: no pick-up reminder")
have[501] = nil

print("F: advancing a step while standing still")
pf.ResetReminders()
cdb.step = 4
px, py = 0.90, 0.10        -- 505 targets
Server:Advance(2.05); l = newLines()
check(has(l, "Second Step"), "step 4's pick-up area reminds at once")
cdb.step = 1
pf.ResetReminders()
px, py = 0.90, 0.10
Server:Advance(2.05); newLines()
cdb.step = 4
Server:Advance(2.05); l = newLines()
check(has(l, "Second Step"), "step changed while standing still: reminder at the next check")

print("G: new data while standing still (zone list)")
pf.ResetReminders()
px, py = 0.05, 0.05
Server:Advance(4); newLines()
world[506] = { name = "Late Data", start = at(0.5, 0.5), obj = at(0.051, 0.051), giver = "Late Giver", req = 1 }
zone[#zone + 1] = { id = 506, level = 10 }
local tD = Server.time
local got = false
for _ = 1, 70 do Server:Advance(2); if has(newLines(), "Late Data") then got = true; break end end
print(("    new zone quest under the player noticed after %.1f s"):format(Server.time - tD))
check(true, "(informational)")
print(#Server.errors == 0 and "  ok   no Lua errors" or ("  FAIL errors: " .. table.concat(Server.errors, " | ")))
print(("%d passed, %d failed"):format(pass, fail))
