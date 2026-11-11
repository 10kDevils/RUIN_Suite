-- Pathfinder's route planner: pick-ups together, overlapping objectives
-- together, hand-ins together, the walk as short as it can be.
local alice, eve, check, errorsSoFar = T.alice, T.eve, T.check, T.errorsSoFar

print("Pathfinder: route planner")
do
    local pf = alice.env.RUIN_API:GetModule("Pathfinder")
    local QB = pf.QB
    local real = { Spots = QB.Spots, Spot = QB.Spot, Prereqs = QB.Prereqs, DoText = QB.DoText, Quest = QB.Quest,
                   AcceptText = QB.AcceptText, TurninText = QB.TurninText, Field = QB.Field }
    local function stub(world)
        QB.Spots = function(q, which) local w = world[q]; return w and w[which] and { w[which] } or {} end
        QB.Spot = function(q, which) local w = world[q]; return w and w[which] end
        QB.Prereqs = function(q) return world[q] and world[q].pre or {} end
        QB.DoText = function(q) return world[q] and world[q].objective and "do it" or "" end
        QB.Quest = function(q) return { name = "Q" .. q } end
        QB.AcceptText = function() return "" end
        QB.TurninText = function() return "" end
        QB.Field = function() return 1 end
    end
    local M_ = 1429
    local function at(x, y) return { map = M_, x = x, y = y } end
    local hub = at(0.50, 0.50)
    -- three quests from the same hub; two kill in the same field, one far away; all hand in at the hub
    local world = {
        [1] = { start = hub, objective = at(0.20, 0.20), finish = hub },
        [2] = { start = at(0.501, 0.50), objective = at(0.21, 0.21), finish = hub },
        [3] = { start = at(0.50, 0.501), objective = at(0.80, 0.30), finish = hub },
        [4] = { start = hub, objective = at(0.79, 0.31), finish = hub, pre = { 1 } },   -- opens when 1 is handed in
    }
    stub(world)
    local plan, length, before = QB.Plan({ 1, 2, 3, 4 }, hub)
    local seq = {}
    for _, t in ipairs(plan) do seq[#seq + 1] = t.kind:sub(1, 1) .. t.qid end
    local s = table.concat(seq, " ")
    check(#plan == 12, "every quest gets a pick-up, objectives and a hand-in (" .. s .. ")")
    check(s:find("^a%d a%d a%d"), "the hub's quests are picked up together first (" .. s .. ")")
    local pos = {}
    for i, t in ipairs(seq) do pos[t] = i end
    check(math.abs(pos.c1 - pos.c2) == 1, "objectives in the same field are done one after the other (" .. s .. ")")
    check(pos.a4 > pos.t1, "a quest is picked up only after the one that opens it is handed in (" .. s .. ")")
    check(math.abs(pos.c3 - pos.c4) == 1 or pos.a4 > pos.c3, "the far objectives are done on one trip (" .. s .. ")")
    check(length <= before + 0.01, "the second pass never makes the walk longer (" .. math.floor(before) .. " -> " .. math.floor(length) .. " yd)")

    -- a big set stays quick
    local big, ids = {}, {}
    math.randomseed(7)
    for q = 100, 159 do
        big[q] = { start = at(0.4 + math.random() * 0.2, 0.4 + math.random() * 0.2), objective = at(math.random(), math.random()),
                   finish = at(0.4 + math.random() * 0.2, 0.4 + math.random() * 0.2) }
        if q > 100 and q % 5 == 0 then big[q].pre = { q - 1 } end
        ids[#ids + 1] = q
    end
    stub(big)
    local t0 = os.clock()
    local bplan, blen, bbefore = QB.Plan(ids, hub)
    local took = os.clock() - t0
    check(#bplan == 180 and blen <= bbefore, "60 quests plan to 180 stops, the second pass only shortening it (" .. math.floor(bbefore) .. " -> " .. math.floor(blen) .. " yd)")
    check(took < 2, ("and it's quick (%.2f s)"):format(took))
    -- the order always holds
    local seen, ok = {}, true
    for _, t in ipairs(bplan) do
        if t.kind == "complete" and not seen["accept" .. t.qid] then ok = false end
        if t.kind == "turnin" and not seen["accept" .. t.qid] then ok = false end
        if t.kind == "accept" then for _, p in ipairs(big[t.qid].pre or {}) do if not seen["turnin" .. p] then ok = false end end end
        seen[t.kind .. t.qid] = true
    end
    check(ok, "pick-up before objectives before hand-in, and earlier quests first, every time")

    for k, v in pairs(real) do QB[k] = v end

    -- the atlas: where quests really are, learned while playing and shared
    local note = pf.AtlasNote
    check(note("s", 9001, 1429, 0.40, 0.60, true), "a pick-up is noted where it happened")
    check(note("s", 9001, 1429, 0.4005, 0.6005, true), "a second one close by refines it")
    local spots = QB.Spots(9001, "start")
    check(#spots == 1 and spots[1].seen == 2 and math.abs(spots[1].x - 0.40025) < 0.0001, "seen twice, the atlas is where the quest starts, even without Questie")
    note("s", 9001, 1429, 0.90, 0.10, true)
    spots = QB.Spots(9001, "start")
    check(math.abs(spots[1].x - 0.40025) < 0.0001, "one odd sighting doesn't move a place seen before")
    note("s", 9001, 1429, 0.9001, 0.1001, true)
    spots = QB.Spots(9001, "start")
    check(math.abs(spots[1].x - 0.90005) < 0.0001, "but seen as often somewhere else, the new place takes over (WoW Forever moved it)")
    note("s", 9001, 1429, 0.40, 0.60, true); note("s", 9001, 1429, 0.40, 0.60, true); note("s", 9001, 1429, 0.40, 0.60, true)
    for k = 1, 3 do note("o", 9001, 1429, 0.1 + k * 0.05, 0.2, true) end
    note("o", 9001, 1429, 0.15, 0.2, true)
    local o = QB.Spots(9001, "objective")
    check(#o == 3 and o[1].seen == 2, "objective progress builds a list of places (a repeat counts up)")
    check(pf.AtlasCounts().s >= 1, "/path atlas counts what's known")
    -- shared with RUIN: another member learns it
    Server:Advance(400)
    local eveAtlas = function() return eve.env.RUIN_PathfinderDB.atlas end
    check(eveAtlas() and eveAtlas().s[9001] and eveAtlas().o[9001], "sightings are shared with RUIN members")
    errorsSoFar("route planner")
end
