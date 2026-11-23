-- RUIN route planner: builds Pathfinder's levelling routes from RUIN Quest Data.
--
--   texlua tests/qa/run51.lua tests/tools/plan_routes.lua <RUIN_Pathfinder dir> [out file]
--
-- For each level bracket it simulates a solo Alliance character: at every
-- point it picks the group of quests (a part of a zone, as Pathfinder's zone
-- routes split them) that gives the most experience per hour at the
-- character's level, counting the walk between givers, objectives and
-- hand-ins, the time to finish objectives and the trip to get there. It does
-- that group's quests in Pathfinder's planned order, levels up as the
-- experience comes in, and moves on, zone to zone, until the bracket's top
-- level. Where quests run short it says where to grind.
--
-- Bracket 1-6 has a route per starting area; later brackets have the best
-- route and up to two others that start in a different zone. A route's last
-- step names 1-3 routes to start next, best first.
--
-- The numbers are estimates (quest XP from its level, about 7 yards a second
-- on foot, time per kill and per item), good for comparing zones, not a promise.
local here = arg[0]:match("^(.*)/") or "."
local PF = assert(arg[1], "usage: plan_routes.lua <RUIN_Pathfinder dir> [out]")
local OUT = arg[2] or (PF .. "/Routes.lua")
local TESTS = here .. "/.."
arg[1], arg[2] = nil, nil      -- the harness reads arg[1] as Core's folder (RUIN_CORE_DIR says where it is)
package.path = TESTS .. "/?.lua;" .. package.path
dofile(TESTS .. "/harness.lua")

local alice = Server:NewClient({ name = "Planner", guid = "Player-1-00000099", guild = "Ashen Order", rank = 0,
                                 modules = { "RUIN_Pathfinder" } })
local env = alice.env
for _, f in ipairs({ "Data.lua", "Fixes.lua" }) do
    local chunk = loadfile(PF .. "/QuestData/" .. f)
    if chunk then setfenv(chunk, env); chunk() end
end
local pf = env.RUIN_API:GetModule("Pathfinder")
local QB = pf.QB
local pns = alice.mns.RUIN_Pathfinder

env.UnitFactionGroup = function() return "Alliance", "Alliance" end
env.UnitClass = function() return "Warrior", "WARRIOR", 1 end
-- zone (area) names: the game gives them in play (C_Map.GetAreaInfo); here, Classic's IDs
-- plus WoW Forever's own zones, as their quests place them (Coming of Age is on Zephras
-- Isle, Friz Frazzlespark at Powderfuse Port in the Riverglades, Hyjal Stags on Mount Hyjal)
local AREA = {
    [1] = "Dun Morogh", [3] = "Badlands", [4] = "Blasted Lands", [8] = "Swamp of Sorrows", [10] = "Duskwood", [11] = "Wetlands",
    [12] = "Elwynn Forest", [14] = "Durotar", [15] = "Dustwallow Marsh", [16] = "Azshara", [17] = "The Barrens",
    [28] = "Western Plaguelands", [33] = "Stranglethorn Vale", [36] = "Alterac Mountains", [38] = "Loch Modan", [40] = "Westfall",
    [41] = "Deadwind Pass", [44] = "Redridge Mountains", [45] = "Arathi Highlands", [46] = "Burning Steppes", [47] = "The Hinterlands",
    [51] = "Searing Gorge", [85] = "Tirisfal Glades", [130] = "Silverpine Forest", [139] = "Eastern Plaguelands", [141] = "Teldrassil",
    [148] = "Darkshore", [215] = "Mulgore", [267] = "Hillsbrad Foothills", [331] = "Ashenvale", [357] = "Feralas", [361] = "Felwood",
    [400] = "Thousand Needles", [405] = "Desolace", [406] = "Stonetalon Mountains", [440] = "Tanaris", [490] = "Un'Goro Crater",
    [493] = "Moonglade", [618] = "Winterspring", [1377] = "Silithus", [1497] = "Undercity", [1519] = "Stormwind City",
    [1537] = "Ironforge", [1637] = "Orgrimmar", [1638] = "Thunder Bluff", [1657] = "Darnassus", [616] = "Mount Hyjal",
    [188] = "Shadowglen", [1769] = "Timbermaw Hold", [16593] = "Zephras Isle", [16591] = "Riverglades", [2817] = "Crystalsong Forest", [16560] = "City of Dalaran", [132] = "Coldridge Valley", [9] = "Northshire Valley",
}
-- which landmass a zone is on: crossing the sea is a boat ride, not a short flight
local KALIMDOR = { [14] = 1, [15] = 1, [16] = 1, [17] = 1, [141] = 1, [148] = 1, [188] = 1, [215] = 1, [331] = 1, [357] = 1,
    [361] = 1, [400] = 1, [405] = 1, [406] = 1, [440] = 1, [490] = 1, [493] = 1, [618] = 1, [1377] = 1, [1637] = 1, [1638] = 1,
    [1657] = 1, [616] = 1, [1769] = 1 }
