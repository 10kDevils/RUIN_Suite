-- RUIN security tests (0.4.5): every attack from the October 2026 security
-- audit, played out by a modified client, must fail, and the legitimate path
-- next to it must still work.
--   Mal Mischief: an ordinary member of Ashen Order with a modified RUIN
--   Xan Outsider: a player in no org guild, whispering RUIN messages
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
local function chatLine(c, needle)
    for _, line in ipairs(c.chat) do if line:find(needle, 1, true) then return line end end
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

local MODULES = { "RUIN_Finder", "RUIN_Pathfinder", "RUIN_Codex", "RUIN_Exchange", "RUIN_Muster" }
local G = {
    alice = "Player-1-00000001", cara = "Player-1-00000002", eve = "Player-1-00000004",
    olga = "Player-1-00000005", mal = "Player-1-00000006", xan = "Player-1-00000009",
}
Server.guilds["Ashen Order"] = {
    { name = "Alice Ash", rank = 0, guid = G.alice },
    { name = "Olga Oak", rank = 1, guid = G.olga },
    { name = "Mal Mischief", rank = 3, guid = G.mal },
}
Server.guilds["Briar Fang"] = {
    { name = "Cara Cole", rank = 0, guid = G.cara },
    { name = "Eve Ember", rank = 2, guid = G.eve },
}
Server.guilds["Grey Wolves"] = { { name = "Xan Outsider", rank = 0, guid = G.xan } }

local alice = Server:NewClient({ name = "Alice Ash", guid = G.alice, guild = "Ashen Order", rank = 0, modules = MODULES })
local olga = Server:NewClient({ name = "Olga Oak", guid = G.olga, guild = "Ashen Order", rank = 1, modules = MODULES })
local mal = Server:NewClient({ name = "Mal Mischief", guid = G.mal, guild = "Ashen Order", rank = 3, modules = MODULES })
local cara = Server:NewClient({ name = "Cara Cole", guid = G.cara, guild = "Briar Fang", rank = 0, modules = MODULES })
local eve = Server:NewClient({ name = "Eve Ember", guid = G.eve, guild = "Briar Fang", rank = 2, modules = MODULES })
local xan = Server:NewClient({ name = "Xan Outsider", guid = G.xan, guild = "Grey Wolves", rank = 0, modules = MODULES })
Server:Advance(10)
Server:Slash(alice, "key create RUIN")
Server:Slash(alice, "key addguild Briar Fang, 1, Briar")
alice.ns.Org:SendFullKey("Cara Cole")
Server:Advance(3)
cara.env.RUIN_ConfirmDialog.onAccept()
Server:Advance(120)
-- let officer hellos and the verified-officer lists go round
Server:Advance(700)

local function send(c, kind, data, scope, target)
    c.ns.Comms:Send(kind, data, scope, target, c.ns.Comms.PRIORITY.ALERT)
end
local function key(c) return c.ns.Org:Get() end

print("Setup")
check(alice.ns.Comms:IsJoined("ORG") and eve.ns.Comms:IsJoined("ORG") and mal.ns.Comms:IsJoined("ORG"), "members on the org channel")
check(olga.ns.Comms:IsJoined("OFFICERS") and cara.ns.Comms:IsJoined("OFFICERS"), "officers on the officer channel")
check(not mal.ns.Comms:IsJoined("OFFICERS") and not eve.ns.Comms:IsJoined("OFFICERS"), "members are not")
check(key(alice).an and key(alice).an[1] == "Alice Ash", "a new key names its admin's character")
check(key(eve).an and key(eve).an[1] == "Alice Ash", "and every member's copy has that name")
check(cara.ns.Presence:IsOfficerName("Olga Oak"), "Cara (Briar) verifies Olga as an officer from the officer channel")
check(eve.ns.Presence:IsOfficerName("Olga Oak"), "Eve (Briar member) verifies Olga through her own guild's officer")
check(not eve.ns.Presence:IsOfficerName("Mal Mischief"), "Mal is no officer to anyone")
errorsSoFar("setup")

