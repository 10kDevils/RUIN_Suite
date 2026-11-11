-- WoW Forever launch data (2026-11-05) in Codex and Pathfinder.
-- Runs after the other run_features_*.lua files and shares T.
local alice, cara, check, errorsSoFar = T.alice, T.cara, T.check, T.errorsSoFar

print("Codex: WoW Forever's new dungeons")
do
    local CN = cara.mns.RUIN_Codex
    local cx = cara.env.RUIN_API:GetModule("Codex")
    local by, ids = {}, {}
    local dup = false
    for _, d in ipairs(CN.Dungeons) do
        if ids[d.id] then dup = true end
        ids[d.id] = true
        by[d.id] = d
    end
    check(not dup, "every dungeon has its own id")
    local want = {
        hot = { "Hall of Thanes", "13-18", 4 }, rol = { "Ruins of Lordaeron", "15-20", 7 },
        exc = { "Excavation Site: Wetlands", "24-31", 4 }, dal = { "City of Dalaran", "28-33", 8 },
        drowned = { "The Drowned City", "35-40", 3 }, kroldok = { "Krol'dok Stronghold", "40-45", 0 },
        alcaz = { "Alcaz Prison", "48-53", 0 }, blackmaw = { "Blackmaw Hold", "55-60", 0 }, shaper = { "Shaper's Terrace", "58-60", 0 },
    }
    local wrong = {}
    for id, w in pairs(want) do
        local d = by[id]
        if not (d and d.name == w[1] and d.levels == w[2] and #d.bosses == w[3] and d.forever == "2026-11-05" and d.where and d.where ~= "") then
            wrong[#wrong + 1] = id
        end
    end
    check(#wrong == 0, "all nine WoW Forever dungeons: name, levels, entrance and bosses from the launch data (" .. table.concat(wrong, ", ") .. ")")
    check(by.hot.bosses[1][1] == "Faldrim Anvilmar" and by.hot.bosses[2][1] == "Magmatus" and by.hot.bosses[4][1] == "Durgen Dirgehammer",
        "Hall of Thanes bosses in kill order")
    check(by.hot.bosses[2][2]:find("Combust", 1, true) and by.exc.bosses[1][2]:find("^Level 28%."), "boss tips come from the mechanics (and levels where known)")
    check(by.dal.attunement and by.dal.attunement.alliance:find("Emissary Jacques", 1, true) and by.dal.attunement.horde:find("Tarren Mill", 1, true),
        "City of Dalaran's attunement for both factions")
    check(by.rol.set and by.rol.set.name == "Rotmender's Raiment" and #by.rol.set.bonuses == 3 and by.dal.set.name == "Violet Sorcerer's Vestments",
        "set bonuses for Ruins of Lordaeron and City of Dalaran")
    check(#by.hot.quests == 5 and by.exc.questXP:find("39,300", 1, true), "dungeon quests and quest XP")
    -- a classic dungeon is unchanged
    check(by.dm and by.dm.levels == "17-26" and not by.dm.forever, "classic dungeons keep their sample data")

    -- loot by name, until the game knows the item
    local loot = CN.Loot.For(by.hot)
    check(loot and #loot.bosses == 4 and loot.bosses[1].items[1].name == "Ephemeral Choker" and loot.bosses[1].items[1].info:find("^Neck")
        and loot.bosses[1].items[1].id == nil, "Hall of Thanes loot is listed by name and slot")
    local n = 0
    for _, id in ipairs({ "hot", "rol", "exc", "dal" }) do
        for _, b in ipairs(CN.Loot.For(by[id]).bosses) do n = n + #b.items end
    end
    check(n == 70, "every boss drop in the launch data: 70 across the four documented dungeons (" .. n .. ")")
    local bad = 0
    for _, e in ipairs(CN.Loot.errors) do if not e:find("^Rethilgore") and not e:find("Shadowfang") then bad = bad + 1 end end
    check(bad == 0, "the launch loot file loads with no skipped entries")
    check(cx:DungeonShort("Excavation Site: Wetlands") == "EXC" and cx:DungeonWhere("City of Dalaran"):find("Alterac", 1, true),
        "Codex names and places the new dungeons for the party signal")

    -- the Journal page
    local function text(lines) local t = {}; for _, l in ipairs(lines) do t[#t + 1] = l[1] end; return table.concat(t, "\n") end
    local hot = text(cx.JournalLines(by.hot, false))
    check(hot:find("WoW Forever launch data", 1, true) and not hot:find("WoW Classic sample", 1, true), "the Journal says the data is Forever's, not the Classic sample")
    check(hot:find("Ephemeral Choker", 1, true) and hot:find("(Neck", 1, true) and hot:find("Quests", 1, true) and hot:find("The Restless Dead", 1, true),
        "Hall of Thanes: items with their slots, and the dungeon quests")
    local dal = text(cx.JournalLines(by.dal, false))
    check(dal:find("Attunement", 1, true) and dal:find("Set: Violet Sorcerer's Vestments (5 pieces)", 1, true) and dal:find("(4) Chance on damaging spell", 1, true),
        "City of Dalaran: attunement and the set's bonuses")
    local kd = text(cx.JournalLines(by.kroldok, false))
    check(kd:find("No boss list published yet.", 1, true) and kd:find("Twilight's Hammer", 1, true) and kd:find("story only", 1, true),
        "Krol'dok Stronghold says no boss list is published yet, with its notes")

    -- once a RUIN member loots a listed item, its line shows the real item
    local realInfo = cara.env.GetItemInfo
    cara.env.GetItemInfo = function(id)
        if id == 990001 then return "Ephemeral Choker", "|cff1eff00|Hitem:990001::|h[Ephemeral Choker]|h|r", 2, nil, 13 end
        if id == 990002 then return "Something Else", "|cff1eff00|Hitem:990002::|h[Something Else]|h|r", 2, nil, 13 end
        return realInfo(id)
    end
    cara.env.RUIN_CodexDB.drops["Hall of Thanes"] = { [990001] = { n = 2 }, [990002] = { n = 1 } }
    local lines = cx.JournalLines(by.hot, false)
    local choker, also
    for i, l in ipairs(lines) do
        if l[1]:find("Ephemeral Choker", 1, true) then choker = l end
        if l[1]:find("Also looted by RUIN members", 1, true) then also = i end
    end
    check(choker and choker.link and choker.link:find("990001", 1, true) and choker[1]:find("looted 2x by RUIN", 1, true),
        "a listed name RUIN looted shows the real item, with how often")
    local after = text({ unpack(lines, also) })
    check(after:find("Something Else", 1, true) and not after:find("Ephemeral Choker", 1, true), "and isn't listed again as an extra drop")
    cara.env.GetItemInfo = realInfo
    cara.env.RUIN_CodexDB.drops["Hall of Thanes"] = nil
    T.openAllSubTabs(cara, "Codex")
    errorsSoFar("forever dungeons")
end

print("Pathfinder: launch updates")
do
    local P = alice.mns.RUIN_Pathfinder
    local function routeOf(id) for _, r in ipairs(P.Routes) do if r.id == id then return r end end end
    local function hasQid(r, qid, act) for _, s in ipairs(r.steps) do if s.qid == qid and s.act == act then return true end end return false end
    local function noteHas(r, text) for _, s in ipairs(r.steps) do if s.act == "note" and s.text:find(text, 1, true) then return true end end return false end
    local el, ze = routeOf("elwynn_1_10"), routeOf("zephras_1_12")
    -- The Forever quest database has no quests 7961, 7962 or 92454: they're out of the routes
    check(not hasQid(el, 7962, "accept") and not hasQid(el, 7961, "accept"), "Elwynn: no quests the Forever database doesn't have")
    check(not hasQid(ze, 92454, "accept") and hasQid(ze, 92460, "accept"), "Zephras Isle opens with Coming of Age (92460)")
    check(hasQid(ze, 92460, "accept") and hasQid(ze, 92460, "turnin"), "Zephras Isle: Coming of Age")
    check(noteHas(routeOf("teldrassil_1_12"), "The Goddess Provides") and noteHas(el, "A Scribbled Letter"), "class and race starter quests as notes")
    check(noteHas(routeOf("wetlands_20_30"), "City of Dalaran") and noteHas(routeOf("duskwood_20_28"), "Emissary Jacques")
        and noteHas(routeOf("ashenvale_18_28"), "City of Dalaran"), "a City of Dalaran pointer at 28+ in the routes that reach it")
    check(noteHas(routeOf("wetlands_20_30"), "levels 24-31") and noteHas(routeOf("wetlands_20_30"), "39,300 XP"), "Excavation Site's levels and quest XP")
    check(noteHas(routeOf("hall_of_thanes"), "Magmatus") and noteHas(routeOf("westfall_10_15"), "Ruins of Lordaeron"), "Hall of Thanes boss order; Ruins of Lordaeron as a detour")
    check(P.ZoneQuests and P.ZoneQuests["Elwynn Forest"][1] == 74 and P.ZoneQuests["Zephras Isle"][1] == 92 and el.zone == "Elwynn Forest",
        "zone quest counts from ForeverDB, and routes know their zone")
    check(not routeOf("hall_of_thanes").zone, "the dungeon route has no zone count")
    -- the Routes page tooltip
    T.openAllSubTabs(alice, "Pathfinder")
    errorsSoFar("pathfinder launch updates")
end
