-- Finder 0.7.2: the listing card's dropdowns (which one, spec / profession /
-- tone), Rares, group size, Allow Queue and the join request list.
local alice, cara, check, chatHas, errorsSoFar = T.alice, T.cara, T.check, T.chatHas, T.errorsSoFar

print("Finder 0.7.2: listing dropdowns, group size, queue, requests")
do
    local Lst = alice.mns.RUIN_Finder.Lists
    check(Lst.Has(Lst.DETAILS.Raid, "Molten Core") and Lst.Has(Lst.DETAILS.Dungeon, "Gnomeregan"), "dungeons and raids are listed")
    check(Lst.Has(Lst.DETAILS.Questing, "Riverglades") and not Lst.Has(Lst.DETAILS.Questing, "Stormwind City")
        and not Lst.Has(Lst.DETAILS.Questing, "Dalaran") and not Lst.Has(Lst.DETAILS.Questing, "Thunder Bluff"), "zones, but no cities")
    check(table.concat(Lst.DETAILS.PvP, ",") == "Dueling,World,Battlegrounds" and table.concat(Lst.DETAILS.Rares, ",") == "Mobs,Items,Secrets"
        and table.concat(Lst.DETAILS.Professions, ",") == "Farming,Services" and table.concat(Lst.DETAILS.Social, ",") == "Just Chatting,Theory Craft,RP",
        "PvP, Rares, Professions and Social have their categories")
    check(Lst.Has(Lst.PROFESSIONS, "Fishing") and Lst.Has(Lst.PROFESSIONS, "Lockpicking") and Lst.Has(Lst.PROFESSIONS, "Tailoring"),
        "professions: primary, secondary and class")

    local R = alice.env.RUIN_API
    local F = R:GetModule("Finder")
    local db = alice.env.RUIN_FinderCharDB
    R:OpenTab("Finder")
    local ui = F.UI
    alice.env.SlashCmdList.RUINFINDER("group rares")
    check(db.activity == "Rares" and db.listing == "Group", "Rares is an activity")
    ui.activity._scripts.OnClick(ui.activity, "LeftButton")
    local names = {}
    for _, it in ipairs(ui.activity.items or {}) do names[#names + 1] = it:GetText() end
    check(table.concat(names, ","):find("Questing,Rares,Professions", 1, true), "right after Questing in the list (" .. table.concat(names, ",") .. ")")
    ui.activity.menu:Hide()

    -- the detail dropdown follows the activity
    db.activity = "Raid"; ui.detail:Refresh()
    ui.detail:Open()
    local hasMC = false
    for _, it in ipairs(ui.detail.items) do if it:GetText() == "Molten Core" then hasMC = true; it._scripts.OnClick(it) break end end
    check(hasMC and db.detail == "Molten Core", "picking Raid lists the raids, and one can be picked")

    -- the spec box
    db.spec = "Auto"
    db.activity = "Dungeon"; ui.spec:Refresh()
    check(ui.spec:GetText():find("^Auto"), "spec starts on Auto (" .. ui.spec:GetText() .. ")")
    db.activity = "Professions"; ui.spec:Refresh()
    ui.spec:Open()
    local prof = {}
    for _, it in ipairs(ui.spec.items) do prof[#prof + 1] = it:GetText() end
    check(table.concat(prof, ","):find("Alchemy", 1, true), "Professions: the spec box lists professions")
    ui.spec.items[3]._scripts.OnClick(ui.spec.items[3])
    check(db.profession == prof[3], "and picking one sets it")
    db.activity = "Social"; ui.spec:Refresh()
    ui.spec:Open()
    check(ui.spec.items[1]:GetText() == "Casual" and ui.spec.items[3]:GetText() == "Engaged", "Social: the tone")
    ui.spec.menu:Hide()

    -- group size, queue and requests
    db.activity = "Dungeon"; db.detail = "Gnomeregan"
    db.looking, db.listing = true, "Group"
    db.groupSize, db.allowQueue = 1, false
    local cf = cara.env.RUIN_API:GetModule("Finder")
    cf:Send("JOINREQ", { g = cara.guid, c = "WARRIOR", l = 20, role = "Tank", a = "Dungeon" }, "PEER", "Alice Ash")
    Server:Advance(5)
    check(#F.Requests() == 0 and chatHas(cara, "is full"), "a full group turns requests away and says so")
    db.allowQueue = true
    Server:Advance(61)
    cf:Send("JOINREQ", { g = cara.guid, c = "WARRIOR", l = 20, sp = "Protection", role = "Tank", a = "Dungeon" }, "PEER", "Alice Ash")
    Server:Advance(5)
    local rq = F.Requests()
    check(#rq == 1 and rq[1].queued and rq[1].sp == "Protection", "with Allow Queue on, they wait in the queue")
    check(ui.reqRows[1]._shown ~= false and ui.reqRows[1].text:GetText():find("Queued", 1, true), "the request shows on the listing card")
    local invited
    alice.env.C_PartyInfo = { InviteUnit = function(n) invited = n end }
    ui.reqRows[1].yes._scripts.OnClick(ui.reqRows[1].yes)
    check(invited == "Cara Cole" and #F.Requests() == 0, "Invite invites them and takes them off the list")

    db.groupSize = 0
    Server:Advance(61)
    cf:Send("JOINREQ", { g = cara.guid, c = "WARRIOR", l = 20, role = "Tank", a = "Dungeon" }, "PEER", "Alice Ash")
    Server:Advance(5)
    check(#F.Requests() == 1 and not F.Requests()[1].queued, "no size: requests come in as usual")
    ui.reqRows[1].no._scripts.OnClick(ui.reqRows[1].no)
    Server:Advance(5)
    check(#F.Requests() == 0 and chatHas(cara, "declined"), "Decline takes them off and lets them know")
    alice.env.SlashCmdList.RUINFINDER("off")
    db.listing = "Player"
    errorsSoFar("finder listing")
end