---------------------------------------------------------------------------
print("C1: org key takeover")
do
    local before = deepcopy(key(cara))
    local forged = deepcopy(key(mal))
    forged.admin, forged.an = G.mal, { "Mal Mischief" }
    forged.rev = before.rev + 1
    forged.c = { n = "ruinmalchannel", p = "x" }
    -- Mal had to look like an officer before: claim it in an org hello
    send(mal, "OHELLO", { g = G.mal, v = "0.4.5", gu = "Ashen Order", o = 1, kr = 99 }, "ORG")
    Server:Advance(2)
    send(mal, "ORGKEY", { k = forged }, "PEER", "Cara Cole")
    send(mal, "ORGKEY", { k = forged }, "PEER", "Eve Ember")
    send(mal, "ORGKEY", { k = forged }, "ORG")
    Server:Advance(5)
    check(key(cara).admin == G.alice and key(cara).rev == before.rev, "a member's forged key is refused (whisper)")
    check(key(eve).admin == G.alice and key(eve).c.n ~= "ruinmalchannel", "and Eve keeps the real org channel")
    check(not cara.ns.Org:IsAdminName("Mal Mischief"), "Mal is not the admin anywhere")

    local frozen = deepcopy(key(mal))
    frozen.rev = 2 ^ 53
    send(mal, "ORGKEY", { k = frozen }, "PEER", "Cara Cole")
    Server:Advance(3)
    check(key(cara).rev == before.rev, "a revision of 2^53 (the freeze) is refused")
    check(cara.ns.Org.Decode(cara.ns.Org.Encode(frozen)) == nil, "and so is a pasted key with it")

    -- an officer passing a key on can't name a new admin either
    local officerForged = deepcopy(key(olga))
    officerForged.admin, officerForged.an, officerForged.rev = G.olga, { "Olga Oak" }, before.rev + 1
    send(olga, "ORGKEY", { k = officerForged }, "PEER", "Cara Cole")
    Server:Advance(3)
    check(key(cara).admin == G.alice and cara.ns.Org:IsAdminName("Alice Ash") and not cara.ns.Org:IsAdminName("Olga Oak"),
        "an officer's relay can't change the admin")
    check(key(cara).rev == before.rev, "(and the relayed key isn't taken)")

    -- legitimate: the admin edits the key; everyone gets it
    Server:Slash(alice, "key addguild Grey Wolves, 1, Grey")
    Server:Advance(60)
    check(key(cara).rev == key(alice).rev and key(cara).guilds["Grey Wolves"], "the admin's edit reaches the officers")
    check(key(eve).rev == key(alice).rev, "and the members")

    -- legitimate: an officer catches up someone who missed an edit
    local cur = deepcopy(key(cara))
    local behind = deepcopy(cur); behind.rev = cur.rev - 1
    cara.ns.db.orgKey = behind
    send(olga, "ORGKEY", { k = deepcopy(key(olga)) }, "PEER", "Cara Cole")
    Server:Advance(3)
    check(key(cara).rev == cur.rev, "a verified officer can still pass the current key on")

    -- an outsider can't do it either
    local x = deepcopy(key(alice)); x.rev = x.rev + 1; x.c = { n = "ruinxan", p = "y" }
    send(xan, "ORGKEY", { k = x }, "PEER", "Eve Ember")
    Server:Advance(3)
    check(key(eve).c.n ~= "ruinxan", "an outsider's whispered key is refused")

    -- a key from before admin names: the officer channel bootstraps the name
    local old = deepcopy(key(cara)); old.an = nil; cara.ns.db.orgKey = old
    local m = deepcopy(key(mal)); m.an, m.rev = { "Mal Mischief" }, old.rev + 1
    send(mal, "ORGKEY", { k = m }, "PEER", "Cara Cole")
    Server:Advance(3)
    check(key(cara).rev == old.rev, "old key: a member naming himself admin by whisper is refused")
    local a = deepcopy(key(alice)); a.rev = old.rev + 1
    send(alice, "ORGKEY", { k = a }, "OFFICERS", key(alice).oc.n)
    Server:Advance(3)
    check(key(cara).rev == old.rev + 1 and cara.ns.Org:IsAdminName("Alice Ash"), "old key: the admin on the officer channel adds her name")
end
errorsSoFar("C1")

