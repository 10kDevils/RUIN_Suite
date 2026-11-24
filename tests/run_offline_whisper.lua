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
