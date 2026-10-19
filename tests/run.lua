-- RUIN Core integration tests
local here = arg[0]:match("^(.*)/") or "."
dofile(here .. "/harness.lua")

local pass, fail = 0, 0
local function check(cond, label)
    if cond then pass = pass + 1; print("  ok   " .. label)
    else fail = fail + 1; print("  FAIL " .. label) end
end
local function chatHas(c, needle)
    for _, line in ipairs(c.chat) do if line:find(needle, 1, true) then return true end end
    return false
end
local function chatCount(c, needle)
    local n = 0
    for _, line in ipairs(c.chat) do if line:find(needle, 1, true) then n = n + 1 end end
    return n
end
local function key(c) return c.env.RUIN_DB and c.env.RUIN_DB.orgKey end
local function errorsSoFar(label)
    check(#Server.errors == 0, label .. ": no Lua errors")
    for _, e in ipairs(Server.errors) do print("       " .. e) end
    Server.errors = {}
end

---------------------------------------------------------------------------
print("Unit: serializer, base64, hash, key encoding")
---------------------------------------------------------------------------
local ns = {}
do
    local env = setmetatable({}, { __index = _G })
    local chunk = assert(loadfile((arg[1] or os.getenv("RUIN_CORE_DIR") or ((arg[0]:match("^(.*)/") or ".") .. "/../RUIN_Core")) .. "/Util.lua"))
    setfenv(chunk, env)
    chunk("RUIN_Core", ns)
end
local sample = { a = "hi|there\030x", n = 42, f = -3.5, t = true, b = false, list = { "x", "y", { deep = "z" } },
                 big = 1700000000123, ["key with space"] = "", [7] = "seven", utf = "Ragnarös·Tag" }
local back, err = ns.Deserialize(ns.Serialize(sample))
check(err == nil, "deserialize without error")
check(back and back.a == sample.a and back.n == 42 and back.f == -3.5 and back.t == true and back.b == false, "scalars round-trip")
check(back and back.list[3].deep == "z" and back[7] == "seven" and back["key with space"] == "", "nested and odd keys round-trip")
check(back and back.big == 1700000000123, "large integer round-trips")
check(back and back.utf == sample.utf, "UTF-8 round-trips")
check(select(2, ns.Deserialize("s5:abc")) ~= nil, "truncated string rejected")
check(select(2, ns.Deserialize("{s1:a")) ~= nil, "unterminated table rejected")
check(select(2, ns.Deserialize(string.rep("{", 40) .. string.rep("}", 40))) ~= nil, "deep nesting rejected")
for _, s in ipairs({ "", "a", "ab", "abc", "abcd", string.rep("\255\0\1", 50) }) do
    check(ns.Base64Decode(ns.Base64Encode(s)) == s, "base64 round-trip len " .. #s)
end
check(ns.Hash("hello") == ns.Hash("hello") and ns.Hash("hello") ~= ns.Hash("hellp") and #ns.Hash("x") == 8, "hash stable, 8 hex chars")
check(ns.CompareVersions("0.1.10", "0.1.9") == 1 and ns.CompareVersions("0.1", "0.1.0") == 0 and ns.CompareVersions("0.2.0", "1.0") == -1, "version compare")
check(ns.NormalizeName("Alice Ash-Forever") == ns.NormalizeName("aliceash"), "name normalization")
local gname, grank, gtag = ns.ParseGuildSpec(" Briar Fang , 2, Briar ")
check(gname == "Briar Fang" and grank == 2 and gtag == "Briar", "guild spec parsing")

---------------------------------------------------------------------------
print("Setup: two guilds, five clients, one member without RUIN")
---------------------------------------------------------------------------
Server.guilds["Ashen Order"] = {
    { name = "Alice Ash", rank = 0, guid = "Player-1-00000001" },
    { name = "Bob Brand", rank = 3, guid = "Player-1-00000005" },
    { name = "Gary Ghost", rank = 4, guid = "Player-1-00000009" },   -- no addon
}
Server.guilds["Briar Fang"] = {
    { name = "Cara Cole", rank = 0, guid = "Player-1-00000002" },
    { name = "Dan Dusk", rank = 1, guid = "Player-1-00000003" },
    { name = "Eve Ember", rank = 2, guid = "Player-1-00000004" },
}
local alice = Server:NewClient({ name = "Alice Ash", guid = "Player-1-00000001", guild = "Ashen Order", rank = 0 })
local bob   = Server:NewClient({ name = "Bob Brand", guid = "Player-1-00000005", guild = "Ashen Order", rank = 3 })
local cara  = Server:NewClient({ name = "Cara Cole", guid = "Player-1-00000002", guild = "Briar Fang", rank = 0 })
local dan   = Server:NewClient({ name = "Dan Dusk", guid = "Player-1-00000003", guild = "Briar Fang", rank = 1 })
local eve   = Server:NewClient({ name = "Eve Ember", guid = "Player-1-00000004", guild = "Briar Fang", rank = 2, version = "0.1.1" })
local gary  = Server.guilds["Ashen Order"][3]
Server:Advance(15)
errorsSoFar("load and login")
check(alice.ns.guildName == "Ashen Order" and dan.ns.guildRank == 1, "guild info picked up")

---------------------------------------------------------------------------
print("Org key: create, share inside guild")
---------------------------------------------------------------------------
Server:Slash(alice, "key create RUIN")
Server:Advance(20)
check(key(alice) and key(alice).org == "RUIN" and key(alice).oc ~= nil, "Alice created key with officer part")
check(alice.ns.Org:IsAdmin(), "Alice is admin")
check(key(bob) and key(bob).rev == 1 and key(bob).oc == nil, "Bob got member key from guild without officer part")
check(bob.joined[key(alice).c.n] ~= nil, "Bob joined org channel")
check(bob.joined[key(alice).oc.n] == nil, "Bob did not join officer channel")
check(alice.joined[key(alice).oc.n] ~= nil, "Alice joined officer channel")

---------------------------------------------------------------------------
print("Org key: add guild, offer to other guild's leader")
---------------------------------------------------------------------------
Server:Slash(alice, "key addguild Briar Fang, 1, Briar")
check(key(alice).rev == 2 and key(alice).guilds["Briar Fang"].tag == "Briar", "guild added, rev 2")
alice.target = "Cara Cole"
alice.ns.UI:SendKeyToTarget()
Server:Advance(3)
local confirmBox = cara.env.RUIN_ConfirmDialog
check(confirmBox and confirmBox:IsShown() and confirmBox.onAccept ~= nil, "Cara got RUIN's own accept prompt")
check(#cara.popups == 0, "no Blizzard StaticPopup used")
confirmBox.onAccept()
Server:Advance(90)
errorsSoFar("key distribution")
check(key(cara) and key(cara).oc ~= nil, "Cara (GM) kept the officer part")
check(key(dan) and key(dan).rev == 2 and key(dan).oc ~= nil, "Dan (officer) got member key and officer part")
check(key(eve) and key(eve).rev == 2 and key(eve).oc == nil, "Eve (member) got member key only")
check(key(bob).rev == 2, "Bob caught up to rev 2")
local orgName, offName = key(alice).c.n, key(alice).oc.n
local allOnOrg = true
for _, c in ipairs({ alice, bob, cara, dan, eve }) do if not c.joined[orgName] then allOnOrg = false end end
check(allOnOrg, "all five on the org channel")
check(dan.joined[offName] and cara.joined[offName] and not eve.joined[offName], "officer channel: officers only")

---------------------------------------------------------------------------
print("Unified guild chat")
---------------------------------------------------------------------------
Server:GuildSay("Ashen Order", { name = "Alice Ash", guid = alice.guid }, "hello from ashen")
Server:Advance(3)
check(chatHas(cara, "[RUIN·Ashen Order]") and chatHas(cara, "hello from ashen"), "Briar sees Alice's line")
check(chatCount(eve, "hello from ashen") == 1, "Eve sees it exactly once")
check(not chatHas(bob, "hello from ashen"), "Bob (same guild) gets no duplicate")

Server:GuildSay("Ashen Order", gary, "line from a member without the addon")
Server:Advance(3)
check(chatCount(dan, "line from a member without the addon") == 1, "bridge relayed non-addon member once")
local bridgeA = alice.ns.Presence:BridgeGUID()
check(bridgeA == bob.ns.Presence:BridgeGUID() and bridgeA == alice.guid, "Ashen agrees on bridge (lowest GUID)")

local long = string.rep("long message ", 19)   -- ~247 chars, forces chunking
Server:GuildSay("Briar Fang", { name = "Eve Ember", guid = eve.guid }, long)
Server:Advance(3)
check(chatHas(alice, long) and chatCount(bob, long) == 1, "long line chunked and reassembled")
check(Server.maxLen <= 255, "no addon message over 255 bytes (max " .. Server.maxLen .. ")")

---------------------------------------------------------------------------
print("Cross-guild officer chat")
---------------------------------------------------------------------------
Server:Advance(30)  -- let attestation go out
Server:GuildSay("Briar Fang", { name = "Dan Dusk", guid = dan.guid }, "officer plans", true)
Server:Advance(3)
check(chatHas(alice, "[RUIN Officer·Briar]") and chatHas(alice, "officer plans"), "Alice (officer) sees Briar officer line")
check(not chatHas(alice, "(unverified)"), "line is verified by attestation")
check(not chatHas(bob, "officer plans"), "Bob (member) does not")

---------------------------------------------------------------------------
print("Version notice")
---------------------------------------------------------------------------
check(chatHas(alice, "RUIN Core 0.1.1"), "Alice told a newer version (Eve's 0.1.1) is in use")

---------------------------------------------------------------------------
print("Rotate key: everyone follows to new channels")
---------------------------------------------------------------------------
Server:Slash(alice, "key rotate")    -- opens confirm dialog
alice.ns.Org:Rotate()
Server:Advance(150)
errorsSoFar("rotation")
local newOrg = key(alice).c.n
check(newOrg ~= orgName and key(alice).rev == 3, "new channels, rev 3")
local allMoved = true
for _, c in ipairs({ alice, bob, cara, dan, eve }) do
    if not (key(c) and key(c).rev == 3 and c.joined[newOrg]) then allMoved = false; print("       not moved: " .. c.name) end
end
check(allMoved, "all five on the new org channel")
check(not alice.joined[orgName], "old channel left")
Server:GuildSay("Briar Fang", { name = "Cara Cole", guid = cara.guid }, "after rotation")
Server:Advance(3)
check(chatHas(alice, "after rotation") and chatHas(bob, "after rotation"), "chat works after rotation")

---------------------------------------------------------------------------
print("Module API")
---------------------------------------------------------------------------
local got
local function addModule(c)
    local env = c.env
    local m = env.RUIN_API:RegisterModule("Test", { version = "0.0.1" })
    function m:OnEnable() self:Listen("PING", "OnPing") end
    function m:OnPing(data, sender) if c == dan then got = { data.x, sender } end end
    return m
end
local ma = addModule(alice); addModule(dan)
Server:Advance(1)
ma:Send("PING", { x = 7 }, "ORG")
Server:Advance(2)
check(got and got[1] == 7 and got[2] == "Alice Ash", "module message delivered across guilds")
check(alice.env.RUIN_API:GetOrg().name == "RUIN" and alice.env.RUIN_API:GetOrg().guilds[1].name ~= nil, "GetOrg works")
check(#alice.env.RUIN_API:GetOnlineMembers() == 5, "online list shows 5 (got " .. #alice.env.RUIN_API:GetOnlineMembers() .. ")")

---------------------------------------------------------------------------
print("UI smoke test and remove guild")
---------------------------------------------------------------------------
alice.env.RUIN_ToggleWindow()
alice.ns.UI:Refresh()
alice.ns.UI:ShowExport()
Server:Slash(alice, "status")
Server:Slash(alice, "versions")
Server:Slash(alice, "key removeguild Briar Fang")
Server:Advance(150)
errorsSoFar("UI and removal")
check(key(alice).guilds["Briar Fang"] == nil and key(alice).rev == 4, "Briar removed, rev 4")
check(key(cara).rev == 3 and not cara.joined[key(alice).c.n], "removed guild did not follow to new channels")
check(key(bob).rev == 4 and bob.joined[key(alice).c.n], "remaining guild followed")

-- A non-officer cannot push a key into the guild
local fake = { v = 1, org = "EVIL", rev = 99, guilds = { ["Ashen Order"] = { o = 9 } }, c = { n = "evilchan", p = "x" } }
bob.ns.Comms:Send("KEY", { k = fake }, "GUILD")
Server:Advance(5)
check(key(alice).org == "RUIN" and key(alice).rev == 4, "member-sent key ignored")

---------------------------------------------------------------------------
print("Late joiner: an officer logs in after setup")
---------------------------------------------------------------------------
table.insert(Server.guilds["Ashen Order"], { name = "Hal Hart", rank = 1, guid = "Player-1-0000000a" })
local hal = Server:NewClient({ name = "Hal Hart", guid = "Player-1-0000000a", guild = "Ashen Order", rank = 1 })
Server:Advance(40)
errorsSoFar("late joiner")
check(key(hal) and key(hal).rev == 4 and key(hal).oc ~= nil, "Hal got the key and the officer part on his own")
check(hal.joined[key(alice).oc.n] ~= nil, "Hal joined the officer channel")
check(chatHas(hal, "Received the RUIN org key"), "Hal was told where the key came from")

---------------------------------------------------------------------------
print(("\n%d passed, %d failed, %d addon messages sent"):format(pass, fail, Server.sent))
os.exit(fail == 0 and 0 or 1)
