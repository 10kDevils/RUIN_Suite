-- Leaving the org (anyone) and disbanding it (the admin). Runs last: the
-- org is gone afterwards.
local alice, cara, eve, check, errorsSoFar = T.alice, T.cara, T.eve, T.check, T.errorsSoFar

print("Core: leave and disband the org")
do
    local A, C, E = alice.ns.Org, cara.ns.Org, eve.ns.Org
    local ok, err = A:Leave()
    check(not ok and err:find("hand the admin over", 1, true) and A:Get(), "the admin can't just leave (transfer or disband instead)")

    check(E:Leave() and E:Get() == nil, "Eve leaves: her key is gone")
    Server:Advance(5)
    check(not eve.ns.Comms:IsJoined("ORG"), "and she's off the org channel")
    cara.ns.Presence:SendGuildHello(true)
    eve.ns.Presence:SendGuildHello(true)
    Server:Advance(120)
    check(E:Get() == nil, "her guild's officer doesn't hand the key back on its own")
    C:SendFullKey("Eve Ember")
    Server:Advance(3)
    eve.env.RUIN_ConfirmDialog.onAccept()
    Server:Advance(30)
    check(E:Get() ~= nil and not E.Refused(E:Get().org), "accepting the key again brings her back")

    -- a straggler copy of the key, to see the disband reach someone who missed it
    local old = alice.ns.DeepCopy(E:Get())
    ok, err = C:Disband()
    check(not ok, "only the admin can disband")
    check(A:Disband(), "Alice disbands the org")
    Server:Advance(10)
    check(A:Get() == nil and C:Get() == nil and E:Get() == nil, "every member online drops the key")
    check(not cara.ns.Comms:IsJoined("ORG") and not alice.ns.Comms:IsJoined("ORG"), "and leaves the org channel")
    check(C.Refused(old.org), "and won't take that org's key back on its own")
    -- Eve was offline: she still has the key and says so in her guild hello
    eve.ns.db.orgKey = old
    eve.ns.Presence:SendGuildHello(true)
    Server:Advance(20)
    check(E:Get() == nil, "a member who missed it hears it from a guildmate who didn't")
    errorsSoFar("leave and disband")
end
