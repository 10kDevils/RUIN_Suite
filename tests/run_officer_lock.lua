-- Locking someone out of the officer channel: a new one goes by whisper to
-- the officers RUIN can vouch for, never over the old channel.
local alice, cara, eve, check, errorsSoFar = T.alice, T.cara, T.eve, T.check, T.errorsSoFar

print("Core: lock an ex-officer out of the officer channel")
do
    local A, C, E = alice.ns.Org, cara.ns.Org, eve.ns.Org
    cara.ns.Presence:SendOfficerHello()
    Server:Advance(5)
    local old = alice.ns.DeepCopy(A:Get().oc)
    -- Eve kept the officer channel from when she was an officer, and listens on it
    eve.ns.db.orgKey.oc = alice.ns.DeepCopy(old)
    eve.ns.Comms:SetChannel("OFFICERS", old.n, old.p)
    Server:Advance(5)
    check(A:RotateOfficerChannel({ "Eve Ember" }), "the admin makes a new officer channel, leaving Eve out")
    Server:Advance(30)
    local new = A:Get().oc
    check(new.n ~= old.n, "the officer channel changed")
    check(C:Get().oc and C:Get().oc.n == new.n, "the other guild's officer has the new one")
    local eoc = E:Get().oc
    check(not (eoc and eoc.n == new.n), "the ex-officer listening on the old channel doesn't get it")
    check(not alice.ns.Presence:IsOfficerName("Eve Ember"), "and isn't counted as an officer any more")
    check(cara.ns.Comms:IsJoined("OFFICERS") and alice.ns.Comms:IsJoined("OFFICERS"), "officers are on the new channel")
    -- an ordinary edit (no new officer channel) still reaches officers with theirs kept
    check(A:SetLinks({ { label = "Discord", url = "https://discord.gg/x" } }), "a later edit")
    Server:Advance(20)
    check(C:Get().oc and C:Get().oc.n == new.n, "keeps officers on the new officer channel")
    errorsSoFar("officer lock-out")
end

print("Core: an officer who is demoted gets locked out")
do
    local A = alice.ns.Org
    -- Grimlock is an officer in Alice's guild roster; demote him
    local norm
    for n, e in pairs(alice.ns.roster) do if alice.ns.Org:IsOfficerRank(e.rank) and n ~= alice.ns.playerNorm then norm = n end end
    if not norm then
        alice.ns.roster["grimlock"] = { name = "Grimlock", rank = 1 }
        norm = "grimlock"
        alice.ns:Fire("ROSTER_UPDATED")
    end
    local who = alice.ns.roster[norm].name
    alice.ns.roster[norm].rank = 5
    alice.ns:Fire("ROSTER_UPDATED")
    Server:Advance(10)
    local dlg = alice.env.RUIN_ConfirmDialog
    local title = dlg and dlg.title and dlg.title:GetText()
    check(title == "Lock out of the officer channel?", "the admin is asked to lock out " .. tostring(who) .. " (" .. tostring(title) .. ")")
    local before = A:Get().oc.n
    dlg.onAccept()
    Server:Advance(20)
    check(A:Get().oc.n ~= before, "and accepting makes a new officer channel")
    errorsSoFar("demoted officer")
end

print("Core: what RUIN shares about you")
do
    local s = eve.ns.db.settings
    s.share = { zone = false }
    eve.ns.Presence:SendOrgHello()
    Server:Advance(5)
    local seen
    for _, p in ipairs(alice.ns.Presence:GetOnlineList()) do if p.name and p.name:find("Eve") then seen = p end end
    check(seen and not seen.zone, "with zone sharing off, other guilds see you online without a zone (" .. tostring(seen and seen.zone) .. ")")
    check(not eve.env.RUIN_API:Shares("zone") and eve.env.RUIN_API:Shares("loot"), "each kind is its own switch, on unless turned off")
    s.share = nil
    T.openAllSubTabs(eve, "Options")
    errorsSoFar("privacy switches")
end
