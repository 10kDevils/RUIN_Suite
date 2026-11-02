-- Pathfinder reading the standalone QuestieDB addon (contract 4).
-- Needs QuestieDB's source tree (for its offline client emulator) and an
-- installed QuestieDB folder: run from the QuestieDB source root as
--   lua <suite>/tests/run_questiedb.lua <folder holding QuestieDB/> <suite>/RUIN_Pathfinder/Questie.lua
local RFP = arg[1]
local client = dofile("emulator/client.lua")
local meta = dofile("emulator/metadata.lua")
client.install({ expansion = "Forever" })
meta.load(RFP .. "/QuestieDB/QuestieDB_Forever.toc", "QuestieDB")
local lib = meta.loadAddon(RFP .. "/QuestieDB/QuestieDB_Forever.toc", "QuestieDB", RFP .. "/QuestieDB")
print("contract", lib.contractVersion, #lib.Quest.GetAllIds())
-- load Pathfinder's bridge
local ns = {}
local chunk = assert(loadfile(arg[2]))
chunk("RUIN_Pathfinder", ns)
local QB = ns.QB
print("source", QB.Source())
for _, id in ipairs({ 176, 33, 7, 783 }) do
  local q = QB.Quest(id)
  if q then
    print(id, q.name, q.level, q.req, table.concat(q.starts, "/"), table.concat(q.ends, "/"), q.objectives[1], q.zone)
    local s = QB.Spot(id, "start")
    if s then print("  start", s.map, s.x, s.y, s.name) end
    local o = QB.Spots(id, "objective")
    print("  objective spots", #o, o[1] and o[1].map)
  else print(id, "missing") end
end
_G.C_QuestLog = { IsQuestFlaggedCompleted = function() return false end }
_G.C_Map = { GetMapInfo = function(m) return { name = "Elwynn Forest" } end }
local r, why = QB.DraftRoute(1429, 6, 0.4, 0.6)
print("draft", r and #r.steps or why)