---------------------------------------------------------------------------
print("C2: the Watch")
do
    -- Mal pretends to be the admin (her GUID) and an officer
    send(mal, "OHELLO", { g = G.alice, v = "0.4.5", gu = "Ashen Order", o = 1, kr = 1 }, "ORG")
    Server:Advance(2)
    local id = "malsan1"
    for _, target in ipairs({ "Alice Ash", "Cara Cole", "Eve Ember" }) do
        send(mal, "WSAN", { id = id .. target:sub(1, 1), kind = "hide", target = target, untilT = 0, reason = "x",
                            t = 1e300, u = 1e300 }, "ORG")
    end
    Server:Advance(3)
    check(not eve.ns.Watch:IsHidden("Alice Ash") and not cara.ns.Watch:IsHidden("Alice Ash"), "a member can't hide the admin")
    check(not alice.ns.Watch:IsHidden("Cara Cole"), "or an officer")
    check(not cara.ns.Watch:IsMuted("Eve Ember") and not eve.ns.Watch:IsMuted("Eve Ember"), "or anyone")
    check(not alice.ns.Watch:Sanctions(true)[1], "nothing is stored at all")

    -- legitimate: officer Olga (Ashen) mutes Eve (Briar member)
    local ok, s = olga.ns.Watch:Sanction("mute", "Eve Ember", 1800, "spam")
    Server:Advance(3)
    check(ok and eve.ns.Watch:IsMuted("Eve Ember") and cara.ns.Watch:IsMuted("Eve Ember") and alice.ns.Watch:IsMuted("Eve Ember"),
        "an officer's mute reaches every guild")
    -- a forged far-future update of it can't block the lift
    local f = deepcopy(s); f.u, f.t, f.reason = 1e300, 1e300, "forever"
    send(olga, "WSAN", f, "ORG")
    Server:Advance(2)
    olga.ns.Watch:Lift(s.id)
    Server:Advance(3)
    check(not eve.ns.Watch:IsMuted("Eve Ember") and not alice.ns.Watch:IsMuted("Eve Ember"), "a lift wins over a far-future copy")
    -- an un-lift doesn't come back
    local un = deepcopy(s); un.lifted, un.u = nil, s.u + 10
    send(olga, "WSAN", un, "ORG")
    Server:Advance(2)
    check(not eve.ns.Watch:IsMuted("Eve Ember"), "a lifted sanction stays lifted")

    -- an officer can't hide another officer, even with a hand-made message
    send(olga, "WSAN", { id = "olgahide", kind = "hide", target = "Cara Cole", untilT = 0, reason = "x", t = 1, u = 1 }, "ORG")
    Server:Advance(2)
    check(not eve.ns.Watch:IsHidden("Cara Cole") and not alice.ns.Watch:IsHidden("Cara Cole"), "officers are protected on receipt too")
    -- the admin can
    local okA = alice.ns.Watch:Sanction("mute", "Cara Cole", 300, "cool down")
    Server:Advance(3)
    check(okA and eve.ns.Watch:IsMuted("Cara Cole"), "the admin can mute an officer")
    for _, x in ipairs(alice.ns.Watch:Sanctions(false)) do alice.ns.Watch:Lift(x.id) end
    Server:Advance(3)
    -- nobody hides the admin
    send(olga, "WSAN", { id = "olgaadm", kind = "hide", target = "Alice Ash", untilT = 0, reason = "x", t = 1, u = 1 }, "ORG")
    Server:Advance(2)
    check(not eve.ns.Watch:IsHidden("Alice Ash"), "not even an officer can hide the admin")

    -- Mal's chat-line deletes and fake cases go nowhere
    send(mal, "WDEL", { k = "abcd1234", a = "Cara Cole" }, "ORG")
    Server:Advance(2)
    local log = eve.ns.Watch:LogLines()
    local sawDel = false
    for _, l in ipairs(log) do if l.act == "deleted" and tostring(l.a):find("Mal", 1, true) then sawDel = true end end
    check(not sawDel, "a member's line delete is ignored")
    -- an outsider whispering a sanction
    send(xan, "WSAN", { id = "xan1", kind = "mute", target = "Eve Ember", untilT = 0, t = 1, u = 1 }, "PEER", "Eve Ember")
    Server:Advance(2)
    check(not eve.ns.Watch:IsMuted("Eve Ember"), "an outsider's whispered sanction is ignored")
end
errorsSoFar("C2")

