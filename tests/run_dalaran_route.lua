-- Pathfinder 0.5.2: City of Dalaran's route. The Forever database files the
-- attunement and follow-up quests outside the dungeon and records no order
-- between them, so Pathfinder adds the order by hand: the attunement first,
-- the dungeon's quests, then the follow-up once Heart of Disruption is in.
-- Quests without a giver in the database get one from the hint table.
local alice, check, errorsSoFar = T.alice, T.check, T.errorsSoFar
local here = T.here or "."
local fakeQuestieDB = dofile(here .. "/fake_questiedb.lua")

print("Pathfinder: City of Dalaran route")
do
    local done = {}
    local undo = fakeQuestieDB(alice, done)
    local PF = alice.env.RUIN_API:GetModule("Pathfinder")

    local list = PF:DungeonQuests("City of Dalaran")
    local by = {}
    for _, q in ipairs(list or {}) do by[q.id] = q end
    check(by[92457] and by[92458] and by[92459] and by[96987], "the street quests, the follow-up and the giverless tome are all listed")
    check(not by[96984], "the Horde version stays out for an Alliance character")
    check(by[92458] and by[92458].pre[1] == 92432, "Heart of Disruption needs the attunement first (" .. tostring(by[92458] and by[92458].pre[1]) .. ")")
    check(by[92459] and by[92459].pre[#by[92459].pre] == 92458, "the follow-up needs Heart of Disruption")
    check(by[96987] and by[96987].inside, "the tome is picked up inside")

    local r = PF:DungeonRoute("City of Dalaran")
    local seq, pos = {}, {}
    for i, s in ipairs(r and r.steps or {}) do
        seq[#seq + 1] = s.act .. ":" .. (s.quest or "")
        pos[seq[#seq]] = pos[seq[#seq]] or i
    end
    local function before(a, b) return pos[a] and pos[b] and pos[a] < pos[b] end
    check(seq[1] == "accept:Alliance Attunement", "the route opens with the attunement (" .. tostring(seq[1]) .. ")")
    check(before("turnin:Alliance Attunement", "accept:Dalaran Heart"), "Modera's quests come after it")
    check(before("turnin:Dalaran Heart", "accept:Dalaran Follow-up") and before("accept:Dalaran Follow-up", "turnin:Dalaran Follow-up"),
          "the follow-up is taken after Heart of Disruption is handed in")
    local tome
    for _, s in ipairs(r and r.steps or {}) do if s.act == "accept" and s.quest == "Dalaran Tome" then tome = s end end
    check(tome and tome.text:find("Rexxie Copperclutch", 1, true), "the tome's giver comes from the hint table")
    for _, s in ipairs(r and r.steps or {}) do
        check(not (s.text or ""):find("doesn't say", 1, true), "no step says Questie doesn't know (" .. s.act .. " " .. (s.quest or "") .. ")")
    end

    undo()
    errorsSoFar("dalaran route")
end
