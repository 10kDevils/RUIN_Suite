local here = os.getenv("QA_TESTS") or "."
dofile(here .. "/harness.lua")
Server.guilds["Ashen Order"] = { { name = "Alice Ash", rank = 0, guid = "Player-1-00000001" } }
local alice = Server:NewClient({ name = "Alice Ash", guid = "Player-1-00000001", guild = "Ashen Order", rank = 0, modules = { "RUIN_Finder" } })
Server:Advance(10)
Server:Slash(alice, "key create RUIN")
Server:Advance(30)
local Comms = alice.ns.Comms
local ours, order = {}, {}
for _, ch in ipairs(Comms.ChannelList()) do order[#order+1] = Comms.IsOurChannel(ch.name) and "RUIN" or ch.name; if Comms.IsOurChannel(ch.name) then ours[#ours+1] = ch.name end end
print("order", table.concat(order, ","))
local prints = {}
local realPrint = alice.ns.Print
alice.ns.Print = function(self, msg, ...) prints[#prints+1] = msg; return realPrint(self, msg, ...) end
for i = 1, 3 do Server.fire(alice, "CHAT_MSG_CHANNEL_NOTICE", "WRONG_PASSWORD", "", "", "5. " .. (ours[1] or "?"), "", "", 0, 5, ours[1] or "?") end
Server.fire(alice, "CHAT_MSG_CHANNEL_NOTICE", "WRONG_PASSWORD", "", "", "1. General", "", "", 0, 1, "General")
local n = 0 for _, p in ipairs(prints) do if tostring(p):find("wrong password") then n = n + 1 end end
print("wrong-password warnings", n)
print("errors", #Server.errors, table.concat(Server.errors, " // "))
