-- QA (optimization round 3, OPT3-5): QB.Spots answers for many quests (hits, misses, a bad id,
-- the 5-minute miss memory, ForgetSpots and Forget), with the bundled quest data loaded.
-- Run from <build>/tests: QA_TESTS=<build>/tests RUIN_CORE_DIR=<build>/RUIN_Core texlua qa/run51.lua <this>
local here = os.getenv("QA_TESTS") or "."
dofile(here .. "/harness.lua")
Server.guilds["Ashen Order"] = { { name = "Alice Ash", rank = 0, guid = "Player-1-00000001" } }
local alice = Server:NewClient({ name = "Alice Ash", guid = "Player-1-00000001", guild = "Ashen Order", rank = 0, modules = { "RUIN_Pathfinder" } })
Server:Advance(10)
local env = alice.env
local core = os.getenv("RUIN_CORE_DIR")
for _, f in ipairs({ "Data.lua", "Horde.lua" }) do
    local chunk = assert(loadfile(core .. "/../RUIN_Pathfinder/QuestData/" .. f)); setfenv(chunk, env); chunk()
end
local QB = env.RUIN_API:GetModule("Pathfinder").QB
QB.Forget()
local function sig(l)
    local t = {}
    for i, s in ipairs(l) do if i > 5 then break end t[#t + 1] = ("%s@%.3f,%.3f"):format(tostring(s.map), s.x, s.y) end
    return #l .. ":" .. table.concat(t, ";")
end
local ids = { 2, 7, 33, 60, 99999, 0, "7", "x", nil, 176, 783, 5, 9999999 }
local function round(tag)
    local out = {}
    for _, which in ipairs({ "start", "finish", "objective" }) do
        for i = 1, #ids + 1 do out[#out + 1] = sig(QB.Spots(ids[i], which)) end
    end
    print(tag, table.concat(out, " | "))
end
round("first"); round("again")
Server:Advance(200); round("200 s")
Server:Advance(200); round("400 s")
QB.ForgetSpots(7); round("forgot 7")
QB.Forget(); round("forgot all")
local e1, e2 = QB.Spots(99999, "start"), QB.Spots(99999, "start")
print("miss lists empty", #e1, #e2, next(e1) == nil)
print("errors", #Server.errors, table.concat(Server.errors, " // "))