local SKIP_AREAS = { [16651] = true, [16606] = true }      -- the Magram reputation grind; a battleground's turn-ins
-- a race's starting valley: only in that race's first route
local STARTER = { [9] = { Human = true }, [132] = { Dwarf = true, Gnome = true }, [188] = { NightElf = true },
                  ["16593:1"] = { Zephras = true } }
local function landOf(area) if area == 16593 then return "isle" end return KALIMDOR[area] and "K" or "EK" end
env.C_Map = env.C_Map or {}
env.C_Map.GetAreaInfo = function(a) return AREA[a] end

local RACES = { Human = 1, Dwarf = 3, NightElf = 4, Gnome = 7, Zephras = 1 }    -- Zephras Isle's start is open to every race
local function setRace(r) local id = RACES[r]; local nm = r == "Zephras" and "Human" or r; env.UnitRace = function() return nm, nm, id end end
setRace("Human")

---------------------------------------------------------------------------
-- The game's numbers
---------------------------------------------------------------------------
-- experience from level L to L+1 (Classic's formula)
local function xpToLevel(L)
    local diff = 0
    if L == 29 then diff = 1 elseif L == 30 then diff = 3 elseif L == 31 then diff = 6 elseif L >= 32 then diff = 5 * (L - 30) end
    return math.floor(((8 * L) + diff) * (45 + 5 * L) / 100 + 0.5) * 100
end
-- a quest's experience at its level (Classic's quests, by level), less when it's grey to you
local QXP = { { 1, 80 }, { 5, 300 }, { 10, 750 }, { 15, 1250 }, { 20, 1800 }, { 25, 2350 }, { 30, 2900 }, { 35, 3450 },
              { 40, 4050 }, { 45, 4650 }, { 50, 5250 }, { 55, 5900 }, { 60, 6600 } }
