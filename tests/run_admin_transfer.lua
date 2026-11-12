-- Handing the org admin over: the admin offers, the other player accepts,
-- and every client follows the new admin. Runs last (and hands it back).
local alice, cara, eve, check, errorsSoFar = T.alice, T.cara, T.eve, T.check, T.errorsSoFar

print("Core: transfer the org admin")
do
    local A, C, E = alice.ns.Org, cara.ns.Org, eve.ns.Org
    check(A:IsAdmin() and not C:IsAdmin(), "before: Alice is the org admin")
    local ok, err = C:OfferAdmin("Eve Ember")
    check(not ok and err:find("Only the org admin", 1, true), "only the admin can hand it over")
    -- someone who isn't the admin can't push a key naming a new admin
    local forged = alice.ns.DeepCopy(E:Get())
    forged.admin, forged.an, forged.rev = eve.guid, { "Eve Ember" }, forged.rev + 1
    cara.ns.Comms:Send("ORGKEY", { k = forged }, "PEER", "Alice Ash", cara.ns.Comms.PRIORITY.ALERT)
    Server:Advance(5)
    check(A:IsAdmin() and A:Get().admin == alice.guid, "a key from someone else naming a new admin is ignored")

    check(A:OfferAdmin("Cara Cole"), "Alice offers the admin to Cara")
    Server:Advance(5)
    local dlg = cara.env.RUIN_ConfirmDialog
    local title = dlg and dlg.title and dlg.title.GetText and dlg.title:GetText()
    check(dlg and dlg.onAccept and title == "Become the RUIN org admin?", "Cara is asked to accept (" .. tostring(title) .. ")")
    dlg.onAccept()
    Server:Advance(30)
    check(C:IsAdmin() and C:Get().admin == cara.guid, "Cara is now the org admin")
    check(not A:IsAdmin(), "and Alice no longer is")
    check(E:Get().admin == cara.guid and E:IsAdminName("Cara Cole") and not E:IsAdminName("Alice Ash"), "Eve's key follows the new admin")
    local ok2, err2 = A:AddGuild("Some Guild", 1, "SG")
    check(not ok2 and err2:find("Only the org admin", 1, true), "Alice can't change the key any more")
    check(C:AddGuild("Fresh Guild", 1, "FG"), "Cara can")
    Server:Advance(30)
    check(A:GuildInfo("Fresh Guild") and E:GuildInfo("Fresh Guild"), "and her edit reaches Alice and Eve")
    -- hand it back so the rest of the suite is as it was
    C:OfferAdmin("Alice Ash")
    Server:Advance(5)
    alice.env.RUIN_ConfirmDialog.onAccept()
    Server:Advance(30)
    check(A:IsAdmin() and not C:IsAdmin(), "and back again")
    errorsSoFar("admin transfer")
end
