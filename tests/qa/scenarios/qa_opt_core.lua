-- QA round 3 (after optimization round 1): OPT-1..3 behaviour checks beyond the suites.
-- Run from /home/claude/stage/tests:  RUIN_CORE_DIR=/home/claude/stage/RUIN_Core texlua qa/run51.lua <this file>
dofile("/home/claude/stage/tests/harness.lua")

local pass, fail = 0, 0
local function check(cond, label)
    if cond then pass = pass + 1; print("  ok   " .. label)
    else fail = fail + 1; print("  FAIL " .. label) end
end
local function errorsSoFar(label)
    check(#Server.errors == 0, label .. ": no Lua errors")
    for _, e in ipairs(Server.errors) do print("       " .. e) end
    Server.errors = {}
end
local function upvalue(fn, name)
    local i = 1
    while true do
        local n, v = debug.getupvalue(fn, i)
        if not n then return nil end
        if n == name then return v end
        i = i + 1
    end
end
local function deepcopy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = deepcopy(v) end
    return o
end

local G = { alice = "Player-1-00000001", cara = "Player-1-00000002", eve = "Player-1-00000004",
            olga = "Player-1-00000005", mal = "Player-1-00000006" }
Server.guilds["Ashen Order"] = {
    { name = "Alice Ash", rank = 0, guid = G.alice },
    { name = "Olga Oak", rank = 1, guid = G.olga },
    { name = "Mal Mischief", rank = 3, guid = G.mal },
}
Server.guilds["Briar Fang"] = {
    { name = "Cara Cole", rank = 0, guid = G.cara },
    { name = "Eve Ember", rank = 2, guid = G.eve },
}
local alice = Server:NewClient({ name = "Alice Ash", guid = G.alice, guild = "Ashen Order", rank = 0 })
local olga = Server:NewClient({ name = "Olga Oak", guid = G.olga, guild = "Ashen Order", rank = 1 })
local mal = Server:NewClient({ name = "Mal Mischief", guid = G.mal, guild = "Ashen Order", rank = 3 })
local cara = Server:NewClient({ name = "Cara Cole", guid = G.cara, guild = "Briar Fang", rank = 0 })
local eve = Server:NewClient({ name = "Eve Ember", guid = G.eve, guild = "Briar Fang", rank = 2 })
local all = { alice, olga, mal, cara, eve }
Server:Advance(10)
Server:Slash(alice, "key create RUIN")
Server:Slash(alice, "key addguild Briar Fang, 1, Briar")
alice.ns.Org:SendFullKey("Cara Cole")
Server:Advance(20)
cara.env.RUIN_ConfirmDialog.onAccept()
Server:Advance(120)
Server:Advance(700)
local function key(c) return c.ns.Org:Get() end
local ok = alice.ns.Org:SetMinVersion(alice.ns.CRYPTO_VERSION)
Server:Advance(60)

-- every client hears "QA:T" and records { text, scope-ish }
local heard = {}
for _, c in ipairs(all) do
    heard[c.name] = {}
    c.ns.Comms:Register("QA:T", function(d, sender) table.insert(heard[c.name], d.t) end)
end
local function got(c, t) for _, x in ipairs(heard[c.name]) do if x == t then return true end end return false end
local wire = {}
Server.tap = function(c, prefix, text, chatType, target) wire[#wire + 1] = { from = c.name, text = text, chatType = chatType, target = target } end
local function send(c, t, scope, target, prio)
    return c.ns.Comms:Send("QA:T", { t = t }, scope, target, prio or c.ns.Comms.PRIORITY.ALERT)
end

print("OPT-1/3: encrypted ORG, OFFICERS, PEER both ways")
check(ok and alice.ns.Org:Encrypted() and eve.ns.Org:Encrypted() and cara.ns.Org:Encrypted(), "org encrypts")
for _, c in ipairs(all) do check(c.ns.Org:DataKey() ~= nil, c.name .. " has the data key") end
check(olga.ns.Comms:IsJoined("OFFICERS") and cara.ns.Comms:IsJoined("OFFICERS") and alice.ns.Comms:IsJoined("OFFICERS"), "officers on officer channel")
wire = {}
send(olga, "org-1", "ORG"); send(eve, "org-2", "ORG")
Server:Advance(3)
check(got(cara, "org-1") and got(eve, "org-1") and got(alice, "org-1") and got(mal, "org-1"), "ORG olga -> everyone")
check(got(olga, "org-2") and got(alice, "org-2") and got(cara, "org-2"), "ORG eve -> everyone (other direction)")
local plainLeak = false
for _, w in ipairs(wire) do if w.text:find("org-1", 1, true) or w.text:find("QA:T", 1, true) then plainLeak = true end end
check(#wire > 0 and not plainLeak, "ORG on the wire is ciphertext")
send(olga, "off-1", "OFFICERS"); send(cara, "off-2", "OFFICERS")
Server:Advance(3)
check(got(cara, "off-1") and got(alice, "off-1"), "OFFICERS olga -> cara, alice")
check(got(olga, "off-2") and got(alice, "off-2"), "OFFICERS cara -> olga, alice")
check(not got(eve, "off-1") and not got(mal, "off-1"), "members don't hear officers")
send(olga, "peer-1", "PEER", "Eve Ember"); send(eve, "peer-2", "PEER", "Olga Oak")
send(alice, "peer-3", "PEER", "Cara Cole"); send(cara, "peer-4", "PEER", "Alice Ash")
Server:Advance(3)
check(got(eve, "peer-1") and got(olga, "peer-2") and got(cara, "peer-3") and got(alice, "peer-4"), "PEER both ways, both guilds")
check(not got(cara, "peer-1") and not got(mal, "peer-2"), "PEER only to the target")
-- repeat (cache now warm) to make sure second use of cached keys works
send(olga, "org-1b", "ORG"); send(cara, "off-2b", "OFFICERS"); send(eve, "peer-2b", "PEER", "Olga Oak")
Server:Advance(3)
check(got(mal, "org-1b") and got(olga, "off-2b") and got(olga, "peer-2b"), "second round (cached keys) still opens")
errorsSoFar("encrypted traffic")

print("OPT-1: 'Encryption: on' / DataKeyHex / DkHash stable")
local Sec = alice.ns.OrgSecure
local hex = alice.ns.Org:DataKeyHex()
check(type(hex) == "string" and #hex == 64, "DataKeyHex returns the key")
if Sec and Sec.DkHash then
    local h1 = Sec.DkHash(hex)
    local h2 = Sec.DkHash(hex)
    local hx = Sec.DkHash(("0"):rep(64))
    check(h1 == h2 and h1 == key(alice).dkh, "cached check value equals the key's dkh")
    check(hx ~= h1, "different key, different check value")
    -- push past the 12-entry reset and confirm still correct
    for i = 1, 30 do Sec.DkHash(("%064x"):format(i)) end
    check(Sec.DkHash(hex) == key(alice).dkh, "still correct after cache reset (30 other keys)")
else
    check(false, "OrgSecure.DkHash reachable")
end

print("OPT-1: wrong data key rejected")
do
    local Org = eve.ns.Org
    local goodHex, r = Org:DataKeyHex()
    local bad = ("ab"):rep(32)
    check(Org:SetDataKey(r, bad) == false, "SetDataKey with a wrong key for the current generation is refused")
    check(Org:DataKeyHex() == goodHex, "and the good key stays")
    -- a stored wrong key (corrupted saved vars) is not used
    local store = eve.ns.db.orgData[key(eve).org]
    local saved = store.k
    store.k = bad
    check(Org:DataKey() == nil, "a stored key that doesn't match dkh gives no data key")
    store.k = saved
    check(Org:DataKeyHex() == goodHex, "restored key is used again")
    -- Mal seals with a wrong key: nobody opens it
    local mstore = mal.ns.db.orgData[key(mal).org]
    local mk, mdkh = mstore.k, key(mal).dkh
    mstore.k = bad; key(mal).dkh = mal.ns.OrgSecure.DkHash(bad)
    send(mal, "wrongkey-1", "ORG"); send(mal, "wrongkey-2", "PEER", "Eve Ember")
    Server:Advance(3)
    check(not got(eve, "wrongkey-1") and not got(cara, "wrongkey-1") and not got(eve, "wrongkey-2"), "messages sealed with a wrong key don't open")
    mstore.k = mk; key(mal).dkh = mdkh
    send(mal, "rightkey", "ORG")
    Server:Advance(3)
    check(got(eve, "rightkey"), "his real key works again")
end
errorsSoFar("wrong key")

print("OPT-1/3: data key rotation, grace window for old-generation messages")
do
    local oldR = key(alice).dkr
    local eveOldStore = deepcopy(eve.ns.db.orgData[key(eve).org])
    local eveOldDkh = key(eve).dkh
    check(alice.ns.Org:RotateDataKey(), "admin rotates the data key")
    Server:Advance(120)
    for _, c in ipairs(all) do check(select(2, c.ns.Org:DataKey()) == oldR + 1, c.name .. " has generation " .. (oldR + 1)) end
    send(olga, "rot-org", "ORG"); send(cara, "rot-off", "OFFICERS"); send(eve, "rot-peer", "PEER", "Alice Ash")
    Server:Advance(3)
    check(got(mal, "rot-org") and got(eve, "rot-org") and got(alice, "rot-off") and got(alice, "rot-peer"), "new-generation ORG/OFFICERS/PEER open")
    -- Eve still seals with the old generation (a message sent just before the change)
    local cur = deepcopy(eve.ns.db.orgData[key(eve).org]); local curDkh, curDkr = key(eve).dkh, key(eve).dkr
    eve.ns.db.orgData[key(eve).org] = deepcopy(eveOldStore); key(eve).dkh = eveOldDkh; key(eve).dkr = oldR
    check(select(2, eve.ns.Org:DataKey()) == oldR, "(eve set back to the old generation)")
    wire = {}
    send(eve, "old-gen-org", "ORG"); send(eve, "old-gen-peer", "PEER", "Olga Oak")
    Server:Advance(3)
    local sawOld = false
    for _, w in ipairs(wire) do if w.from == "Eve Ember" and w.text:find("\030E\030", 1, true) then sawOld = true end end
    check(sawOld, "eve's messages went out sealed")
    check(got(olga, "old-gen-org") and got(cara, "old-gen-org") and got(alice, "old-gen-org"), "old-generation ORG message opens inside the grace window")
    check(got(olga, "old-gen-peer"), "old-generation PEER message opens inside the grace window")
    eve.ns.db.orgData[key(eve).org] = cur; key(eve).dkh = curDkh; key(eve).dkr = curDkr
    -- past the grace window (900 s)
    Server:Advance(1000)
    eve.ns.db.orgData[key(eve).org] = deepcopy(eveOldStore); key(eve).dkh = eveOldDkh; key(eve).dkr = oldR
    send(eve, "too-old-org", "ORG"); send(eve, "too-old-peer", "PEER", "Olga Oak")
    Server:Advance(3)
    check(not got(olga, "too-old-org") and not got(cara, "too-old-org") and not got(olga, "too-old-peer"), "past the grace window the old generation no longer opens")
    eve.ns.db.orgData[key(eve).org] = cur; key(eve).dkh = curDkh; key(eve).dkr = curDkr
    send(eve, "back-cur", "ORG")
    Server:Advance(3)
    check(got(olga, "back-cur"), "current generation still fine")
end
errorsSoFar("rotation")

print("OPT-3: officer channel password change")
do
    local oldOC = deepcopy(key(olga).oc)
    send(olga, "pre-oc", "OFFICERS")    -- warm the cache with the old password
    Server:Advance(3)
    check(got(cara, "pre-oc"), "officer traffic before the change")
    check(alice.ns.Org:RotateOfficerChannel({}), "admin makes a new officer channel")
    Server:Advance(180)
    check(key(olga).oc.p ~= oldOC.p and key(cara).oc.p == key(alice).oc.p and key(olga).oc.p == key(alice).oc.p, "officers got the new password")
    check(olga.ns.Comms:IsJoined("OFFICERS") and cara.ns.Comms:IsJoined("OFFICERS"), "and are on the new channel")
    send(olga, "post-oc-1", "OFFICERS"); send(cara, "post-oc-2", "OFFICERS"); send(alice, "post-oc-3", "OFFICERS")
    Server:Advance(3)
    check(got(cara, "post-oc-1") and got(alice, "post-oc-1") and got(olga, "post-oc-2") and got(olga, "post-oc-3"), "officer traffic after the change, all ways")
    -- the OFFICERS key really depends on the password: a client holding a stale password can't open new traffic
    local curP = key(cara).oc.p
    key(cara).oc.p = oldOC.p
    send(olga, "stale-pw", "OFFICERS")
    Server:Advance(3)
    check(not got(cara, "stale-pw"), "with the old password (cached key) the new officer traffic does not open")
    key(cara).oc.p = curP
    send(olga, "fresh-pw", "OFFICERS")
    Server:Advance(3)
    check(got(cara, "fresh-pw"), "with the right password it opens again")
    -- org traffic unaffected
    send(olga, "org-after-oc", "ORG")
    Server:Advance(3)
    check(got(eve, "org-after-oc") and got(mal, "org-after-oc"), "org traffic unaffected")
end
errorsSoFar("officer password")

print("OPT-2: send queue restarts after idle; pacing")
do
    local Comms = alice.ns.Comms
    local wake = upvalue(Comms.Send, "wakeFlush")
    local function tickerOn() if not wake then return nil end return upvalue(wake, "ticker") ~= nil end
    local tokens = function() return Comms:Pace().tokens end
    Server:Advance(600)
    check(not tickerOn(), "after a long idle the send ticker is stopped")
    local t0 = Server.time
    local sentAt
    Server.tap = function(c, prefix, text, chatType) if c == alice and not sentAt then sentAt = Server.time end end
    heard[olga.name] = {}
    send(alice, "after-idle", "ORG", nil, Comms.PRIORITY.NORMAL)
    check(tickerOn(), "a send starts it")
    Server:Advance(0.3)
    check(sentAt and sentAt - t0 <= 0.15, ("it goes out on the next tick (%.3f s)"):format(sentAt and sentAt - t0 or -1))
    Server:Advance(1)
    check(got(olga, "after-idle"), "and is received")
    Server:Advance(10)
    check(not tickerOn(), "stops again once idle and tokens full")
    -- PEER and GUILD after idle too
    sentAt = nil; t0 = Server.time
    send(alice, "peer-idle", "PEER", "Olga Oak")
    Server:Advance(1)
    check(sentAt and sentAt - t0 <= 0.15 and got(olga, "peer-idle"), "a whisper after idle goes promptly")

    -- burst of 20: 6 immediately (token cap), then ~1/s
    Server:Advance(30)
    local n = 0
    Server.tap = function(c) if c == alice then n = n + 1 end end
    for i = 1, 20 do send(alice, "burst-" .. i, "ORG", nil, Comms.PRIORITY.NORMAL) end
    Server:Advance(0.15)
    check(n == 6, "a burst: 6 at once (" .. n .. ")")
    Server:Advance(5)
    check(n >= 10 and n <= 12, "then about 1 a second (" .. n .. " after 5 s)")
    Server:Advance(20)
    local r=0; for _,x in ipairs(heard[olga.name]) do if x:find("^burst%-") then r=r+1 end end
    check(r == 20, "all 20 received (" .. r .. "; " .. n .. " alice sends incl. background)")
    Server:Advance(10)
    check(not tickerOn(), "ticker stops after the burst")

    -- back-off while idle (ticker stopped): pause, then half speed, then normal
    Server:Advance(30)
    alice.ns.Throttle.OnError("You're doing that too fast")
    check(tickerOn(), "a back-off starts the ticker")
    local p = Comms:Pace()
    check(p.paused and p.slow and p.tokens == 0, "paused, slow, tokens 0")
    n = 0
    Server:Advance(2)
    for i = 1, 30 do send(alice, "bo-" .. i, "ORG", nil, Comms.PRIORITY.NORMAL) end
    Server:Advance(3.5)   -- t = 5.5 s into the 6 s pause
    check(n == 0, "nothing goes out during the pause (" .. n .. ")")
    Server:Advance(0.6 + 10)   -- 10 s of half speed
    check(n >= 4 and n <= 6, "half speed after the pause: about 5 in 10 s (" .. n .. ")")
    Server:Advance(90)
    local before = n
    check(not Comms:Pace().slow, "slow pace over")
    Server:Advance(5)
    -- by now all 30 sent (30 needs ~ 55 s at 0.5/s)
    local r=0; for _,x in ipairs(heard[olga.name]) do if x:find("^bo%-") then r=r+1 end end
    check(r == 30, "all 30 received (" .. r .. "; " .. n .. " alice sends incl. background)")
    Server:Advance(10)
    check(not tickerOn(), "and the ticker stops afterwards")
    -- slow period with ticker stopping mid-way: back-off, nothing queued, ticker stops at token cap while still slow;
    -- a burst then refills at half speed
    alice.ns.Throttle.OnError("You're doing that too fast")
    Server:Advance(25)    -- 21 s past pause end; tokens back to 6 at 0.5/s after 12 s
    local pp = Comms:Pace()
    check(pp.slow and pp.tokens >= 6 and not tickerOn(), ("ticker stopped while still in the slow window with full tokens (%s)"):format(tostring(pp.tokens)))
    n = 0
    for i = 1, 16 do send(alice, "slow-" .. i, "ORG", nil, Comms.PRIORITY.NORMAL) end
    Server:Advance(10.05)
    check(n >= 10 and n <= 12, "slow window: 6 at once then 0.5/s (" .. n .. " in 10 s)")
    Server:Advance(120)

    -- long sealed messages: one sealed per tick
    Server.tap = nil
    local long = ("x"):rep(900)
    for i = 1, 4 do Comms:Send("QA:T", { t = "long-" .. i, pad = long }, "ORG", nil, Comms.PRIORITY.NORMAL) end
    check(Comms.PendingJobs() == 4, "4 long sealed messages queued as jobs")
    local seen, okPerTick = {}, true
    local last = 4
    for _ = 1, 400 do
        Server:Advance(0.1)
        local j = Comms.PendingJobs()
        if last - j > 1 then okPerTick = false end
        last = j
        if j == 0 then break end
    end
    check(okPerTick, "at most one long message sealed per tick")
    Server:Advance(60)
    local all4 = got(olga, "long-1") and got(olga, "long-2") and got(olga, "long-3") and got(olga, "long-4")
    check(all4, "all four long messages arrive")

    -- queue items age out at 60 s (lockdown: everything waits; party is dropped)
    Server:Advance(30)
    local CI = alice.env.C_ChatInfo
    CI.InChatMessagingLockdown = function() return true end
    alice.partyOf = 1; olga.partyOf = 1
    local realIG, realIR = alice.env.IsInGroup, alice.env.IsInRaid
    alice.env.IsInGroup = function() return true end
    alice.env.IsInRaid = function() return false end
    n = 0
    Server.tap = function(c) if c == alice then n = n + 1 end end
    send(alice, "locked-org", "ORG", nil, Comms.PRIORITY.NORMAL)
    alice.ns.Comms:Send("QA:T", { t = "locked-party" }, "PARTY", nil, Comms.PRIORITY.NORMAL)
    Server:Advance(30)
    check(n == 0 and tickerOn(), "lockdown: nothing sent, ticker keeps running while items wait")
    CI.InChatMessagingLockdown = nil
    Server:Advance(1)
    check(got(olga, "locked-org") and not got(olga, "locked-party"), "lockdown lifted inside 60 s: org message goes, party message was dropped")
    CI.InChatMessagingLockdown = function() return true end
    n = 0
    send(alice, "aged-org", "ORG", nil, Comms.PRIORITY.NORMAL)
    Server:Advance(61)
    CI.InChatMessagingLockdown = nil
    Server:Advance(2)
    check(not got(olga, "aged-org"), "an item waiting more than 60 s ages out (" .. n .. " alice sends after unlock, background)")
    Server:Advance(5)
    check(not tickerOn(), "and the ticker stops afterwards")
    alice.env.IsInGroup, alice.env.IsInRaid = realIG, realIR
    -- unjoined channel: wait, ticker running, then goes when joined (within 60 s)
    Server.tap = nil
end
errorsSoFar("send queue")
print(("%d passed, %d failed"):format(pass, fail))