local function questXP(ql, pl)
    local base = QXP[#QXP][2]
    for i = 1, #QXP - 1 do
        local a, b = QXP[i], QXP[i + 1]
        if ql <= b[1] then base = a[2] + (b[2] - a[2]) * (ql - a[1]) / (b[1] - a[1]); break end
    end
    local d = pl - ql
    local f = d <= 5 and 1 or d == 6 and 0.8 or d == 7 and 0.6 or d == 8 and 0.4 or d == 9 and 0.2 or 0.1
    return base * f
end
-- experience for a kill of a mob your level (for grinding and the kills quests need)
local function mobXP(L) return 45 + 5 * L end

local RUN = 7                 -- yards a second on foot
local ZONE_TRIP = 600         -- seconds to get to another zone (flight or run)
local SEA_TRIP = 1500         -- seconds to another continent (boat or tram, and the flights each side)
local SAME_ZONE_HOP = 90      -- seconds between parts of one zone
local PER_QUEST = 40          -- seconds per quest for talking, looting, reading
local PER_KILL = 22           -- seconds a kill takes, rest included
local PER_ITEM = 30           -- seconds per item to collect (drop rates)
local MIN_BATCH = 6           -- a trip to another zone is for at least this many quests (fewer: half the value)
local STAY = 1.35             -- another zone must pay this much more than the current one to move on

-- how long a quest's objectives take, and the experience its kills give
local function objectiveCost(qid, pl)
    local o = QB.Field(qid, "objectives")
    local secs, kills = 0, 0
    if type(o) == "table" then
        for _, c in ipairs(type(o[1]) == "table" and o[1] or {}) do kills = kills + (tonumber(c[2]) or 1) end
        for _, g in ipairs(type(o[2]) == "table" and o[2] or {}) do secs = secs + PER_ITEM * 0.5 * (tonumber(g[2]) or 1) end
        for _, it in ipairs(type(o[3]) == "table" and o[3] or {}) do secs = secs + PER_ITEM * (tonumber(it[2]) or 1) end
    end
    secs = secs + kills * PER_KILL
    return math.min(secs, 900), kills * mobXP(pl) * 0.8
end

---------------------------------------------------------------------------
-- What an Alliance character can do
---------------------------------------------------------------------------
local ALLIANCE_BITS = { 1, 3, 4, 7 }      -- race IDs: Human, Dwarf, Night Elf, Gnome
local function hasBit(mask, id) return math.floor(mask / 2 ^ (id - 1)) % 2 == 1 end
local function allianceQuest(qid, race)
    local races = tonumber(QB.Field(qid, "requiredRaces")) or 0
    if races ~= 0 then
        local n = 0
        for _, id in ipairs(ALLIANCE_BITS) do if hasBit(races, id) then n = n + 1 end end
        if n == 0 then return false end                                  -- Horde only
        if n < #ALLIANCE_BITS and not (race and hasBit(races, RACES[race])) then return false end   -- other races' quest
    end
    if (tonumber(QB.Field(qid, "requiredClasses")) or 0) ~= 0 then return false end       -- class quests come in game, for your class
    return true
end
local function level(qid)
    local l = tonumber(QB.Field(qid, "questLevel"))
    if not l or l < 1 then l = tonumber(QB.Field(qid, "requiredLevel")) or 1 end
    return l
end
local function req(qid) return tonumber(QB.Field(qid, "requiredLevel")) or 1 end

-- the quest groups (zone parts), for a race
local function clusters(race)
    pns.Routes = {}                            -- no hand-written routes: every quest is the planner's
    setRace(race or "Human")
    QB.Forget()
    local out, byName = {}, {}
    for _, z in ipairs(QB.Zones()) do
        local qs = {}
        for _, q in ipairs(z.quests) do if allianceQuest(q, race) then qs[#qs + 1] = q end end
        local st = STARTER[z.area] or STARTER[z.area .. ":" .. z.part]
        local starterOk = not st or (race and st[race])
        if #qs >= 3 and not SKIP_AREAS[z.area] and starterOk then
            local key = st and (z.area .. ":" .. z.part) or z.name      -- a starting area stays apart from the rest of its zone
            local cl = byName[key]
            if not cl then
                cl = { area = z.area, part = z.part, name = z.name, quests = {}, lo = z.lo, hi = z.hi, land = landOf(z.area) }
                byName[key] = cl
                out[#out + 1] = cl
            end
            for _, q in ipairs(qs) do cl.quests[#cl.quests + 1] = q end
            cl.lo, cl.hi = math.min(cl.lo, z.lo), math.max(cl.hi, z.hi)
        end
    end
    return out
end

---------------------------------------------------------------------------
-- The character as it levels
---------------------------------------------------------------------------
local function newChar(L)
    return { L = L, xp = 0, done = {}, t = 0, zone = nil, area = nil, steps = {}, zones = {}, zoneList = {} }
end
local function copyChar(c)
    local n = newChar(c.L)
    n.xp, n.t, n.zone, n.area, n.land = c.xp, 0, c.zone, c.area, c.land
    for k, v in pairs(c.done) do n.done[k] = v end
    return n
end
local function gain(c, xp)
    c.xp = c.xp + xp
    while c.L < 60 and c.xp >= xpToLevel(c.L) do
        c.xp = c.xp - xpToLevel(c.L)
        c.L = c.L + 1
        c.leveled = (c.leveled or 0) + 1
    end
end
local function levelF(c) return c.L + c.xp / xpToLevel(c.L) end

-- prerequisites done, or in the set being planned
local function ready(qid, c, inSet)
    for _, p in ipairs(QB.Prereqs(qid)) do
        if not c.done[p] and not (inSet and inSet[p]) then return false end
    end
    return true
end

-- the quests of a group worth doing now
local function doable(cl, c)
    local list, inSet = {}, {}
    for _, q in ipairs(cl.quests) do
        local ql = level(q)
        if not c.done[q] and req(q) <= c.L + 1 and ql <= c.L + 3 and c.L - ql <= 6 then inSet[q] = true end
    end
    -- keep a quest only when what it waits on is done or in the set (in a few passes)
    for _ = 1, 4 do
        for q in pairs(inSet) do if not ready(q, c, inSet) then inSet[q] = nil end end
    end
    for _, q in ipairs(cl.quests) do if inSet[q] then list[#list + 1] = q end end
    return list
end

-- experience an hour from doing a group's quests now, and what goes into it
local function valueRaw(cl, c)
    local list = doable(cl, c)
    if #list < 2 then return 0 end
    local tasks = QB.Planner.build(list, nil, nil)
    if #tasks == 0 then return 0 end
    local order = QB.Planner.greedy(tasks, nil)
    local yards = QB.Planner.length(tasks, order, nil)
    local secs, xp = yards / RUN, 0
    for _, q in ipairs(list) do
        local s, kx = objectiveCost(q, c.L)
        secs = secs + PER_QUEST + s
        xp = xp + questXP(level(q), c.L) + kx
    end
    local trip = (c.zone == nil or c.zone == cl.name) and (c.area == cl.area .. ":" .. cl.part and 0 or SAME_ZONE_HOP)
        or (c.land and c.land ~= cl.land) and SEA_TRIP or ZONE_TRIP
    secs = secs + trip
    return xp / secs * 3600, list, xp, secs, trip
end

-- the same zone, level and finished quests give the same answer: remembered per character
local function tripTo(cl, c)
    return (c.zone == nil or c.zone == cl.name) and (c.area == cl.area .. ":" .. cl.part and 0 or SAME_ZONE_HOP)
        or (c.land and c.land ~= cl.land) and SEA_TRIP or ZONE_TRIP
end
local function value(cl, c)
    local done = 0
    for _, q in ipairs(cl.quests) do if c.done[q] then done = done + 1 end end
    local key = cl.name .. ":" .. cl.area .. ":" .. cl.part .. ":" .. c.L .. ":" .. done
    c.vcache = c.vcache or {}
    local hit = c.vcache[key]
    if not hit then
        local _, list, xp, secs, trip = valueRaw(cl, c)
        hit = { xp = xp or 0, secs = (secs or 0) - (trip or 0), list = list }
        c.vcache[key] = hit
    end
    if hit.xp == 0 then return 0 end
    local secs = hit.secs + tripTo(cl, c)
    return hit.xp / secs * 3600, hit.list, hit.xp, secs
end

-- step texts
local function addStep(c, s)
    s.lv = math.floor(levelF(c) * 10 + 0.5) / 10
    s.t = math.floor(c.t / 60 + 0.5)           -- minutes since the route's start
    c.steps[#c.steps + 1] = s
end

-- do a group's quests, in Pathfinder's planned order
local function run(c, cl, list)
    if c.zone ~= cl.name then
        if c.zone then
            local sea = c.land and c.land ~= cl.land
            c.t = c.t + (sea and SEA_TRIP or ZONE_TRIP)
            addStep(c, { act = "go", zone = cl.name, text = sea and ("Travel to %s: take the boat across, then fly or run."):format(cl.name)
                or ("Travel to %s (take a flight if you have the path)."):format(cl.name) })
        end
        c.land = cl.land
        c.zone = cl.name
        if not c.zones[cl.name] then c.zones[cl.name] = true; c.zoneList[#c.zoneList + 1] = cl.name end
        c.hearth = c.hearth or {}
        if #list >= 8 and not c.hearth[cl.name] and c.L >= 6 then
            c.hearth[cl.name] = true
            addStep(c, { act = "note", text = ("Set your hearthstone at the inn nearest %s's quests."):format(cl.name) })
        end
    elseif c.area ~= cl.area .. ":" .. cl.part then
        c.t = c.t + SAME_ZONE_HOP
    end
    c.area = cl.area .. ":" .. cl.part
    if not c.zones[cl.name] then c.zones[cl.name] = true; c.zoneList[#c.zoneList + 1] = cl.name end
    local steps = QB.ZoneRoute(list) or {}
    local xpOf, timeOf = {}, {}
    for _, q in ipairs(list) do
        local s, kx = objectiveCost(q, c.L)
        timeOf[q], xpOf[q] = s, kx
    end
    local tasks = QB.Planner.build(list, nil, nil)
    local _, yards = QB.Plan(list, nil)
    local walkPer = (yards or 0) / RUN / math.max(1, #steps)
    for _, s in ipairs(steps) do
        c.t = c.t + walkPer + 10
        local qids = s.qids or { s.qid }
        if s.act == "complete" then
            for _, q in ipairs(qids) do
                if timeOf[q] then c.t = c.t + timeOf[q]; gain(c, xpOf[q] or 0); timeOf[q] = nil end
            end
        elseif s.act == "turnin" and s.qid and not c.done[s.qid] then
            c.t = c.t + PER_QUEST * 0.5
            gain(c, questXP(level(s.qid), c.L))
            c.done[s.qid] = true
        elseif s.act == "accept" then
            c.t = c.t + PER_QUEST * 0.5
        end
        if s.qid and (s.act == "accept" or s.act == "turnin" or s.act == "complete") and not s.zone then s.zone = cl.name end
        addStep(c, s)
        if c.leveled then
            c.leveled = nil
            if c.L % 2 == 0 and c.L >= 4 then
                addStep(c, { act = "note", train = c.L, text = ("Level %d: visit your class trainer for new spells when you're next in town."):format(c.L) })
            end
        end
    end
    -- quests in a prerequisite chain from elsewhere count as done once they're in the steps,
    -- and every quest this visit took on is handled (one with no hand-in step won't be offered again)
    for _, s in ipairs(steps) do if s.act == "turnin" and s.qid then c.done[s.qid] = true end end
    for _, q in ipairs(list) do c.done[q] = true end
end

-- grind to a level where there aren't enough quests
local function grind(c, toL, cls)
    local best, bestD
    for _, cl in ipairs(cls) do
        local mid = (cl.lo + cl.hi) / 2
        local d = math.abs(mid - c.L)
        if not bestD or d < bestD then best, bestD = cl, d end
    end
    local need = xpToLevel(c.L) - c.xp
    local kills = math.ceil(need / mobXP(c.L))
    c.t = c.t + kills * PER_KILL
    gain(c, need)
    addStep(c, { act = "go", text = ("Quests run short: kill level %d-%d mobs in %s to level %d (about %d kills), or run a dungeon (Codex lists them)."):format(
        c.L - 1, c.L + 1, best and best.name or "this zone", c.L, kills), zone = best and best.name })
end

-- plan one route from character c until level hi; firstCluster forces where it starts
local function plan(c, hi, cls, firstCluster, startZone)
    local guard = 0
    while c.L < hi and guard < 60 do
        guard = guard + 1
        local best, bestV, bestList
        for _, cl in ipairs(cls) do
            local ok = true
            if firstCluster and #c.steps == 0 then ok = cl == firstCluster end
            if startZone and #c.steps == 0 then ok = cl.name == startZone end
            if ok then
                local v, list = value(cl, c)
                if c.zone == cl.name then v = v * STAY
                elseif list and #list < 3 then v = 0                 -- not worth the trip for one or two
                elseif list and #list < MIN_BATCH then v = v * 0.5 end
                if v > (bestV or 0) then best, bestV, bestList = cl, v, list end
            end
        end
        if os.getenv("PLAN_DEBUG") and tonumber(os.getenv("PLAN_DEBUG")) == c.L and not firstCluster and not startZone then
            local rows = {}
            for _, cl in ipairs(cls) do
                local v, list = value(cl, c)
                if v > 0 then rows[#rows + 1] = { cl.name, math.floor(v), #list, cl.lo .. "-" .. cl.hi, #cl.quests } end
            end
            table.sort(rows, function(x, y) return x[2] > y[2] end)
            io.stderr:write(("L%.1f in %s:"):format(levelF(c), tostring(c.zone)))
            for i = 1, math.min(8, #rows) do io.stderr:write((" %s=%d/%dq(%s,%d)"):format(unpack(rows[i]))) end
            io.stderr:write("\n")
        end
        if not best then
            if firstCluster or startZone then return nil end
            grind(c, c.L + 1, cls)
        else
            run(c, best, bestList)
            if #c.steps > 285 then break end
        end
        firstCluster, startZone = nil, nil
    end
    return c
end

---------------------------------------------------------------------------
-- Brackets and routes
---------------------------------------------------------------------------
local BRACKETS = { { 1, 6 }, { 6, 12 }, { 12, 18 }, { 18, 24 }, { 24, 30 }, { 30, 35 }, { 35, 40 },
                   { 40, 45 }, { 45, 50 }, { 50, 55 }, { 55, 60 } }
local START = { { race = "Human", zone = "Northshire Valley" }, { race = "Dwarf", zone = "Coldridge Valley" },
                { race = "NightElf", zone = "Shadowglen" }, { race = "Zephras", zone = "Zephras Isle" } }

local routes = {}
local function slug(s) return (s:lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")) end
local function finish(c, lo, label)
    local first = c.zoneList[1] or "?"
    local zones = table.concat(c.zoneList, ", ")
    local title = ("%d-%d %s"):format(lo, c.L, zones)
    if #title > 40 then title = ("%d-%d %s and more"):format(lo, c.L, first):sub(1, 40) end
    local r = { id = ("a_%02d_%s%s"):format(lo, slug(first), label or ""), title = title, faction = "Alliance",
                author = "RUIN planner", zone = first, levels = lo .. "-" .. c.L, startLevel = lo, endLevel = c.L,
                minutes = math.floor(c.t / 60 + 0.5), zones = c.zoneList, steps = c.steps, plan = true }
    local xp = 0
    for L = lo, c.L - 1 do xp = xp + xpToLevel(L) end
    r.xph = math.floor(xp / math.max(1, c.t) * 3600 / 100) * 100
    return r
end

local mainline = {}                  -- bracket -> the character after its best route (what later brackets start from)
local Lua51Clusters = {}
local function clustersFor(race)
    if not Lua51Clusters[race or "-"] then Lua51Clusters[race or "-"] = clusters(race) end
    QB.Forget(); setRace(race or "Human"); pns.Routes = {}
    return Lua51Clusters[race or "-"]
end

local bi = 0
while true do
    bi = bi + 1
    local b = BRACKETS[bi]
    local prevEnd = mainline[bi - 1] and mainline[bi - 1].L
    if not b then
        if not prevEnd or prevEnd >= 60 then break end
        b = { prevEnd, 60 }
        BRACKETS[bi] = b
    end
    local lo, hi = b[1], b[2]
    if prevEnd and prevEnd < lo then lo = prevEnd end
    if lo >= 60 then break end
    local made = {}
    if lo == 1 then
        for _, s in ipairs(START) do
            -- a starting route stays at home: the starting area and its race's own zone (no boat at level 4)
            local HOME = { Human = "Elwynn Forest", Dwarf = "Dun Morogh", NightElf = "Teldrassil", Zephras = "Zephras Isle" }
            local cls = {}
            for _, cl in ipairs(clustersFor(s.race)) do
                if cl.name == s.zone or cl.name == HOME[s.race] then cls[#cls + 1] = cl end
            end
            local c = plan(newChar(1), hi, cls, nil, s.zone)
            if not c then
                local names = {}
                for _, cl in ipairs(cls) do if cl.lo <= 6 then names[#names + 1] = cl.name .. " " .. cl.lo .. "-" .. cl.hi .. " (" .. #doable(cl, newChar(1)) .. ")" end end
                io.stderr:write("no start route for " .. s.zone .. "; low groups: " .. table.concat(names, ", ") .. "\n")
            end
            if c then
                local r = finish(c, 1, "")
                made[#made + 1] = r
                if not mainline[bi] or s.zone == "Northshire Valley" then mainline[bi] = c end
            end
        end
    else
        local cls = clustersFor("Human")
        local from = mainline[bi - 1] or newChar(lo)
        local c0 = copyChar(from)
        c0.L = math.max(c0.L, lo)
        local c = plan(copyChar(c0), hi, cls)
        if c then
            local r = finish(c, lo, "")
            made[#made + 1] = r
            mainline[bi] = c
            -- up to two others that start somewhere else
            local tried = { [c.zoneList[1] or ""] = true }
            local opts = {}
            for _, cl in ipairs(cls) do
                if not tried[cl.name] then
                    local v = value(cl, c0)
                    if v > 0 then opts[#opts + 1] = { cl = cl, v = v } end
                end
            end
            table.sort(opts, function(a, b2) return a.v > b2.v end)
            local n = 0
            for _, o in ipairs(opts) do
                if n >= 2 then break end
                if not tried[o.cl.name] then
                    tried[o.cl.name] = true
                    local alt = plan(copyChar(c0), hi, cls, o.cl)
                    if alt and #alt.steps > 10 then
                        local ra = finish(alt, lo, "_alt" .. (n + 1))
                        local same, inBest = 0, {}
                        for _, z in ipairs(r.zones) do inBest[z] = true end
                        for _, z in ipairs(ra.zones) do if inBest[z] then same = same + 1 end end
                        local differs = same / math.max(1, #ra.zones) <= 0.6
                        if ra.xph >= r.xph * 0.75 and differs then made[#made + 1] = ra; n = n + 1 end
                    end
                end
            end
        end
    end
    for _, r in ipairs(made) do routes[#routes + 1] = r end
    io.stderr:write(("%d-%d: %d routes%s\n"):format(lo, hi, #made, made[1] and (" (best " .. made[1].title .. ", " .. made[1].minutes .. " min, " .. #made[1].steps .. " steps)") or ""))
end

-- last step: 1-3 routes to start next, best first (the ones starting at or just below where you finish)
for _, r in ipairs(routes) do
    local nexts = {}
    for _, o in ipairs(routes) do
        if o ~= r and o.startLevel > r.startLevel and o.startLevel <= r.endLevel + 1 and o.startLevel >= r.endLevel - 3 then nexts[#nexts + 1] = o end
    end
    -- a route that carries on where this one ends comes first (no trip), then the later start, then the faster
    local endZone = r.zones[#r.zones]
    table.sort(nexts, function(a, b)
        local ah, bh = a.zones[1] == endZone, b.zones[1] == endZone
        if ah ~= bh then return ah end
        if a.startLevel ~= b.startLevel then return a.startLevel > b.startLevel end
        return a.xph > b.xph
    end)
    local ids, names = {}, {}
    for i = 1, math.min(3, #nexts) do ids[i] = nexts[i].id; names[i] = nexts[i].title end
    if #ids > 0 then
        r.next = ids
        r.steps[#r.steps + 1] = { act = "note", next = ids, lv = r.endLevel, t = r.minutes,
                                  text = "Route done. Start next: " .. table.concat(names, "; ") }
    else
        r.steps[#r.steps + 1] = { act = "note", lv = r.endLevel, t = r.minutes, text = "Route done: you've reached the top level." }
    end
end

---------------------------------------------------------------------------
-- Write Routes.lua
---------------------------------------------------------------------------
local function q(s) return ("%q"):format(s) end
local src = io.open(PF .. "/Routes.lua"):read("*a")
local head = src:sub(1, src:find("ns.Routes = {", 1, true) - 1)
-- and everything after the routes table (the dungeon quest index, quest hints) stays as it is
local tail = ""
do
    local open = src:find("ns.Routes = {", 1, true) + #"ns.Routes = "
    local depth, i = 0, open
    while i <= #src do
        local ch = src:sub(i, i)
        if ch == "{" then depth = depth + 1
        elseif ch == "}" then depth = depth - 1; if depth == 0 then tail = src:sub(i + 1); break end
        elseif ch == "-" and src:sub(i, i + 1) == "--" then      -- skip a comment (it may hold braces)
            local e = src:find("\n", i, true) or #src
            i = e
        elseif ch == '"' then                                   -- skip a string
            local j = i + 1
            while j <= #src and src:sub(j, j) ~= '"' do if src:sub(j, j) == "\\" then j = j + 1 end; j = j + 1 end
            i = j
        end
        i = i + 1
    end
end
-- keep the routes that aren't Alliance levelling (Horde, the sleeping bag runs, the dungeon)
local keep = {}
for id in src:gmatch('\n    {\n        id = "([^"]+)"') do
    local block = src:match('id = "' .. id .. '"[^\n]*')
    if not block:find('faction = "Alliance"', 1, true) or id == "hall_of_thanes" or id:find("^cozy_sleeping_bag") then
        keep[#keep + 1] = id
    end
end
local keptText = {}
for _, id in ipairs(keep) do
    local s, e = src:find("\n    {\n        id = \"" .. id .. "\"", 1, true)
    if s then
        local depth, i = 0, s + 1
        local close
        while i <= #src do
            local ch = src:sub(i, i)
            if ch == "{" then depth = depth + 1 elseif ch == "}" then depth = depth - 1; if depth == 0 then close = i; break end end
            i = i + 1
        end
        if close then keptText[#keptText + 1] = src:sub(s + 1, close) .. "," end
    end
end

local lines = {}
local function w(s) lines[#lines + 1] = s end
head = head:gsub("%-%- Alliance 1%-30 routes checked.-\nlocal ADDON, ns = %.%.%.", [[
-- Alliance 1-60 levelling routes are made by RUIN's route planner
-- (tests/tools/plan_routes.lua) from RUIN Quest Data: each picks, level by
-- level, the zone's quests that give the most experience an hour solo, moves
-- from zone to zone the way the game expects, and ends by naming 1-3 routes
-- to start next. Steps carry lv (your level about then) and t (minutes since
-- the route's start), estimates for the time budget. Don't edit these routes
-- by hand: change the planner and run it again.
local ADDON, ns = ...]])
w(head .. "ns.Routes = {")
w("")
w("    -- planned Alliance levelling routes, " .. os.date("%Y-%m-%d"))
for _, r in ipairs(routes) do
    local zs = {}
    for _, z in ipairs(r.zones) do zs[#zs + 1] = q(z) end
    local nx = {}
    for _, id in ipairs(r.next or {}) do nx[#nx + 1] = q(id) end
    w(("    {\n        id = %s, title = %s, faction = \"Alliance\", author = \"RUIN planner\", zone = %s, levels = %s, plan = true,"):format(
        q(r.id), q(r.title), q(r.zone), q(r.levels)))
    w(("        startLevel = %d, endLevel = %d, minutes = %d, xph = %d, zones = { %s }, next = { %s },"):format(
        r.startLevel, r.endLevel, r.minutes, r.xph, table.concat(zs, ", "), table.concat(nx, ", ")))
    w("        steps = {")
    for _, s in ipairs(r.steps) do
        local parts = { "act = " .. q(s.act) }
        if s.quest then parts[#parts + 1] = "quest = " .. q(s.quest) end
        if s.qid then parts[#parts + 1] = "qid = " .. s.qid end
        if s.qids and #s.qids > 1 then
            local t = {}
            for _, x in ipairs(s.qids) do t[#t + 1] = tostring(x) end
            parts[#parts + 1] = "qids = { " .. table.concat(t, ", ") .. " }"
        end
        if s.text and s.text ~= "" then parts[#parts + 1] = "text = " .. q(s.text) end
        if s.zone and (s.act == "go") then parts[#parts + 1] = "zone = " .. q(s.zone) end
        if s.train then parts[#parts + 1] = "train = " .. s.train end
        if s.next then
            local t = {}
            for _, x in ipairs(s.next) do t[#t + 1] = q(x) end
            parts[#parts + 1] = "next = { " .. table.concat(t, ", ") .. " }"
        end
        parts[#parts + 1] = ("lv = %s, t = %d"):format(tostring(s.lv), s.t or 0)
        w("            { " .. table.concat(parts, ", ") .. " },")
    end
    w("        },")
    w("    },")
end
w("")
w("    -- routes that aren't Alliance levelling")
for _, t in ipairs(keptText) do w(t) end
w("}" .. tail:gsub("\n+$", ""))
local fh = assert(io.open(OUT, "w"))
fh:write(table.concat(lines, "\n"), "\n")
fh:close()
for _, r in ipairs(routes) do
    for _, z in ipairs(r.zones) do if z:find("^Zone %d") then io.stderr:write("no name for " .. z .. " (" .. r.id .. ")\n") end end
end
io.stderr:write(("wrote %d planned routes (+%d kept) to %s\n"):format(#routes, #keptText, OUT))
