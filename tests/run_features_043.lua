-- RUIN 0.4.3 batch: census, people and offices, the Watch, chat tools, joining,
-- update tools, guild bank; Finder where / layers / hops / marks / timers;
-- Exchange treasury and crafting history; Muster Most Wanted, War Room, loot notes.
local alice, cara, eve = T.alice, T.cara, T.eve
local check, chatHas, errorsSoFar = T.check, T.chatHas, T.errorsSoFar
local fire = Server.fire

---------------------------------------------------------------------------
print("Core 0.4.3: census, people and offices")
do
    Server:Advance(400)
    alice.ns.OrgRoster:AskMissing()
    Server:Advance(60)
    local Census = alice.ns.Census
    local rows = Census:Rows()
    local by = {}
    for _, r in ipairs(rows) do by[r.name] = r end
    check(by["Ashen Order"] and by["Briar Fang"], "the census has a row for every org guild")
    check(by["Briar Fang"].leader == "Cara Cole" and by["Briar Fang"].members >= 2, "with members and the guild master")
    local t = Census:Totals()
    check(t.guilds >= 2 and t.characters >= 3, "and totals for the org")
    local res = Census:Search("BRlAR")
    local kinds = {}
    for _, r in ipairs(res) do kinds[r.kind] = true end
    check(kinds.guild, "search finds a guild with look-alike letters (l for I)")
    res = Census:Search("cara")
    kinds = {}
    for _, r in ipairs(res) do kinds[r.kind] = true end
    check(kinds.leader, "and a guild master by name")
    res = Census:Search("free 500")
    check(#res == t.guilds and res[1].kind == "recruiting", "free 500 lists guilds with room")
    Census:Sample()
    local days = Census:DaySeries()
    check(#days == 30 and days[30].value == t.characters, "today's count goes into the 30-day history")
    check(#Census:HourSeries() == 24, "and the 24-hour one")

    -- offices: the guild master appoints, everyone sees them
    local CP, EP = cara.ns.People, eve.ns.People
    check(not EP:CanAppoint(), "a member can't appoint offices")
    local ok = CP:Appoint("Treasurer", "Eve Ember")
    Server:Advance(5)
    check(ok and alice.ns.People:HasOffice("Eve Ember", "Treasurer"), "Cara made Eve Treasurer and Alice's RUIN knows")
    check(eve.env.RUIN_API:HasOffice("Eve Ember", "treasurer"), "modules can ask (API level 11)")
    local h = alice.ns.People:Hierarchy()
    check(#h > 0, "the hierarchy lists the guilds' leaders and officers")
    local g = alice.ns.People:Grouped("class", "", false)
    check(#g > 0 and g[1].header ~= nil, "people grouped by class")
    alice.env.RUIN_API:OpenTab("Guild")
    T.openAllSubTabs(alice, "Guild")
    errorsSoFar("census and people")
end

---------------------------------------------------------------------------
print("Core 0.4.3: the Watch")
do
    local W = eve.ns.Watch
    check(not W:IsModerator() and alice.ns.Watch:IsModerator() and cara.ns.Watch:IsModerator(), "officers and the admin moderate")
    local ok, how = W:Report("Spammy McSpam", "Spam", "flooding org chat")
    check(ok and how == "sent", "Eve's report goes to an officer online")
    Server:Advance(10)
    local cases = cara.ns.Watch:Cases("open")
    check(#cases == 1 and cases[1].target == "Spammy McSpam" and cases[1].reason == "Spam", "the officer opened a case")
    check(#alice.ns.Watch:Cases("open") == 1, "every officer of the org sees it")
    check(W:MyReports()[1].status == "received by an officer", "Eve sees her report arrived")
    check(#eve.ns.Watch:Cases("open") == 0, "members don't see cases")

    -- sanctions follow the player
    ok = alice.ns.Watch:Sanction("mute", "Eve Ember", 1800, "testing")
    Server:Advance(5)
    check(ok and cara.ns.Watch:IsMuted("Eve Ember"), "a mute reaches the other officers")
    check(chatHas(eve, "muted in RUIN chat"), "and Eve is told on her screen")
    check(cara.ns.Chat:Hidden("Eve Ember", "hello"), "her RUIN chat lines are hidden")
    local ok2, err = cara.ns.Watch:Sanction("hide", "Alice Ash", 0, "x")
    check(not ok2 and err:find("org admin"), "an officer can't sanction the org admin")
    local s = alice.ns.Watch:Sanctions(false)[1]
    alice.ns.Watch:Lift(s.id)
    Server:Advance(5)
    check(not cara.ns.Watch:IsMuted("Eve Ember"), "lifting ends it for everyone")
    -- warnings climb a ladder
    local okw, text = alice.ns.Watch:Warn("Eve Ember", "language", cases[1] and cases[1].id)
    check(okw and text:find("Warning 1"), "a first warning mutes for a few minutes")
    Server:Advance(5)
    for _, x in ipairs(alice.ns.Watch:Sanctions(false)) do alice.ns.Watch:Lift(x.id) end
    Server:Advance(5)
    -- hide: their RUIN messages are dropped
    alice.ns.Watch:Sanction("hide", "Eve Ember", 600, "test hide")
    Server:Advance(5)
    check(cara.ns.Watch:IsHidden("Eve Ember"), "hide reaches the org")
    for _, x in ipairs(alice.ns.Watch:Sanctions(false)) do alice.ns.Watch:Lift(x.id) end
    Server:Advance(5)
    check(not cara.ns.Watch:IsHidden("Eve Ember"), "and lifts")
    -- log and cover name
    alice.ns.Watch:SetCover("Hawk")
    alice.ns.Watch:DeleteLine("Eve Ember", "bad line")
    Server:Advance(5)
    local log = cara.ns.Watch:LogLines()
    check(log[1] and log[1].a == "Moderator Hawk" and log[1].act == "deleted", "deleting a line is logged under the cover name")
    alice.ns.Watch:SetCover("")
    cara.ns.Watch:SetStatus(cases[1].id, "resolved")
    Server:Advance(5)
    check(#alice.ns.Watch:Cases("open") == 0 and #alice.ns.Watch:Cases("closed") == 1, "resolving a case closes it for every officer")
    -- members don't see the Watch tab; they report through a dialog
    eve.env.RUIN_API:OpenTab("Guild")
    local function watchHidden(c)
        for _, st in ipairs(c.subtabs) do if st.names and st.names[6] == "Watch" then return st.hidden and st.hidden[6] end end
    end
    check(watchHidden(eve), "members don't see the Watch tab")
    check(not watchHidden(alice), "officers do")
    eve.ns.Watch:PromptReport("Spammy")
    eve.env.RUIN_TextDialog.onAccept("spam: gold ads in org chat")
    Server:Advance(10)
    local found
    for _, c in ipairs(cara.ns.Watch:Cases("open")) do if c.target == "Spammy" and c.reason == "Spam" then found = true end end
    check(found, "a member's report from the dialog opens a case with the reason they wrote")
    alice.env.RUIN_API:OpenTab("Guild")
    alice.ns.UI:SelectGuildTab("Watch")
    T.openAllSubTabs(eve, "Guild")
    errorsSoFar("watch")
end

---------------------------------------------------------------------------
print("Core 0.4.3: chat tools, joining, update tools, guild bank")
do
    -- block words and pins
    cara.ns.db.blockWords = { "badword" }
    check(cara.ns.Chat:Hidden("Eve Ember", "what a BADWORD thing"), "personal block words hide lines")
    alice.ns.Org:SetBlockWords({ "orgword" })
    Server:Advance(10)
    check(cara.ns.Chat:Hidden("Eve Ember", "orgword here"), "the admin's block words reach the org with the key")
    local line = { a = "Eve Ember", text = "pin me", t = 1 }
    check(cara.ns.Chat:TogglePin(line) and cara.ns.Chat:IsPinned(line), "a line can be pinned")
    cara.ns.Chat:TogglePin(line)
    check(not cara.ns.Chat:IsPinned(line), "and unpinned")
    alice.ns.Org:SetBlockWords({})
    cara.ns.db.blockWords = {}

    -- join requests reach those who can invite
    local can = alice.env.CanGuildInvite
    alice.env.CanGuildInvite = function() return true end
    cara.ns.Comms:Send("JOINASK", { m = "Let me in please", c = "WARRIOR", l = 20, gu = "Ashen Order" }, "PEER", "Alice Ash", cara.ns.Comms.PRIORITY.ALERT)
    Server:Advance(5)
    local asks = alice.ns.Recruit:Asks()
    check(#asks == 1 and asks[1].name == "Cara Cole" and asks[1].m == "Let me in please", "a join request shows on the Overview")
    check(chatHas(alice, "asks to join"), "and Alice is told")
    local invited
    alice.env.GuildInvite = function(n) invited = n end
    alice.ns.Recruit:Invite("Cara Cole")
    check(invited == "Cara Cole" and #alice.ns.Recruit:Asks() == 0, "Invite sends the guild invite and clears the request")
    alice.env.CanGuildInvite = can
    -- /who for the Join screen
    local sent
    eve.env.C_FriendList = { SendWho = function(q) sent = q end, GetNumWhoResults = function() return 1 end,
                             GetWhoInfo = function() return { fullName = "Alice Ash", fullGuildName = "Ashen Order", level = 20, filename = "WARRIOR", area = "Durotar" } end }
    eve.ns.Recruit:FindMembers("Ashen Order")
    fire(eve, "WHO_LIST_UPDATE")
    local results = eve.ns.Recruit:WhoResults()
    check(sent == 'g-"Ashen Order"' and #results == 1 and results[1].name == "Alice Ash", "Find members online asks /who for the guild")

    -- versions and the right-click menu
    alice.ns.Updates:Check("Cara Cole")
    Server:Advance(5)
    check(chatHas(alice, "Cara Cole runs RUIN") or chatHas(alice, "Cara runs RUIN") or chatHas(alice, "runs RUIN"), "Check RUIN version asks the player")
    local lines = alice.ns.Updates:MenuLines("Cara Cole")
    local hasReport = false
    for _, l in ipairs(lines) do if l.text == "Report to the RUIN Watch" then hasReport = true end end
    check(#lines >= 2 and hasReport, "the right-click menu gets RUIN's lines")
    local hooked = {}
    alice.env.Menu = { ModifyMenu = function(tag, fn) hooked[#hooked + 1] = tag end }
    alice.ns.Updates:HookMenus()
    check(#hooked >= 5, "RUIN adds to the game's player menus")
    alice.ns.Updates:ShowLetter("0.4.2")
    check(alice.env.RUIN_WhatsNew and alice.env.RUIN_WhatsNew:IsShown() ~= false, "the What's new letter opens")
    local U = alice.ns.Updates
    check(#U:NotesSince("0.4.2") == #U:NotesSince("0.4.3") + 1 and #U:NotesSince(U.NOTES[2][1]) == 1 and #U:NotesSince(U.NOTES[1][1]) == 0,
        "with what changed since your version")

    -- guild bank: Cara opens it, Eve sees it
    cara.env.GetNumGuildBankTabs = function() return 2 end
    cara.env.GetGuildBankTabInfo = function(tab) return "Tab " .. tab, "icon", tab == 1 end
    cara.env.GetGuildBankItemInfo = function(tab, slot) if slot <= 2 then return "icon", 5 end end
    cara.env.GetGuildBankItemLink = function(tab, slot) if slot <= 2 then return "|cffffffff|Hitem:2589::|h[Linen Cloth]|h|r" end end
    cara.env.GetGuildBankMoney = function() return 1234567 end
    cara.env.QueryGuildBankTab = function() end
    eve.env.GetNumGuildBankTabs, eve.env.GetGuildBankItemInfo = cara.env.GetNumGuildBankTabs, cara.env.GetGuildBankItemInfo
    fire(cara, "GUILDBANKFRAME_OPENED")
    Server:Advance(5)
    local snap = eve.ns.Bank:Snapshot()
    check(snap and snap.money == 1234567 and #snap.tabs == 1 and snap.tabs[1].i[1][1] == 2589 and snap.tabs[1].i[1][2] == 10,
        "a guild bank snapshot reaches the guild (viewable tabs only, counts added up)")
    check(alice.ns.Bank:Snapshot() == nil, "but not other guilds")
    check(eve.env.RUIN_API:GetGuildBank() ~= nil and eve.env.RUIN_API.apiLevel >= 11, "modules can read it (API level 11)")
    T.openAllSubTabs(eve, "Guild")
    errorsSoFar("chat, join, updates, bank")
end

---------------------------------------------------------------------------
print("Finder 0.4.1: layers, hops, where, marks")
do
    local AL, CL = alice.mns.RUIN_Finder.Layers, cara.mns.RUIN_Finder.Layers
    local zone, npc = AL.Parse("Creature-0-4372-1-1234-3100-0000123456")
    check(zone == 1234 and npc == 3100, "a creature's ID gives its layer")
    check(AL.Parse("Player-1-00000001") == nil and AL.Parse("Pet-0-1-1-55-3100-1") == nil, "players and pets don't count")
    local function creatures(c, guids)
        c.env.UnitExists = function(u) return guids[u] ~= nil or (u == "target" and c.target ~= nil) end
        c.env.UnitIsPlayer = function(u) return guids[u] == nil end
        c.env.UnitPlayerControlled = function() return false end
        local real = c.env.UnitGUID
        c.env.UnitGUID = function(u) return guids[u] or c.guid end
        return function() c.env.UnitGUID = real; c.env.UnitExists = function(u) return u == "target" and c.target ~= nil end; c.env.UnitIsPlayer = function() return true end end
    end
    alice.env.GetRealZoneText = function() return "Durotar" end
    cara.env.GetRealZoneText = function() return "Durotar" end
    local undoA = creatures(alice, { nameplate1 = "Creature-0-1-1-111-3100-1", nameplate2 = "Creature-0-1-1-111-3101-2" })
    AL.Observe("nameplate1")
    check(AL.Mine() == nil, "one creature isn't enough")
    AL.Observe("nameplate2")
    check(AL.Mine() == 111, "two creatures agree: Alice is on layer 111")
    local undoC = creatures(cara, { nameplate1 = "Creature-0-1-1-222-3100-1", nameplate2 = "Creature-0-1-1-222-3102-3" })
    CL.Observe("nameplate1"); CL.Observe("nameplate2")
    check(CL.Mine() == 222, "Cara is on layer 222")
    Server:Advance(40)
    local tbl = CL.Table()
    check(tbl[1] and tbl[1].zone == "Durotar" and #tbl[1].layers == 2, "members share their layer: Durotar has two")
    -- a stray creature from another layer doesn't move you
    undoA()
    undoA = creatures(alice, { nameplate3 = "Creature-0-1-1-999-3100-1" })
    AL.Observe("nameplate3")
    check(AL.Mine() == 111, "one stray creature doesn't change your layer")
    -- hop: Cara asks, Alice invites, Cara accepts that invite
    cara.env.IsInGroup = function() return false end
    local ok = CL.AskHop()
    Server:Advance(5)
    check(ok and chatHas(alice, "asks for a hop"), "a hop request reaches members on another layer")
    alice.env.C_PartyInfo = { InviteUnit = function(n) alice.invited = n end }
    AL.Help("Cara Cole")
    Server:Advance(5)
    check(alice.invited == "Cara Cole", "Alice invites Cara")
    local accepted = false
    cara.env.AcceptGroup = function() accepted = true end
    fire(cara, "PARTY_INVITE_REQUEST", "Eve Ember")
    check(not accepted, "an invite from someone else isn't accepted")
    fire(cara, "PARTY_INVITE_REQUEST", "Alice Ash")
    check(accepted, "the helper's invite is accepted by itself")
    undoA(); undoC()

    -- where: members by zone
    local where = alice.env.RUIN_API:GetWhere()
    check(where.total >= 2 and where.zones[1] and where.zones[1].count >= 1, "Where counts online members by zone")
    -- marks: org guild players get a mark
    local WH = alice.mns.RUIN_Finder.Where
    alice.env.UnitExists = function(u) return u == "target" end
    alice.env.UnitIsPlayer = function() return true end
    alice.targetGuild = "Briar Fang"
    check(WH.TagOf("target") == "Briar", "a Briar Fang player shows the Briar tag")
    alice.targetGuild = "Strangers"
    check(WH.TagOf("target") == nil, "players outside the org get no mark")
    alice.targetGuild = nil
    alice.env.UnitExists = function(u) return u == "target" and alice.target ~= nil end
    T.openAllSubTabs(alice, "Finder")
    errorsSoFar("finder layers and where")
end

---------------------------------------------------------------------------
print("Muster 0.4.1: Most Wanted, War Room, loot notes")
do
    -- Eve is killed by an enemy player; the org learns who
    eve.env.C_DeathRecap = { HasRecapEvents = function() return true end,
        GetRecapEvents = function() return { { sourceName = "Gankster", sourceFlags = 0x548, overkill = 12 }, { sourceName = "Gankster", sourceFlags = 0x548, overkill = -1 } } end }
    fire(eve, "PLAYER_DEAD")
    Server:Advance(5)
    local AW = alice.mns.RUIN_Muster.Wanted
    local mw = AW.MostWanted(false)
    check(mw[1] and mw[1].name == "Gankster" and mw[1].week == 1, "the killer goes on the Most Wanted list")
    fire(eve, "PLAYER_DEAD")
    Server:Advance(5)
    check(AW.MostWanted(false)[1].week == 1, "the same death reported twice counts once")
    eve.env.C_DeathRecap = { HasRecapEvents = function() return true end,
        GetRecapEvents = function() return { { sourceName = "Hogger", sourceFlags = 0xa48, overkill = 5 } } end }
    Server:Advance(30)
    fire(eve, "PLAYER_DEAD")
    Server:Advance(5)
    check(#AW.MostWanted(false) == 1, "deaths to creatures don't count")
    -- Alice gets revenge
    fire(alice, "CHAT_MSG_COMBAT_HONOR_GAIN", "Gankster dies, honorable kill Rank: Scout (Estimated Honor Points: 5)")
    Server:Advance(5)
    local sl = cara.mns.RUIN_Muster.Wanted.Slayers()
    check(sl[1] and sl[1].name == "Alice Ash" and sl[1].week == 1, "honorable kills count on the Slayers list")
    check(cara.mns.RUIN_Muster.Wanted.Row("Gankster") ~= nil, "a killer of RUIN members is looked up when they die (revenge)")

    -- War Room
    local mu = alice.env.RUIN_API:GetModule("Muster")
    local at = os.date("%Y-%m-%d %H:%M", os.time() + 5 * 3600)
    local ev = mu:Create("Crossroads raid", at, { kind = "PvP" })
    Server:Advance(3)
    cara.env.RUIN_API:GetModule("Muster"):SignUp(ev.id, "T")
    eve.env.RUIN_API:GetModule("Muster"):SignUp(ev.id, "D")
    mu:SignUp(ev.id, "H")
    Server:Advance(3)
    local WR = alice.mns.RUIN_Muster.WarRoom
    local aev = alice.env.RUIN_MusterDB.events[ev.id]
    WR.AutoSquads(aev, 2)
    WR.SetObjective(aev, 1, "Hold the bridge")
    Server:Advance(3)
    local eev = eve.env.RUIN_MusterDB.events[ev.id]
    check(eev.squads and #eev.squads == 2, "squads travel with the event")
    local orders = eve.mns.RUIN_Muster.WarRoom.MyOrders(eev)
    check(orders and orders.squad ~= nil, "everyone signed up sees their squad")
    local eWR = eve.mns.RUIN_Muster.WarRoom
    check(not eWR.AddSquad(eev, "Mine"), "a member can't change the plan")
    WR.SetReport(aev, "We held the bridge for 20 minutes.")
    Server:Advance(3)
    check(cara.env.RUIN_MusterDB.events[ev.id].aar and cara.env.RUIN_MusterDB.events[ev.id].aar.text:find("bridge"), "the after-action report reaches the org")

    -- Loot notes
    local L = alice.mns.RUIN_Muster.Loot
    local okL = L.Award(aev, "|cffa335ee|Hitem:17076::|h[Bonereaver's Edge]|h|r", "Cara Cole", "Main spec", 30, "first drop")
    Server:Advance(3)
    local cn = cara.mns.RUIN_Muster.Loot.Notes(ev.id)
    check(okL and #cn == 1 and cn[1].to == "Cara Cole" and cn[1].pts == 30, "loot notes reach the org")
    local tot = cara.mns.RUIN_Muster.Loot.Totals()
    check(tot[1] and tot[1].pts == 30 and tot[1].count == 1, "and add up per player this season")
    check(not eve.mns.RUIN_Muster.Loot.Award(eev, "x", "Eve Ember"), "members can't note awards")
    eve.mns.RUIN_Muster.Loot.Ask(eev, "[Bonereaver's Edge]", "for my main")
    Server:Advance(3)
    check(#L.Asks(ev.id) == 1, "a member's wish reaches the leaders")
    fire(alice, "CHAT_MSG_LOOT", "Cara Cole receives loot: |cffa335ee|Hitem:17076::|h[Bonereaver's Edge]|h|r.")
    check(L.Recent()[1] and L.Recent()[1].name == "Cara Cole", "drops are caught from the loot lines")
    alice.env.SlashCmdList.RUINMUSTER("timer songflower")
    T.openAllSubTabs(alice, "Muster")
    T.openAllSubTabs(eve, "Muster")
    errorsSoFar("muster 0.4.1")
end

---------------------------------------------------------------------------
print("Exchange 0.4.1: treasury book and crafting history")
do
    local CT, ET = cara.mns.RUIN_Exchange.Treasury, eve.mns.RUIN_Exchange.Treasury
    check(CT.IsKeeper(), "the guild master keeps the book")
    check(ET.IsKeeper(), "and so does the Treasurer office holder")
    -- a trade: Eve gives Cara 50 gold
    cara.env.UnitName = (function(old) return function(u) if u == "NPC" then return "Eve Ember" end return old(u) end end)(cara.env.UnitName)
    cara.env.GetTargetTradeMoney = function() return 500000 end
    cara.env.GetPlayerTradeMoney = function() return 0 end
    fire(cara, "TRADE_SHOW")
    fire(cara, "TRADE_MONEY_CHANGED")
    cara.env.ERR_TRADE_COMPLETE = "Trade complete."
    fire(cara, "UI_INFO_MESSAGE", 0, "Trade complete.")
    Server:Advance(3)
    local ce = CT.Entries()
    check(ce[1] and ce[1].c == 500000 and ce[1].who == "Eve Ember" and ce[1].via == "trade", "gold traded to the treasurer is written down")
    check(#ET.Entries() == 1, "and the guild sees the book")
    -- mail
    cara.env.GetInboxHeaderInfo = function(i)
        if i == 1 then return nil, nil, "Eve Ember", "Guild dues", 100000 end
        return nil, nil, "Auction House", "Auction successful: Linen Cloth", 999999
    end
    cara.env.TakeInboxMoney = function() end
    cara.mns.RUIN_Exchange.Treasury.Init(cara.env.RUIN_API:GetModule("Exchange"), cara.env.RUIN_ExchangeDB)
    cara.env.TakeInboxMoney(1)
    cara.env.TakeInboxMoney(2)
    check(#CT.Entries() == 2 and CT.Entries()[1].via == "mail", "mailed gold is written down, auction house mail isn't")
    local tt = CT.Totals()
    check(tt.weekIn == 600000 and tt.givers[1].name == "Eve Ember", "weekly totals and givers")
    check(not alice.mns.RUIN_Exchange.Treasury.Entries()[1], "other guilds don't get the book")

    -- crafting history: Cara crafted for Eve, Eve confirms
    local CH, EH = cara.mns.RUIN_Exchange.History, eve.mns.RUIN_Exchange.History
    check(CH.Log("Robe of Power", "Eve Ember", "Tailoring"), "Cara logs a craft for Eve")
    Server:Advance(3)
    local p = EH.Pending()
    check(p[1] and p[1].cr == "Cara Cole" and not p[1].mine, "Eve is asked to confirm")
    EH.Confirm(p[1].id, true)
    Server:Advance(3)
    local done = alice.mns.RUIN_Exchange.History.Done()
    check(done[1] and done[1].item == "Robe of Power" and done[1].cu == "Eve Ember", "confirmed crafts reach the whole org")
    check(#CH.Pending() == 0, "and leave the crafter's waiting list")
    local top = alice.mns.RUIN_Exchange.History.Crafters()
    check(top[1] and top[1].name == "Cara Cole" and top[1].month == 1, "crafters ranked by confirmed crafts")
    -- a forged confirmation from someone else is ignored
    alice.env.RUIN_API:GetModule("Exchange"):Send("CCONF", { id = "fake1", item = "Fake", cr = "Alice Ash", cu = "Eve Ember", t = 1 }, "ORG")
    Server:Advance(3)
    check(#cara.mns.RUIN_Exchange.History.Done() == 1, "only the customer can confirm a craft")
    T.openAllSubTabs(cara, "Exchange")
    errorsSoFar("exchange 0.4.1")
end
