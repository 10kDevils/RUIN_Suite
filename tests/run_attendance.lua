-- Muster attendance (noted by an event's leaders while it runs, shared with
-- everyone) and reminders before events you signed up for. Runs inside run_features.lua.
local alice, cara, eve, check, errorsSoFar = T.alice, T.cara, T.eve, T.check, T.errorsSoFar

print("Muster: attendance and reminders")
do
    local mu = alice.env.RUIN_API:GetModule("Muster")
    local AA, EA = alice.mns.RUIN_Muster.Attendance, eve.mns.RUIN_Muster.Attendance
    check(AA and AA.Snapshot, "Muster has attendance")
    -- an event starting in 40 minutes; Eve and Cara sign up
    local ev = mu:Create("Attendance test", os.date("%Y-%m-%d %H:%M", alice.env.GetServerTime() + 40 * 60), { kind = "Raid" })
    Server:Advance(5)
    eve.env.RUIN_API:GetModule("Muster"):SignUp(ev.id, "H")
    cara.env.RUIN_API:GetModule("Muster"):SignUp(ev.id, "T")
    Server:Advance(5)
    -- reminders: 30 minutes before, once; then 5 minutes before
    local function toastCount(c) local n = 0; for _, l in ipairs(c.chat) do if l:find("Attendance test starts in", 1, true) then n = n + 1 end end; return n end
    EA.CheckReminders()
    check(toastCount(eve) == 0, "no reminder 40 minutes out")
    local base = alice.env.GetServerTime
    local shift = 0
    for _, c in ipairs({ alice, eve, cara }) do c.env.GetServerTime = function() return base() + shift end end
    shift = 12 * 60
    EA.CheckReminders()
    check(toastCount(eve) == 1 and T.chatHas(eve, "you signed up as healer"), "30 minutes before: reminded, with your role")
    EA.CheckReminders()
    check(toastCount(eve) == 1, "only once")
    shift = 36 * 60
    EA.CheckReminders()
    check(toastCount(eve) == 2, "and again 5 minutes before")
    eve.env.RUIN_MusterDB.remind = false
    eve.env.RUIN_MusterDB.reminded = {}
    check(EA.CheckReminders() == 0, "Remind me off: no reminders")
    eve.env.RUIN_MusterDB.remind = true
    -- the event runs: Alice (its author) is in a raid with Eve; Cara signed up and didn't come
    shift = 50 * 60
    local saved = { raid = alice.env.IsInRaid, grp = alice.env.IsInGroup, n = alice.env.GetNumGroupMembers, info = alice.env.GetRaidRosterInfo }
    alice.env.IsInRaid = function() return true end
    alice.env.IsInGroup = function() return true end
    alice.env.GetNumGroupMembers = function() return 2 end
    alice.env.GetRaidRosterInfo = function(i) return ({ "Alice Ash", "Eve Ember" })[i] end
    check(AA.Snapshot() >= 1 and alice.env.RUIN_MusterDB.attend[ev.id].present["eve ember"] == "Eve Ember",
        "the leader notes who's in the raid")
    Server:Advance(10)
    alice.env.IsInRaid, alice.env.IsInGroup, alice.env.GetNumGroupMembers, alice.env.GetRaidRosterInfo = saved.raid, saved.grp, saved.n, saved.info
    -- after the event, everyone sees the same numbers
    shift = 5 * 3600
    local function rowOf(stats, name) for _, r in ipairs(stats) do if r.name == name then return r end end end
    local es = EA.Stats()
    local eveRow, caraRow = rowOf(es, "Eve Ember"), rowOf(es, "Cara Cole")
    local rec = eve.env.RUIN_MusterDB.attend[ev.id]
    check(rec and rec.present["eve ember"] and rec.present["alice ash"] and not rec.present["cara cole"], "the leader's note reaches everyone")
    check(eveRow and eveRow.attended >= 1 and eveRow.signed >= 1 and eveRow.missed == 0 and eveRow.rate == 100,
        "Eve sees she attended what she signed up for")
    check(caraRow and caraRow.missed >= 1 and (caraRow.rate or 100) < 100, "and that Cara signed up and missed it")
    -- someone who isn't the event's leader or an officer can't write attendance
    local before = rowOf(AA.Stats(), "Nobody Here")
    eve.env.RUIN_API:GetModule("Muster"):Send("ATTEND", { id = ev.id, ti = "x", at = ev.at, n = { "Nobody Here" } }, "ORG")
    Server:Advance(10)
    check(not rowOf(AA.Stats(), "Nobody Here") and not before, "a member's attendance message is ignored")
    for _, c in ipairs({ alice, eve, cara }) do c.env.GetServerTime = base end
    alice.env.RUIN_API:OpenTab("Muster")
    T.openAllSubTabs(alice, "Muster")
    mu:Delete(ev.id)
    errorsSoFar("attendance")
end