---------------------------------------------------------------------------
print("H1: modules")
do
    local now = alice.env.GetServerTime()
    local mu = alice.env.RUIN_API:GetModule("Muster")
    local ev = mu:Create("Molten Core", alice.env.date("%Y-%m-%d %H:%M", now + 86400), { kind = "Raid" })
    Server:Advance(3)
    local evId = ev and ev.id
    check(evId and eve.env.RUIN_MusterDB.events[evId], "legit: the officer's event reaches Eve")
    eve.env.RUIN_API:GetModule("Muster"):SignUp(evId, "H")
    Server:Advance(3)
    check(alice.env.RUIN_MusterDB.events[evId].signups[G.eve], "legit: Eve's sign-up reaches Alice")

    -- an outsider whispers an event to Eve
    send(xan, "Muster:EVENT", { id = "xanev", title = "Free gold", at = now + 3600, by = "Alice Ash", t = now, signups = {},
                                 rally = { map = 1, x = 0.5, y = 0.5, zone = "Ambush Alley" } }, "PEER", "Eve Ember")
    Server:Advance(2)
    check(not eve.env.RUIN_MusterDB.events.xanev, "an outsider's whispered event is ignored")
    -- Mal rewrites Alice's event, posts one in her name, deletes hers, moves Eve
    local copy = deepcopy(alice.env.RUIN_MusterDB.events[evId]); copy.title, copy.t = "Cancelled", now + 10
    send(mal, "Muster:EVENT", copy, "ORG")
    send(mal, "Muster:EVENT", { id = "malev", title = "Rally here", at = now, by = "Alice Ash", t = now, signups = {},
                                rally = { map = 1, x = 0.5, y = 0.5, zone = "Ambush Alley" } }, "ORG")
    Server:Advance(2)
    check(eve.env.RUIN_MusterDB.events[evId].title == "Molten Core", "a member can't rewrite someone else's event")
    check(not eve.env.RUIN_MusterDB.events.malev, "or post one in the officer's name")
    send(mal, "Muster:DELETE", { id = evId }, "ORG")
    send(mal, "Muster:SIGN", { id = evId, g = G.eve, s = { n = "Eve Ember", role = nil, t = now + 5 } }, "ORG")
    send(mal, "Muster:ROSTER", { id = evId, r = { [G.eve] = 0 }, t = now + 5 }, "ORG")
    Server:Advance(2)
    check(eve.env.RUIN_MusterDB.events[evId] ~= nil, "or delete it")
    check(cara.env.RUIN_MusterDB.events[evId].signups[G.eve] and cara.env.RUIN_MusterDB.events[evId].signups[G.eve].role == "H",
        "or withdraw Eve's sign-up")
    check(not (cara.env.RUIN_MusterDB.events[evId].roster or {})[G.eve], "or bench her")
    send(mal, "Muster:EVENT", { id = "far", title = "Far", at = now + 400 * 86400, by = "Mal Mischief", t = now, signups = {} }, "ORG")
    Server:Advance(2)
    check(not eve.env.RUIN_MusterDB.events.far, "an event more than 90 days out is refused")
    -- bounties and loot points are officers'
    send(mal, "Muster:BOUNTY", { id = "malb", target = "Cara Cole", kind = "Player", reward = "1000g", exp = now + 3600, t = now }, "ORG")
    send(mal, "Muster:LNOTE", { id = "maln", ev = evId, item = "Thunderfury", to = "Mal Mischief", kind = "Main spec", pts = -9999, t = now }, "ORG")
    Server:Advance(2)
    check(not eve.env.RUIN_MusterDB.bounties.malb, "a member's bounty is ignored")
    check(not (eve.env.RUIN_MusterDB.loot and eve.env.RUIN_MusterDB.loot.notes.maln), "and his loot note")
    olga.env.RUIN_API:GetModule("Muster"):PostBounty("Grim Tusk", "Player", "100g")
    Server:Advance(3)
    local got = false
    for _, b in pairs(eve.env.RUIN_MusterDB.bounties) do if b.target == "Grim Tusk" then got = true end end
    check(got, "legit: an officer's bounty reaches the other guild")

    -- Exchange
    local ex = alice.mns.RUIN_Exchange.Treasury
    ex.Record(5000, "Olga Oak", "hand", "dues")
    Server:Advance(3)
    local okBook = olga.mns.RUIN_Exchange.Treasury.Entries()[1]
    check(okBook and okBook.c == 5000, "legit: the guild master's treasury entry reaches the guild")
    send(mal, "Exchange:TBOOK", { id = "malt", c = -999999, who = "Mal Mischief", via = "hand", note = "fee", t = now }, "GUILD")
    Server:Advance(2)
    local bad = false
    for _, e in ipairs(olga.mns.RUIN_Exchange.Treasury.Entries()) do if e.id == "malt" then bad = true end end
    check(not bad, "a member can't write in the treasury book")
    alice.env.RUIN_ExchangeDB.crafters[G.eve] = { name = "Eve Ember", guild = "Briar Fang", t = now, profs = { Alchemy = { "Flask" } } }
    send(mal, "Exchange:CRAFTS", { g = G.eve, gu = "Briar Fang", p = "Alchemy", l = { "Flask" } }, "ORG")
    Server:Advance(2)
    check(alice.env.RUIN_ExchangeDB.crafters[G.eve].name == "Eve Ember", "a member can't take over a crafter's listing")
    eve.env.RUIN_API:GetModule("Exchange"):Request("Flask of the Titans", "please")
    Server:Advance(3)
    local rid
    for id, r in pairs(alice.env.RUIN_ExchangeDB.requests) do if r.by == "Eve Ember" then rid = id end end
    send(mal, "Exchange:REQDEL", { id = rid }, "ORG")
    Server:Advance(2)
    check(rid and alice.env.RUIN_ExchangeDB.requests[rid], "a member can't close someone else's request")
    send(mal, "Exchange:PRICES", { t = now + 1e9, l = { 2589, 1 } }, "ORG")
    Server:Advance(2)
    check(not alice.env.RUIN_ExchangeDB.prices[2589] or alice.env.RUIN_ExchangeDB.prices[2589].t < now + 1e6, "far-future prices are refused")

    -- Pathfinder: "official" routes need a verified officer
    send(mal, "Pathfinder:OFFICIAL", { id = "malroute", title = "Shortcut", faction = "Any", ot = now,
                                       steps = { { act = "go", text = "jump off the cliff", at = { zone = "Thousand Needles", x = 0.5, y = 0.5 } } } }, "ORG")
    Server:Advance(3)
    local pdb = eve.env.RUIN_PathfinderDB
    check(not (pdb and pdb.official and pdb.official.malroute), "a member can't publish an official route")

    -- Finder: someone else's listing
    local Finder = eve.env.RUIN_API:GetModule("Finder")
    local board = upvalue(Finder.OnBeacon, "board")
    board[G.cara] = { g = G.cara, name = "Cara Cole", a = "Dungeons", t = eve.env.GetTime(), on = 1 }
    send(mal, "Finder:BEACON", { g = G.cara, on = 1, a = "Scam", d = "whisper me" }, "ORG")
    Server:Advance(2)
    check(board[G.cara] and board[G.cara].name == "Cara Cole", "a member can't replace someone else's listing")
