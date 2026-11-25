-- QA (optimization round 3, OPT3-4): which channel texts count as RUIN's, before and after the
-- org's channels change (key rotation), asked twice each so remembered answers are compared too.
-- Run from <build>/tests: QA_TESTS=<build>/tests RUIN_CORE_DIR=<build>/RUIN_Core texlua qa/run51.lua <this>
local here = os.getenv("QA_TESTS") or "."
dofile(here .. "/harness.lua")
Server.guilds["Ashen Order"] = { { name = "Alice Ash", rank = 0, guid = "Player-1-00000001" } }
local alice = Server:NewClient({ name = "Alice Ash", guid = "Player-1-00000001", guild = "Ashen Order", rank = 0, modules = { "RUIN_Finder" } })
Server:Advance(10)
local Comms = alice.ns.Comms
local function ask(tag, list)
    local out = {}
    for _, t in ipairs(list) do out[#out + 1] = (Comms.IsOurChannel(t) and "Y" or "n") .. (Comms.IsOurChannel("x", t) and "Y" or "n") end
    print(tag, table.concat(out, " "))
end
local fixed = { "1. General", "2. Trade - City", "General", "", "LookingForGroup" }
ask("no key", fixed)
Server:Slash(alice, "key create RUIN")
Server:Advance(30)
local function names()
    local l = {}
    for _, ch in ipairs(Comms.ChannelList()) do l[#l + 1] = ch.name; l[#l + 1] = "5. " .. ch.name; l[#l + 1] = ch.name:upper() end
    return l
end
local first = names()
for _, f in ipairs(fixed) do first[#first + 1] = f end
ask("key", first); ask("key again", first)
Server:Slash(alice, "key rotate")
Server:Advance(60)
local second = names()
ask("rotated: old", first); ask("rotated: new", second); ask("rotated: new again", second)
for i = 1, 300 do Comms.IsOurChannel("filler " .. i) end
ask("after filler", second)
local ord = {}
for _, ch in ipairs(Comms.ChannelList()) do ord[#ord + 1] = Comms.IsOurChannel(ch.name) and "RUIN" or ch.name end
print("order", table.concat(ord, ","))
-- a text asked about (a "no") before it becomes a RUIN channel name must turn "yes"
local probe = { "zzprobechan", "5. ZZProbeChan", "ZZPROBECHAN - x" }
ask("probe before", probe)
Comms:SetChannel("OFFICERS", "zzprobechan", "pw")
Server:Advance(5)
ask("probe after", probe)
print("errors", #Server.errors, table.concat(Server.errors, " // "))
