-- Exchange 0.5.1: the recipe list shows one crafter per recipe (the online
-- member with the lowest skill), a list of the others on the name, an
-- "Offline crafters" switch, skill shared with the recipes, and a whisper to
-- the full name. Runs after the other run_features_*.lua files and shares T.
local alice, cara, eve, check, chatHas, errorsSoFar = T.alice, T.cara, T.eve, T.check, T.chatHas, T.errorsSoFar
local Server = Server

print("Exchange: recipes by crafter")
do
    local X = alice.env.RUIN_API:GetModule("Exchange")
    local db = alice.env.RUIN_ExchangeDB
    local saved = db.crafters
    local now = alice.env.GetServerTime()
    local ME = alice.guid
    local KELL, OLD = "Player-1-00000091", "Player-1-00000092"
    db.crafters = {
        [cara.guid] = { name = "Cara Cole", guild = "Briar Fang", t = now, profs = { Tailoring = { "Linen Bandage", "Linen Cloak" } }, skill = { Tailoring = 120 } },
        [eve.guid] = { name = "Eve Ember", guild = "Briar Fang", t = now, profs = { Tailoring = { "Linen Bandage" } }, skill = { Tailoring = 80 } },
        [KELL] = { name = "Kell Dawn", guild = "Ash Vale", t = now, profs = { Tailoring = { "Linen Bandage", "Heavy Linen Bandage" } }, skill = { Tailoring = 40 } },
        [OLD] = { name = "Olga Oak", guild = "Ash Vale", t = now, profs = { Tailoring = { "Linen Cloak" } } },   -- an older RUIN: no skill
        [ME] = { name = "Alice Ash", guild = "Briar Fang", t = now, profs = { Tailoring = { "Linen Bandage", "Silk Headband" } }, skill = { Tailoring = 50 } },
    }
    -- online: Alice, Cara, Eve and Olga; Kell is offline
    local realOnline = alice.env.RUIN_API.GetOnlineMembers
    alice.env.RUIN_API.GetOnlineMembers = function()
        return { { guid = ME, self = true }, { guid = cara.guid }, { guid = eve.guid }, { guid = OLD } }
    end
    local function rows(q)
        local by = {}
        for _, r in ipairs(X.SearchRows(q or "", "Tailoring")) do if r.recipe then by[r.recipe] = r end end
        return by
    end
    local function names(r) local t = {}; for _, c in ipairs(r.crafters) do t[#t + 1] = c.name end; return table.concat(t, ",") end

    db.showOffline = false
    local by = rows()
    local band = by["Linen Bandage"]
    check(band and band.who.name == "Eve Ember", "a recipe shows the online crafter with the lowest skill (Eve, 80, not Cara, 120)")
    check(names(band) == "Eve Ember,Cara Cole,Alice Ash", "the others follow, lowest skill first, you last; offline Kell is left out (" .. names(band) .. ")")
    check(not by["Heavy Linen Bandage"], "a recipe only offline members know is hidden")
    local cloak = by["Linen Cloak"]
    check(cloak and cloak.who.name == "Cara Cole" and names(cloak) == "Cara Cole,Olga Oak", "a crafter whose skill is unknown (older RUIN) sorts after known skills")
    local head = by["Silk Headband"]
    check(head and head.who.self, "a recipe only you know shows you")
    local n = 0
    for _, r in ipairs(X.SearchRows("", "Tailoring")) do if r.recipe then n = n + 1 end end
    check(n == 3, "one row per recipe, not one per crafter (" .. n .. ")")

    db.showOffline = true
    by = rows()
    check(names(by["Linen Bandage"]) == "Eve Ember,Cara Cole,Alice Ash,Kell Dawn" and by["Linen Bandage"].who.name == "Eve Ember",
        "Offline crafters: offline members join the list after the online ones; the pick is still online")
    local heavy = by["Heavy Linen Bandage"]
    check(heavy and heavy.who.name == "Kell Dawn" and not heavy.who.online, "and recipes only offline members know show up, marked offline")

    -- the page: the name button, the list on it, picking someone else
    alice.env.RUIN_API:OpenTab("Exchange")
    T.openAllSubTabs(alice, "Exchange")
    local ui = X.UI
    local row
    for _, r in ipairs(ui.list.rows) do if r.pick and r.pick.rec and r.pick.rec.recipe == "Linen Bandage" then row = r end end
    check(row and row.pick:GetText():find("Eve Ember", 1, true) and row.pick:GetText():find("80", 1, true) and row.pick:GetText():find("+3", 1, true),
        "the row shows Eve with her skill, and +3 others (" .. tostring(row and row.pick:GetText()) .. ")")
    X.OpenCrafterList(row.pick, row.pick.rec)
    local list = ui.crafterList
    check(list:IsShown() and list.items[1]:GetText():find("Eve Ember", 1, true) and list.items[4]:GetText():find("offline", 1, true),
        "the name opens everyone who can craft it, offline ones marked")
    list.items[2]._scripts.OnClick(list.items[2])
    check(not list:IsShown() and rows()["Linen Bandage"].who.name == "Cara Cole", "picking Cara from the list makes her the recipe's crafter")
    local whispered
    local realWhisper = X.Whisper
    for _, r in ipairs(ui.list.rows) do
        if r.pick and r.pick.rec and r.pick.rec.recipe == "Linen Bandage" then row = r end
    end
    -- whispering opens chat to the full name, with no "/cw" for the chat box to cut short
    local box = { attrs = {}, header = 0 }
    function box:SetAttribute(k, v) self.attrs[k] = v end
    function box:UpdateHeader() self.header = self.header + 1 end
    local opened
    alice.env.ChatFrameUtil = { ChooseBoxForSend = function() return box end, OpenChat = function(text) opened = text end,
                                SendTell = function() whispered = "SendTell" end }
    row.btn._scripts.OnClick(row.btn)
    check(opened == "" and box.attrs.chatType == "WHISPER" and box.attrs.tellTarget == "Cara Cole" and box.header == 1 and whispered == nil,
        "Whisper opens a whisper to Cara Cole, first and last name")
    local heavyRow
    for _, r in ipairs(ui.list.rows) do if r.pick and r.pick.rec and r.pick.rec.recipe == "Heavy Linen Bandage" then heavyRow = r end end
    local mineRow
    for _, r in ipairs(ui.list.rows) do if r.pick and r.pick.rec and r.pick.rec.recipe == "Silk Headband" then mineRow = r end end
    check(heavyRow and heavyRow.pick:GetText():find("offline", 1, true), "an offline crafter's row says so")
    alice.env.ChatFrameUtil = nil
    db.showOffline = false
    ui.picked = nil

    -- skill travels with the recipes
    local XE = eve.env.RUIN_API:GetModule("Exchange")
    eve.env.GetProfessions = function() return 1 end
    eve.env.GetProfessionInfo = function() return "Alchemy", 0, 133, 150 end
    eve.env.RUIN_ExchangeDB.crafters[eve.guid] = { name = "Eve Ember", guild = "Briar Fang", t = now, profs = { Alchemy = { "Minor Healing Potion" } } }
    db.crafters = saved
    db.crafters[eve.guid] = nil
    XE.ShareMine(true)
    Server:Advance(60)
    local got = db.crafters[eve.guid]
    check(got and got.skill and got.skill.Alchemy == 133, "a crafter's skill now travels with their recipes (" .. tostring(got and got.skill and got.skill.Alchemy) .. ")")
    alice.env.RUIN_API.GetOnlineMembers = realOnline
    errorsSoFar("exchange recipes")
end

print("Settings: the key phrase stays hidden")
do
    local Org = alice.ns.Org
    check(Org:ChooseNewKey("ruin rises at dawn") and Org:Get().ph == "ruin rises at dawn", "the admin sets a key phrase")
    Server:Advance(10)
    check(not chatHas(alice, "ruin rises at dawn"), "setting it doesn't print the phrase in chat")
    alice.env.RUIN_API:OpenTab("Settings")
    alice.ns.UI:SelectSettingsTab(1)
    alice.ns.UI:Refresh()
    local S = alice.ns.UI.settings
    local function statusText() return S.status:GetText() or "" end
    local function revealBtn() return S.reveal end
    local st = statusText()
    check(st and st:find("key phrase:", 1, true) and st:find("hidden", 1, true) and not st:find("ruin rises at dawn", 1, true),
        "Settings > Org says the key phrase is hidden, without showing it")
    local b = revealBtn()
    check(b and b:GetText() == "Show key phrase", "with a Show key phrase button")
    b._scripts.OnClick(b)
    st = statusText()
    check(st:find("ruin rises at dawn", 1, true) and b:GetText() == "Hide key phrase", "the button shows it, and becomes Hide key phrase")
    Server:Advance(21)
    alice.ns.UI:Refresh()
    check(not statusText():find("ruin rises at dawn", 1, true) and b:GetText() == "Show key phrase", "it hides again by itself after 20 seconds")
    b._scripts.OnClick(b)
    b._scripts.OnClick(b)
    check(not statusText():find("ruin rises at dawn", 1, true), "Hide key phrase hides it at once")
    errorsSoFar("hidden key phrase")
end
