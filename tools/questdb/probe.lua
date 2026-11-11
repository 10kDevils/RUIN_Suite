dofile(arg[3])
local L = rawget(_G, "LibQuestieDB") or LibQuestieDB_NS
print("contract", L.contractVersion, "flavor", L.flavor)
local Q = L.Quest
print("Quest api", Q and Q.Get, Q and Q.GetAllIds)
local ids = Q.GetAllIds(true)
local n = 0
for _ in pairs(ids) do n = n + 1 end
print("quests", n)
print("2:", Q.Get(2, "name"), Q.Get(2, "questLevel"))
local sb = Q.Get(2, "startedBy")
print("startedBy", sb and sb[1] and sb[1][1])
