-- Codex 0.5.3: the Dungeon Journal. Items open their full tooltip on click;
-- each listed boss drop has a small tracker (kills, how often it dropped);
-- General lists the greens and blues from the dungeon's mobs, with a drop
-- chance per mob looted. Runs after the other run_features_*.lua files.
local alice, cara, eve, check, errorsSoFar = T.alice, T.cara, T.eve, T.check, T.errorsSoFar
local Server = Server
local INST = "Hall of Thanes"

print("Codex: Dungeon Journal tracking")
do
    local CA, CC = alice.env.RUIN_API:GetModule("Codex"), cara.env.RUIN_API:GetModule("Codex")
    local dbA, dbC, dbE = alice.env.RUIN_CodexDB, cara.env.RUIN_CodexDB, eve.env.RUIN_CodexDB
    local realInInstance = {}
    for _, c in ipairs({ alice, cara, eve }) do
        c.instance = INST
        realInInstance[c] = c.env.IsInInstance
        c.env.IsInInstance = function() return c.instance ~= nil, c.instance and "party" or "none" end
    end
    local function hot() return cara.env.RUIN_API:GetModule("Codex"):FindDungeon(INST) end
    local function text(lines) local t = {}; for _, l in ipairs(lines) do t[#t + 1] = l[1] end; return table.concat(t, "\n") end

    -- boss kills
    check(CC.MatchBoss(INST, "Faldrim") == "Faldrim Anvilmar" and CC.MatchBoss(INST, "Kobold Tunneler") == nil,
        "encounter names match the journal's bosses")
    Server.fire(alice, "ENCOUNTER_END", 3001, "Faldrim Anvilmar", 1, 5, 1)
    Server.fire(alice, "ENCOUNTER_END", 3001, "Faldrim Anvilmar", 1, 5, 1)
    Server.fire(alice, "ENCOUNTER_END", 3002, "Magmatus", 1, 5, 0)
    Server:Advance(3)
    Server:Advance(120)
    check(dbA.kills[INST] and dbA.kills[INST]["Faldrim Anvilmar"] == 1 and dbC.kills[INST] and dbC.kills[INST]["Faldrim Anvilmar"] == 1,
        "a boss kill counts once and reaches the org")
    check(not dbC.kills[INST]["Magmatus"], "a wipe isn't a kill")
    -- WoW Forever: the combat log, when a dungeon has no encounter events
    alice.env.CombatLogGetCurrentEventInfo = function() return 0, "UNIT_DIED", false, "", "", 0, 0, "Creature-0-1-2-3-4001-000A", "Magmatus" end
    Server.fire(alice, "COMBAT_LOG_EVENT_UNFILTERED")
    Server:Advance(60)
    check(dbC.kills[INST]["Magmatus"] == 1, "a boss dying in the combat log counts as a kill")
    for _ = 1, 3 do
        Server:Advance(301)
        Server.fire(alice, "ENCOUNTER_END", 3001, "Faldrim Anvilmar", 1, 5, 1)
    end
    Server:Advance(60)
    check(dbC.kills[INST]["Faldrim Anvilmar"] == 4, "four Faldrim kills (" .. tostring(dbC.kills[INST]["Faldrim Anvilmar"]) .. ")")

    -- a listed drop's tracker: "dropped 1 of 4 kills · 25%"
    local realInfo = cara.env.GetItemInfo
    local known = {
        [990001] = { "Ephemeral Choker", "|cff1eff00|Hitem:990001::|h[Ephemeral Choker]|h|r", 2 },
        [990010] = { "Thane's Belt", "|cff1eff00|Hitem:990010::|h[Thane's Belt]|h|r", 2 },
        [990011] = { "Runed Ring", "|cff0070dd|Hitem:990011::|h[Runed Ring]|h|r", 3 },
        [990012] = { "Linen Cloth", "|cffffffff|Hitem:990012::|h[Linen Cloth]|h|r", 1 },
    }
    for _, c in ipairs({ alice, cara, eve }) do
        local real = c.env.GetItemInfo
        c.env.GetItemInfo = function(id)
            local k = tonumber(id) or tonumber(tostring(id):match("item:(%d+)"))
            if not k then for kid, v in pairs(known) do if v[1] == id then k = kid end end end
            local v = k and known[k]
            if v then return v[1], v[2], v[3], nil, 13 end
            return real(id)
        end
    end
    dbC.drops[INST] = { [990001] = { n = 1 } }
    local lines = CC.JournalLines(hot(), false)
    local t = text(lines)
    check(t:find("Faldrim Anvilmar|r  " .. "|cff", 1, true) and t:find("killed 4x by RUIN", 1, true), "the boss says how often RUIN killed it")
    local choker
    for _, l in ipairs(lines) do if l[1]:find("Ephemeral Choker", 1, true) then choker = l end end
    check(choker and choker[1]:find("1/4 kills", 1, true) and choker[1]:find("25%", 1, true), "a listed drop: 1/4 kills, 25% (" .. tostring(choker and choker[1]) .. ")")
    check(choker and choker[1]:find("(Neck", 1, true), "the list from the launch data stays the main source (name and slot)")
    local other
    for _, l in ipairs(lines) do if l[1]:find("Aetherwisp Bracers", 1, true) then other = l end end
    check(other and other[1]:find("0/4 kills", 1, true) and other.name == "Aetherwisp Bracers" and not other.link,
        "a listed drop nobody has seen yet: 0 of 4, and no link to show")

    -- mob loot windows
    local loot = {}
    alice.env.GetNumLootItems = function() return #loot end
    alice.env.GetLootSlotLink = function(s) return loot[s] and loot[s].link end
    alice.env.GetLootSourceInfo = function(s) return loot[s] and loot[s].guid, 1 end
    alice.env.UnitGUID = function(u) if u == "target" then return alice.targetGUID end return alice.guid end
    alice.env.UnitName = (function(old) return function(u) if u == "target" then return alice.targetName end return old(u) end end)(alice.env.UnitName)
    local function open(guid, links, target)
        loot = {}
        for _, l in ipairs(links) do loot[#loot + 1] = { link = l, guid = guid } end
        if #links == 0 then loot[1] = { guid = guid } end   -- money only
        alice.targetGUID, alice.targetName = guid, target
        Server.fire(alice, "LOOT_OPENED")
    end
    open("Creature-0-1-2-3-500-0001", { known[990010][2], known[990012][2] })
    open("Creature-0-1-2-3-500-0001", { known[990010][2] })            -- the same corpse again
    open("Creature-0-1-2-3-500-0002", {})
    open("Creature-0-1-2-3-500-0003", { known[990011][2] })
    open("Creature-0-1-2-3-500-0004", { known[990010][2] })
    open("Creature-0-1-2-3-4001-0009", { known[990001][2] }, "Faldrim Anvilmar")  -- a boss corpse
    open("GameObject-0-1-2-3-77-0001", { known[990011][2] })           -- a chest
    local mA = dbA.mobs[INST]
    check(mA and mA.n == 4, "four mob corpses looted: a corpse counts once, bosses and chests don't count (" .. tostring(mA and mA.n) .. ")")
    check(mA.items[990010] == 2 and mA.items[990011] == 1 and not mA.items[990012] and not mA.items[990001],
        "greens and blues in the loot windows count; whites and the boss's loot don't")
    check(not (dbC.mobs[INST] and dbC.mobs[INST].n > 0), "sent in a batch, not one message per corpse")
    Server:Advance(90)
    check(dbC.mobs[INST] and dbC.mobs[INST].n == 4 and dbC.mobs[INST].items[990010] == 2, "the batch reaches the org")

    t = text(CC.JournalLines(hot(), false))
    check(t:find("General", 1, true) and t:find("4 mobs looted by RUIN", 1, true), "General says how many mobs RUIN looted")
    local belt, ring
    for _, l in ipairs(CC.JournalLines(hot(), false)) do
        if l[1]:find("Thane's Belt", 1, true) then belt = l end
        if l[1]:find("Runed Ring", 1, true) then ring = l end
    end
    check(belt and belt[1]:find("x2", 1, true) and belt[1]:find("about 50% per mob", 1, true) and belt.link, "Thane's Belt: x2, about 50% per mob (" .. tostring(belt and belt[1]) .. ")")
    check(ring and ring[1]:find("25%", 1, true), "Runed Ring: about 25% per mob")
    local gpos, bpos = t:find("General", 1, true), t:find("Thane's Belt", 1, true)
    local apos = t:find("Also looted by RUIN members", 1, true)
    check(gpos and bpos and apos and gpos < bpos and bpos < apos, "General comes before the other looted drops")
    dbC.drops[INST][990010] = { n = 2 }
    t = text(CC.JournalLines(hot(), false))
    local _, count = t:gsub("Thane's Belt", "")
    check(count == 1, "an item in General isn't listed again under Also looted")

    -- catch-up for a member who was offline
    dbE.kills[INST], dbE.mobs[INST] = nil, nil
    eve.env.RUIN_API:GetModule("Codex"):Send("DROPQ", { n = 0 }, "ORG")
    Server:Advance(90)
    check(dbE.kills[INST] and dbE.kills[INST]["Faldrim Anvilmar"] == 4 and dbE.mobs[INST] and dbE.mobs[INST].n == 4
        and dbE.mobs[INST].items[990010] == 2, "a member who was offline gets the kill and mob counts")
    -- a bad message is ignored
    CA:Send("MOBS", { i = INST, n = 99999, l = { { 990010, 5 } } }, "ORG")
    CA:Send("TALLY", { i = INST, k = { { "Faldrim Anvilmar", "lots" } } }, "ORG")
    Server:Advance(60)
    check(dbC.mobs[INST].n == 4 and dbC.kills[INST]["Faldrim Anvilmar"] == 4, "impossible counts are ignored")

    -- the page: click an item for its full tooltip
    cara.env.RUIN_API:OpenTab("Codex")
    T.openAllSubTabs(cara, "Codex")
    local ui = CC.UI
    for i, d in ipairs(cara.mns.RUIN_Codex.Dungeons) do if d.name == INST then ui.selected = i end end
    ui.jmode = "Dungeons"
    T.openAllSubTabs(cara, "Codex")
    local ref
    cara.env.SetItemRef = function(link, txt, button) ref = { link, txt, button } end
    cara.env.IsModifiedClick = function() return false end
    local beltRow, nameRow
    for _, r in ipairs(ui.detail.rows) do
        if r._shown and r.link and r.text:GetText():find("Thane's Belt", 1, true) then beltRow = r end
        if r._shown and r.itemName == "Aetherwisp Bracers" then nameRow = r end
    end
    check(beltRow ~= nil, "the General item has a row on the page")
    if beltRow then beltRow._scripts.OnMouseUp(beltRow, "LeftButton") end
    check(ref and ref[1] == "item:990010::" and ref[2]:find("[Thane's Belt]", 1, true), "clicking an item opens its full tooltip (" .. tostring(ref and ref[1]) .. ")")
    local linked
    cara.env.IsModifiedClick = function() return true end
    cara.env.HandleModifiedItemClick = function(l) linked = l; return true end
    ref = nil
    beltRow._scripts.OnMouseUp(beltRow, "LeftButton")
    check(linked and linked:find("Thane's Belt", 1, true) and not ref, "shift-click links it in chat")
    cara.env.IsModifiedClick, cara.env.HandleModifiedItemClick, cara.env.SetItemRef = nil, nil, nil
    cara.tooltip.lines = {}
    check(nameRow ~= nil, "a listed item the game doesn't know yet has a row")
    if nameRow then nameRow._scripts.OnEnter(nameRow) end
    local tl = table.concat(cara.tooltip.lines, "\n")
    check(tl:find("Aetherwisp Bracers", 1, true) and tl:find("hasn't sent this item yet", 1, true), "hovering it says why there's no full tooltip yet")

    cara.env.GetItemInfo = realInfo
    for _, c in ipairs({ alice, cara, eve }) do c.instance = nil; c.env.IsInInstance = realInInstance[c] end
    for _, d in ipairs({ dbA, dbC, dbE }) do d.drops[INST], d.kills[INST], d.mobs[INST] = nil, nil, nil end
    errorsSoFar("codex journal")
end