end
errorsSoFar("H1")

---------------------------------------------------------------------------
print("H2: chat")
do
    Server:GuildSay("Briar Fang", { name = "Cara Cole", guid = G.cara }, "real line from Cara")
    Server:Advance(3)
    local line = chatLine(alice, "real line from Cara")
    check(line and not line:find("(via", 1, true), "legit: Cara's own line shows as hers")
    send(mal, "GCHAT", { a = "Cara Cole", g = G.cara, gu = "Briar Fang", t = "FAKE disband the org", c = "WARRIOR" }, "ORG")
    Server:Advance(2)
    check(not chatHas(alice, "FAKE disband"), "a line in another guild's leader's name is dropped")
    send(mal, "GCHAT", { a = "Alice Ash", g = G.alice, gu = "Ashen Order", t = "FAKE from the admin", c = "WARRIOR" }, "ORG")
    Server:Advance(2)
    local l2 = chatLine(eve, "FAKE from the admin")
    check(l2 and l2:find("(via Mal Mischief)", 1, true), "a relayed line always says who relayed it")
    -- officer chat: verified only when the author sent it
    Server:GuildSay("Ashen Order", { name = "Olga Oak", guid = G.olga }, "officer line from Olga", true)
    Server:Advance(3)
    local l3 = chatLine(cara, "officer line from Olga")
    check(l3 and not l3:find("(via", 1, true) and not l3:find("unverified", 1, true), "an officer's own line is shown as theirs")
end
errorsSoFar("H2")

