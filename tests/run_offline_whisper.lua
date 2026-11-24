-- Whispers to players who aren't online: the key goes to online officers only, and the
-- game's "No player named ..." line for a player RUIN just whispered is hidden. Runs in run_features.lua.
local alice, check, errorsSoFar = T.alice, T.check, T.errorsSoFar

print("Core: whispers to offline players")
do
    local ns = alice.ns
    local Comms = ns.Comms
    check(Comms.NotFoundName("No player named 'Epic Pollon' is currently playing.") == "Epic Pollon", "reads the game's line")
    -- a whisper RUIN sent a moment ago: the line is hidden, the rest of that message dropped, further whispers held
    Comms:Send("VREQ", { pad = string.rep("x", 900) }, "PEER", "Epic Pollon", Comms.PRIORITY.NORMAL)
    Comms:NoteWhisper("Epic Pollon")
    check(Comms:OnSystemMessage("No player named 'Epic Pollon' is currently playing."), "the line about a player RUIN just whispered is hidden")
    check(Comms:PeerOffline("Epic Pollon"), "and RUIN holds further whispers to them")
    check(not Comms:OnSystemMessage("No player named 'Someone Else' is currently playing."), "a line about anyone RUIN didn't whisper stays")
    Comms:PeerSeen("Epic Pollon-Realm")
    check(not Comms:PeerOffline("Epic Pollon"), "hearing from them again lifts the hold")
    -- a send the player chose (the key offer, the admin hand-over) always goes out, and the game's line shows once
    local whispers = {}
    local realTap = Server.tap
    Server.tap = function(c, prefix, text, chatType, target)
        if c == alice and chatType == "WHISPER" then whispers[target] = (whispers[target] or 0) + 1 end
        if realTap then realTap(c, prefix, text, chatType, target) end
    end
    Comms:Send("VREQ", {}, "PEER", "Gone Gary", Comms.PRIORITY.NORMAL)
    Server:Advance(2)
    check(Comms:OnSystemMessage("No player named 'Gone Gary' is currently playing.") and Comms:PeerOffline("Gone Gary"), "background whisper: line hidden, player held")
    whispers = {}
    Comms:Send("VREQ", {}, "PEER", "Gone Gary", Comms.PRIORITY.BULK)
    Server:Advance(2)
    check(not whispers["Gone Gary"], "a background whisper to a held player is dropped")
    check(ns.Org:SendFullKey("Gone Gary"), "the admin offers the key to a held player")
    Server:Advance(5)
    check((whispers["Gone Gary"] or 0) > 0, "the key offer still goes out")
    check(not Comms:OnSystemMessage("No player named 'Gone Gary' is currently playing."), "the game's line about the player's own send is shown")
    check(Comms:OnSystemMessage("No player named 'Gone Gary' is currently playing."), "once: the repeat for the next part is hidden")
    check(Comms:PeerOffline("Gone Gary"), "background whispers to them are held again")
    whispers = {}
    Comms:Send("VREQ", {}, "PEER", "Gone Gary", Comms.PRIORITY.BULK)
    Server:Advance(2)
    check(not whispers["Gone Gary"], "and a background whisper is still dropped")
    Server:Advance(20)
    check(ns.Org:SendFullKey("Gone Gary"), "asked again within the hold")
    Server:Advance(5)
    check((whispers["Gone Gary"] or 0) > 0, "the retry goes out too")
    check(not Comms:OnSystemMessage("No player named 'Gone Gary' is currently playing."), "the retry's line is shown")
    -- a retry right after (well within 15 s) still shows its own line, once
    Server:Advance(3)
    check(ns.Org:SendFullKey("Gone Gary"), "asked again a few seconds later")
    Server:Advance(2)
    check(not Comms:OnSystemMessage("No player named 'Gone Gary' is currently playing."), "a quick retry's line is shown too")
    check(Comms:OnSystemMessage("No player named 'Gone Gary' is currently playing."), "and only once for that send")
    Server.tap = realTap
    Comms:PeerSeen("Gone Gary")
    -- the key: offline officers in your roster aren't whispered
    local realKnown = ns.Presence.KnownOfficers
    ns.Presence.KnownOfficers = function() return {
        { name = "Mepti Starbuck", guild = "Ashen Order", online = false, roster = true },
        { name = "Bob Brook", guild = "Ashen Order", online = true, roster = true } } end
    local sent = {}
    local realSend = Comms.Send
    Comms.Send = function(self, kind, d, scope, target, ...) if kind == "ORGKEY" and scope == "PEER" then sent[target] = true end; return realSend(self, kind, d, scope, target, ...) end
    ns.Org:RotateOfficerChannel()
    Server:Advance(10)
    Comms.Send, ns.Presence.KnownOfficers = realSend, realKnown
    check(sent["Bob Brook"] and not sent["Mepti Starbuck"], "a new key is whispered to online officers only")
    Server:Advance(60)
    errorsSoFar("offline whispers")
end
