-- Codex 0.7.1: Scarlet Monastery's wings, bosses set apart, the loot filter,
-- upgrade arrows, and the dungeon list sorted by level (or A-Z) with raids by
-- size. Runs after the other run_features_*.lua files and shares T.
local alice, check, errorsSoFar = T.alice, T.check, T.errorsSoFar

print("Codex 0.7.1: wings, bosses, loot filter, upgrade arrows, sorting")
do
    local R = alice.env.RUIN_API
    local CX = R:GetModule("Codex")
    local CN = alice.mns.RUIN_Codex
    local dbC = alice.env.RUIN_CodexDB
    local ui = CX.UI

    -- the wings
    local wings = {}
    for _, d in ipairs(CN.Dungeons) do if d.group == "Scarlet Monastery" then wings[#wings + 1] = d.wing end end
    check(table.concat(wings, ",") == "Graveyard,Library,Armory,Cathedral", "Scarlet Monastery is four wings (" .. table.concat(wings, ",") .. ")")
    local whole = CX:FindDungeon("Scarlet Monastery")
    check(whole and #whole.wings == 4 and #whole.bosses >= 10, "the whole monastery still answers by name, with every wing's bosses")
    check(CX:FindDungeon("Scarlet Monastery Armory").bosses[1][1] == "Herod", "each wing has its own bosses")

    -- each wing's loot: only its own bosses
    local QL = CX.DungeonLoot
    local savedState, savedLoot = QL.state, dbC.qloot
    QL.state = "ready"
    dbC.qloot = { stamp = "test", d = { ["Scarlet Monastery"] = {
        npcs = { [1] = { "Herod", 1, 40 }, [2] = { "Arcanist Doan", 1, 37 }, [3] = { "Scarlet Defender", 1, 36 } },
        items = { { 9101, "Herod's Shoulder", 4, 40, 1, { 1 } }, { 9102, "Robe of Doan", 4, 37, 1, { 2 } },
                  { 9103, "Scarlet Boots", 4, 34, 2, { 3 } } } } } }
    local armLoot = QL.For(CX:FindDungeon("Scarlet Monastery Armory"))
    local libLoot = QL.For(CX:FindDungeon("Scarlet Monastery Library"))
    local function sec(l, name) for _, s in ipairs(l.sections) do if s.name == name then return s end end end
    check(sec(armLoot, "Herod") and not sec(armLoot, "Arcanist Doan"), "the Armory lists Herod, not the Library's Doan")
    check(sec(libLoot, "Arcanist Doan") and not sec(libLoot, "Herod"), "and the Library the other way round")
    check(#armLoot.trash == 1 and armLoot.trash[1].id == 9103, "trash from anywhere inside shows in every wing")
    QL.state, dbC.qloot = savedState, savedLoot

    -- bosses stand apart
    local lines = CX.JournalLines(CX:FindDungeon("Scarlet Monastery Graveyard"), false)
    local bossLines, tipAfter, rareTag, wingLine = 0, false, false, false
    for i, l in ipairs(lines) do
        if l.boss then
            bossLines = bossLines + 1
            if lines[i + 1] and lines[i + 1].bossTip then tipAfter = true end
            if l[1]:find("Rare", 1, true) then rareTag = true end
        end
        if l[1]:find("wings:", 1, true) then wingLine = true end
    end
    check(bossLines == 5 and tipAfter and rareTag, "each boss is its own block: a header line, its tip under it, rares tagged")
    check(wingLine, "a wing's page names the other wings")

    -- what you can use, and the filter
    local items = alice.items
    items[9201] = { name = "Test Plate Helm", link = "|cff0070dd|Hitem:9201::|h[Test Plate Helm]|h|r", loc = "INVTYPE_HEAD", classID = 4 }
    items[9202] = { name = "Test Cloth Robe", link = "|cff0070dd|Hitem:9202::|h[Test Cloth Robe]|h|r", loc = "INVTYPE_CHEST", classID = 4 }
    local realInfo = alice.env.GetItemInfo
    local SUB = { [9201] = 4, [9202] = 1, [9203] = 10 }
    items[9203] = { name = "Test Staff", link = "|cff0070dd|Hitem:9203::|h[Test Staff]|h|r", loc = "INVTYPE_2HWEAPON", classID = 2 }
    alice.env.GetItemInfo = function(id)
        local r = { realInfo(id) }
        local n = tonumber(id) or tonumber(tostring(id):match("item:(%d+)"))
        if SUB[n] then r[13] = SUB[n] end
        return unpack(r, 1, 13)
    end
    local savedClass, savedLevel = alice.env.UnitClass, alice.env.UnitLevel
    alice.env.UnitClass = function() return "Mage", "MAGE", 8 end
    check(CX.CanUse(9202) == true and CX.CanUse(9201) == false and CX.CanUse(9203) == true, "a mage can use cloth and staves, not plate")
    local k = CX.ItemKinds(9203)
    check(k.Staves and k["Two-Hand"], "a staff is a Staves and a Two-Hand")
    local k2 = CX.ItemKinds(nil, "Chest Leather, +Agi +Int")
    check(k2 and k2.Leather, "a loot list's own words tell the kind before the game sends the item")
    dbC.lootFilter = "Cloth"
    check(CX.PassesFilter(9202) and not CX.PassesFilter(9201), "the Cloth filter keeps cloth only")
    dbC.lootFilter = "Usable by me"
    check(CX.PassesFilter(9203) and not CX.PassesFilter(9201), "Usable by me follows your class")

    -- the upgrade arrow
    CX.ForgetUpgrades()
    local savedUp = CX.IsUpgrade
    CX.IsUpgrade = function(_, link) return link == "item:9202" end
    check(CX.IsUpgradeFor(9202) and not CX.IsUpgradeFor(9201), "an upgrade your class can use gets the arrow")
    dbC.lootFilter = "Upgrades for me"
    check(CX.PassesFilter(9202) and not CX.PassesFilter(9203), "and Upgrades for me shows only those")
    CX.IsUpgrade = savedUp
    CX.ForgetUpgrades()
    dbC.lootFilter = "All loot"
    alice.env.UnitClass, alice.env.UnitLevel, alice.env.GetItemInfo = savedClass, savedLevel, realInfo

    -- sorting
    R:OpenTab("Codex")
    ui.jmode = "Dungeons"
    dbC.dungeonSort = "Level"
    local s = CX.SortedEntries()
    local ok = true
    for i = 2, #s do
        local a = tonumber(s[i - 1].e.levels:match("^(%d+)")) or 0
        local b = tonumber(s[i].e.levels:match("^(%d+)")) or 0
        if a > b then ok = false end
    end
    check(ok and s[1].e.levels:match("^13"), "dungeons sort by level (" .. s[1].e.name .. " first)")
    dbC.dungeonSort = "A-Z"
    s = CX.SortedEntries()
    check(s[1].e.name < s[2].e.name and s[#s].e.name:find("^Zul") ~= nil, "or A-Z (" .. s[1].e.name .. " .. " .. s[#s].e.name .. ")")
    dbC.dungeonSort = "Level"
    ui.jmode = "Raids"
    s = CX.SortedEntries()
    local heads, sizes = {}, {}
    for _, it in ipairs(s) do if it.header then heads[#heads + 1] = it.header else sizes[#sizes + 1] = it.e.size end end
    local sorted = true
    for i = 2, #sizes do if sizes[i] < sizes[i - 1] then sorted = false end end
    check(sorted and heads[1] == "20-player raids" and heads[#heads] == "40-player raids", "raids group by size, smallest first (" .. table.concat(heads, ", ") .. ")")
    ui.jmode = "Dungeons"

    -- stat weights: a leveling shadow priest's Intellect and Spirit outweigh a little spell power
    local IS = CN.ItemStats
    local function stats(lines) local t = {}; for _, l in ipairs(lines) do IS.ParseLine(l, t) end; return t end
    local new = stats({ "+6 Strength", "Equip: Restores 2 mana per 5 sec.", "Equip: Increases damage and healing done by magical spells and effects by up to 5." })
    local old = stats({ "+3 Strength", "+8 Intellect", "Enchanted: Spirit +4" })
    check(old.SPI == 4 and old.INT == 8, "an enchant on what you wear counts (you lose it in a swap)")
    local function sc(t, lvl) return IS.Score(t, CX.WeightsFor("PRIEST", "Shadow", lvl), "PRIEST", "Shadow") end
    check(sc(new, 26) < sc(old, 26), ("at level 26, +5 spell power and 2 mp5 don't beat 8 Intellect and 4 Spirit (%.1f vs %.1f)"):format(sc(new, 26), sc(old, 26)))
    check(sc(new, 60) > sc(old, 60), "at 60, the spell power wins")
    -- weapon damage outweighs a few stats on a two-hander
    local arms = CX.WeightsFor("WARRIOR", "Arms", 30)
    check(IS.Score({ DPS = 20, STR = 5 }, arms) < IS.Score({ DPS = 23 }, arms), "for Arms, 3 weapon DPS beats 5 Strength")
    errorsSoFar("codex browse")
end