---------------------------------------------------------------------------
print("M1: escape codes")
do
    local link = "|cff0070dd|Hitem:100::|h[New Helm]|h|r"
    send(mal, "GCHAT", { a = "Mal Mischief", g = G.mal, gu = "Ashen Order",
                         t = "look " .. link .. " |cffff0000[RUIN] Your key was reset|r |Hurl:evil|h[click]|h\n[RUIN] fake line", c = "WARRIOR" }, "ORG")
    Server:Advance(2)
    local l = chatLine(eve, "look ")
    check(l ~= nil, "the line arrives")
    check(l and l:find(link, 1, true), "item links stay clickable")
    check(l and not l:find("|cffff0000", 1, true) and not l:find("|Hurl", 1, true), "color codes and fake links are neutralized")
    check(l and not l:find("\n", 1, true), "no line breaks (no fake second line)")
    check(eve.ns.SafeText("a|Tinterface\\x:9999|tb") == "a/Tinterface\\x:9999/tb", "textures too")
    local offered = deepcopy(key(alice)); offered.org = "|cffff0000Blizzard|r"
    local enc = alice.ns.Org.Encode(offered)
    local dec = eve.ns.Org.Decode(enc)
    check(dec and not dec.org:find("|c", 1, true), "a pasted key's text is cleaned too")
end
errorsSoFar("M1")

---------------------------------------------------------------------------
print("M2: identity in messages")
do
    -- a guildmate claiming Olga's GUID
    send(mal, "HELLO", { g = G.olga, v = "0.4.5", p = 1, kr = 1, o = 1, b = 1, org = "RUIN" }, "GUILD")
    Server:Advance(2)
    check(alice.ns.Presence:NameForGUID(G.olga) ~= "Mal Mischief", "a guildmate can't take another's GUID")
    -- Mal pretends to be in Briar Fang and sends its roster with himself as guild master
    send(mal, "OHELLO", { g = G.mal, v = "0.4.5", gu = "Briar Fang", o = 1, kr = 1 }, "ORG")
    Server:Advance(2)
    local before = alice.ns.db.orgRosters and alice.ns.db.orgRosters.guilds["Briar Fang"]
    local gmBefore
    for _, m in ipairs(before and before.members or {}) do if m.rank == 0 then gmBefore = m.name end end
    send(mal, "OROSTER", { gu = "Briar Fang", s = "zz", p = 1, n = 1, t = alice.env.GetServerTime(),
                           m = { "Mal Mischief\t60\tWARRIOR\tOrgrimmar\t0\t\t1\t" } }, "ORG")
    Server:Advance(2)
    local after = alice.ns.db.orgRosters.guilds["Briar Fang"]
    local gmAfter
    for _, m in ipairs(after and after.members or {}) do if m.rank == 0 then gmAfter = m.name end end
    check(gmBefore == "Cara Cole" and gmAfter == "Cara Cole", "a forged roster can't crown a new guild master")
    send(mal, "OFFICES", { gu = "Briar Fang", t = alice.env.GetServerTime(), by = "Cara Cole",
                           l = { { title = "Treasurer", name = "Mal Mischief" } } }, "ORG")
    Server:Advance(2)
    check(not alice.ns.People:HasOffice("Mal Mischief", "Treasurer"), "or appoint offices in another's name")
    send(mal, "GSET", { gu = "Ashen Order", er = 9, t = alice.env.GetServerTime() + 1, by = "Alice Ash" }, "GUILD")
    Server:Advance(2)
    check(olga.ns.Guild:EventRank() ~= 9, "or change guild settings in an officer's name")
end
errorsSoFar("M2")

---------------------------------------------------------------------------
print("M3 and L2: far-future times, bad numbers")
do
    send(olga, "GSET", { gu = "Ashen Order", er = 2, t = alice.env.GetServerTime() + 1e9 }, "GUILD")
    Server:Advance(2)
    check(alice.ns.Guild:EventRank() ~= 2, "a far-future setting is refused (even from an officer)")
    local ok = olga.ns.Guild:SetEventRank(3)
    Server:Advance(2)
    check(ok and alice.ns.Guild:EventRank() == 3, "legit: an officer's setting arrives")
    local v, err = alice.ns.Deserialize("n1e999;")
    check(v == nil and err, "infinity doesn't deserialize")
    local v2, err2 = alice.ns.Deserialize("{s1:an1;n0/0;n1;}")
    check(v2 == nil and err2, "nor NaN")
    check(alice.ns.SaneTime(alice.env.GetServerTime() + 60) and not alice.ns.SaneTime(alice.env.GetServerTime() + 3600), "SaneTime allows clock drift, not the future")
end
errorsSoFar("M3")

---------------------------------------------------------------------------
print("L1: floods")
do
    -- Mal starts 50 long messages and never finishes them
    for i = 1, 50 do
        local text = table.concat({ "1", "Muster:EVENT", "mal" .. i, 1, 3, "{s1:a" }, "\030")
        mal.env.C_ChatInfo.SendAddonMessage("RUIN", text, "CHANNEL", mal.env.GetChannelName(key(mal).c.n))
    end
    Server:Advance(5)
    local partials = upvalue(eve.ns.Comms.OnAddonMessage, "partials")
    local n = 0
    for _, p in pairs(partials or {}) do if p.sender == "Mal Mischief" then n = n + 1 end end
    check(partials ~= nil and n <= 8, "half-sent messages per sender are capped (" .. n .. ")")
    -- a real long message still gets through
    local long = string.rep("x", 600)
    Server:GuildSay("Briar Fang", { name = "Cara Cole", guid = G.cara }, "long:" .. long:sub(1, 300))
    Server:Advance(5)
    check(chatHas(alice, "long:xxx"), "legit long lines still arrive")
end
errorsSoFar("L1")

---------------------------------------------------------------------------
print("Review fixes")
do
    local now = alice.env.GetServerTime()
    -- a member's hello can't push the admin's next revision ahead
    local r0 = key(alice).rev
    send(mal, "OHELLO", { g = G.mal, v = "0.4.5", gu = "Ashen Order", kr = r0 + 450 }, "ORG")
    send(mal, "HELLO", { g = G.mal, v = "0.4.5", p = 1, kr = r0 + 450, org = "RUIN" }, "GUILD")
    Server:Advance(2)
    Server:Slash(alice, "key editguild Grey Wolves, Grey Wolves, 1, Wolves")
    Server:Advance(30)
    check(key(alice).rev == r0 + 1 and key(eve).rev == r0 + 1, "a member's reported revision doesn't move the admin's next one")
    -- rally pins: not from an ordinary member
    send(mal, "Muster:EVENT", { id = "malrally", title = "Rally!", at = now, by = "Mal Mischief", t = now, signups = {},
                                rally = { map = 1, x = 0.5, y = 0.5, zone = "Ambush Alley" } }, "ORG")
    Server:Advance(2)
    local e1 = eve.env.RUIN_MusterDB.events.malrally
    check(not (e1 and e1.rally), "a member's event carries no rally pin")
    send(olga, "Muster:EVENT", { id = "olgarally", title = "Rally at the gate", at = now, by = "Olga Oak", t = now, signups = {},
                                 rally = { map = 1, x = 0.5, y = 0.5, zone = "Gate" } }, "ORG")
    Server:Advance(2)
    local e2 = eve.env.RUIN_MusterDB.events.olgarally
    check(e2 and e2.rally, "an officer's rally pin arrives")
    -- someone else's GUID, learned from their org hello
    local evId
    for id, ev in pairs(eve.env.RUIN_MusterDB.events) do if ev.title == "Molten Core" then evId = id end end
    send(mal, "Muster:SIGN", { id = evId, g = G.cara, s = { n = "Mal Mischief", role = "D", t = now } }, "ORG")
    Server:Advance(2)
    local su = eve.env.RUIN_MusterDB.events[evId].signups[G.cara]
    check(not (su and su.n == "Mal Mischief"), "a sign-up can't use another member's GUID")
    -- a line can't wear another guild's tag
    send(mal, "GCHAT", { a = "Mal Mischief", g = G.mal, gu = "Briar Fang", t = "WRONG TAG line", c = "WARRIOR" }, "ORG")
    Server:Advance(2)
    check(not chatHas(alice, "WRONG TAG line"), "a line under another guild's tag is dropped")
    -- key offers to someone who has a key: only from the admin or an officer
    if eve.env.RUIN_ConfirmDialog then eve.env.RUIN_ConfirmDialog.onAccept = nil end
    local other = deepcopy(key(mal)); other.org = "Not RUIN"; other.admin = G.mal; other.an = { "Mal Mischief" }
    send(mal, "FULLKEY", { k = other }, "PEER", "Eve Ember")
    send(xan, "FULLKEY", { k = other }, "PEER", "Eve Ember")
    Server:Advance(3)
    check(not (eve.env.RUIN_ConfirmDialog and eve.env.RUIN_ConfirmDialog.onAccept), "nobody but the admin or an officer can offer a key to a member")
end
errorsSoFar("review")

print(("\n%d passed, %d failed, %d addon messages sent"):format(pass, fail, Server.sent))
os.exit(fail == 0 and 0 or 1)
