-- Codex 0.5.3: weapons compare as a set (main hand + off hand), and with
-- Ruinous Forever Planner running, the planner compares gear: Codex's tooltip
-- line steps aside and its verdicts for other modules come from the planner.
-- Runs after the other run_features_*.lua files and shares T.
local alice, check, errorsSoFar = T.alice, T.check, T.errorsSoFar

print("Codex: weapons as a set, and Ruinous Forever Planner")
do
    local env = alice.env
    local cx = env.RUIN_API:GetModule("Codex")
    local realPlanner = env.RuinousForeverPlanner
    env.RuinousForeverPlanner = nil
    local items = {   -- id -> equip slot, strength
        [501] = { "INVTYPE_2HWEAPON", 30 }, [502] = { "INVTYPE_2HWEAPON", 24 },
        [503] = { "INVTYPE_WEAPONMAINHAND", 14 }, [504] = { "INVTYPE_SHIELD", 10 },
        [505] = { "INVTYPE_WEAPON", 12 }, [506] = { "INVTYPE_WEAPON", 8 }, [507] = { "INVTYPE_HOLDABLE", 6 },
    }
    local worn = {}
    local function idOf(link) return tonumber(tostring(link):match("item:(%d+)")) end
    local saved = { env.UnitClass, env.GetItemStats, env.C_TooltipInfo, env.GetInventoryItemLink, env.GetItemInfoInstant, env.CanDualWield }
    env.GetItemInfoInstant = function(link) local it = items[idOf(link) or 0]; return idOf(link), "Weapon", "", it and it[1] or "INVTYPE_HEAD" end
    env.GetItemStats = function(link) local it = items[idOf(link) or 0]; return it and { ITEM_MOD_STRENGTH_SHORT = it[2] } or {} end
    env.C_TooltipInfo = { GetHyperlink = function() return { lines = { { leftText = "Item" } } } end }
    env.GetInventoryItemLink = function(_, slot) return worn[slot] and ("|cffffffff|Hitem:" .. worn[slot] .. "::|h[x]|h|r") or nil end
    env.UnitClass = function() return "Warrior", "WARRIOR" end
    env.RUIN_CodexDB.spec = "Arms"
    alice.mns.RUIN_Codex.ItemStats.Forget()
    local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.6 end

    -- a two-hander against main hand + off hand
    worn = { [16] = 503, [17] = 504 }              -- sword 14 + shield 10 = 24
    local pct = cx:Compare(501)                    -- 30 vs 24
    check(near(pct, 25), "a two-hander is compared with your main hand plus off hand together (+" .. tostring(pct) .. "%, not +114% over the sword alone)")
    worn = { [16] = 502 }                          -- a 24 two-hander
    pct = cx:Compare(501)
    check(near(pct, 25), "a two-hander against the two-hander you wield (" .. tostring(pct) .. ")")
    check(cx:Compare(502) == "same", "the two-hander you wield is the same item")

    -- while wielding a two-hander
    pct = cx:Compare(503)                          -- 14 one-hander vs 24 two-hander
    check(type(pct) == "number" and pct < 0, "a one-hander against your two-hander is a downgrade, not an upgrade for an empty off hand (" .. tostring(pct) .. ")")
    check(cx:Compare(504) == "twohander" and cx:IsUpgrade(504) == nil, "a shield while you wield a two-hander isn't called an upgrade")
    -- with an off hand in your bags or bank: the pair against the whole two-hander
    alice.bag = { { itemID = 504 } }               -- a 10 shield in the bags
    pct = cx:Compare(503)                          -- 14 + 10 = 24 vs 24
    check(near(pct, 0), "a one-hander is weighed with the best off hand in your bags, against the whole two-hander (" .. tostring(pct) .. ")")
    alice.bag = {}
    env.RUIN_CodexDB.bank = { [env.UnitGUID("player")] = { "|cffffffff|Hitem:507::|h[x]|h|r", "|cffffffff|Hitem:504::|h[x]|h|r" } }
    pct = cx:Compare(505)                          -- 12 + the shield 10 (better than the 6 held item) = 22 vs 24
    check(near(pct, -8.3), "or in your bank, the best of them (" .. tostring(pct) .. ")")
    env.UnitClass = function() return "Priest", "PRIEST" end
    env.RUIN_CodexDB.spec = "Shadow"
    alice.mns.RUIN_Codex.ItemStats.Forget()
    local best = cx.BestOffhand()
    check(not (best and best:find("item:504", 1, true)), "a class without shields never gets a shield as its off hand")
    env.UnitClass = function() return "Warrior", "WARRIOR" end
    env.RUIN_CodexDB.spec = "Arms"
    alice.mns.RUIN_Codex.ItemStats.Forget()
    env.RUIN_CodexDB.bank = nil
    -- a one-hand weapon for a class that can't wield two
    env.UnitClass = function() return "Paladin", "PALADIN" end
    env.CanDualWield = function() return false end
    env.RUIN_CodexDB.spec = "Retribution"
    alice.mns.RUIN_Codex.ItemStats.Forget()
    worn = { [16] = 506 }                          -- 8 one-hander, nothing in the off hand
    pct = cx:Compare(505)
    check(near(pct, 50), "a one-hander for a paladin is compared with the main hand, not the empty off hand (" .. tostring(pct) .. ")")
    -- dual wield: against the weaker hand
    env.UnitClass = function() return "Rogue", "ROGUE" end
    env.CanDualWield = function() return true end
    env.RUIN_CodexDB.spec = "Combat"
    alice.mns.RUIN_Codex.ItemStats.Forget()
    worn = { [16] = 505, [17] = 506 }              -- 12 + 8
    pct = cx:Compare(503)                          -- a main-hand-only weapon: main hand
    check(type(pct) == "number", "a main-hand weapon compares with the main hand (" .. tostring(pct) .. ")")
    worn = { [16] = 503, [17] = 506 }              -- 14 + 8
    pct = cx:Compare(505)                          -- 12 vs the weaker hand (8)
    check(near(pct, 50), "a rogue's one-hander is compared with the weaker hand (" .. tostring(pct) .. ")")

    -- the tooltip line for a two-hander names both hands
    env.UnitClass = function() return "Warrior", "WARRIOR" end
    env.RUIN_CodexDB.spec = "Arms"
    alice.mns.RUIN_Codex.ItemStats.Forget()
    worn = { [16] = 503, [17] = 504 }

    -- Ruinous Forever Planner running: it compares
    local asked = {}
    env.RuinousForeverPlanner = {
        ItemDetails = function(link) local it = items[idOf(link) or 0]; return it and { equipLoc = it[1], id = idOf(link) } end,
        WeightedStatScore = function() return 1 end,
        CompareEquipment = function(slot, d)
            asked[#asked + 1] = slot
            if d.equipLoc == "INVTYPE_2HWEAPON" then return { before = 20, after = 18, hands = true, slot = slot } end
            return { before = 10, after = 15, slot = slot }
        end,
    }
    check(cx.PlannerHandlesGear() == true, "Codex sees Ruinous Forever Planner")
    pct = cx:Compare(501)
    check(near(pct, -10) and asked[1] == 16 and cx:IsUpgrade(501) == false, "Codex's verdict now comes from the planner (" .. tostring(pct) .. ")")
    env.RUIN_API:OpenTab("Codex")
    T.openAllSubTabs(alice, "Codex")
    local ui = cx.UI
    for _, w in ipairs({ ui.plannerNote, ui.tipCheck, ui.specCycle }) do w.SetShown = function(self, v) self._vis = v and true or false end end
    ui.tabs:Select(1)                               -- the Journal
    check(ui.plannerNote._vis == true and ui.tipCheck._vis == false and ui.specCycle._vis == false,
        "the Journal says the planner handles gear, instead of Codex's weights and tooltip switch")
    env.RuinousForeverPlanner = realPlanner
    ui.tabs:Select(1)
    check(ui.tipCheck._vis == true and ui.plannerNote._vis == false, "without the planner, Codex's own controls come back")

    env.UnitClass, env.GetItemStats, env.C_TooltipInfo, env.GetInventoryItemLink, env.GetItemInfoInstant, env.CanDualWield = unpack(saved, 1, 6)
    env.RUIN_CodexDB.spec = "Auto"
    alice.mns.RUIN_Codex.ItemStats.Forget()
    errorsSoFar("codex weapons")
end

print("Ruinous Forever Planner: one stat estimate per tooltip")
do
    local env = alice.env
    local saved = env.RuinousForeverPlanner
    local calls = 0
    local lines = {}
    local tip = { GetName = function() return "PlanTestTip" end, NumLines = function() return #lines end,
                  AddLine = function(_, t) lines[#lines + 1] = t; env["PlanTestTipTextLeft" .. #lines] = { GetText = function() return t end } end }
    local P = { AppendItemRating = function(t) calls = calls + 1; t:AddLine(" "); t:AddLine("Ruinous Forever Planner - stat estimate") end }
    env.RuinousForeverPlanner = P
    alice.ns.Planner:GuardTooltips()
    P.AppendItemRating(tip)
    tip:AddLine("RUIN: Exchange")                 -- another addon adds lines after it
    P.AppendItemRating(tip)                        -- the planner's later hook
    check(calls == 1, "the planner's block is added once, even after other addons add lines")
    lines = {}
    P.AppendItemRating(tip)
    check(calls == 2, "and again for the next item")
    env.RuinousForeverPlanner = saved
    errorsSoFar("planner tooltip")
end

print("Codex: spec from your talents")
do
    local env = alice.env
    local CX = env.RUIN_API:GetModule("Codex")
    local saved = { env.UnitClass, env.GetSpecialization, env.GetSpecializationInfo, env.GetTalentTabInfo, env.RUIN_CodexDB.spec }
    env.UnitClass = function() return "Priest", "PRIEST", 5 end
    env.GetSpecialization = function() return 1 end                          -- the client always says the first spec
    env.GetSpecializationInfo = function() return 256, "Discipline" end
    local points = { 5, 0, 31 }
    local names = { "Discipline", "Holy", "Shadow" }
    -- newer clients: id, name, description, icon id, points spent
    env.GetTalentTabInfo = function(tab) return 200 + tab, names[tab], "desc", 135940, points[tab] end
    env.RUIN_CodexDB.spec = "Auto"
    check(CX.MySpec() == "Shadow", "Auto picks the tree with the most points, not the client's first spec (" .. tostring(CX.MySpec()) .. ")")
    points = { 21, 30, 0 }
    check(CX.MySpec() == "Holy", "and follows a respec")
    points = { 0, 0, 0 }
    check(CX.MySpec() == "Discipline", "with no points spent, the client's spec")
    env.RUIN_CodexDB.spec = "Shadow"
    points = { 31, 0, 0 }
    check(CX.MySpec() == "Shadow", "a spec picked by hand still wins")
    -- trees without point counts: the talents themselves are counted
    env.RUIN_CodexDB.spec = "Auto"
    env.GetTalentTabInfo = function(tab) return 200 + tab, names[tab], "desc", 135940 end
    local ranks = { [1] = { 2, 0 }, [2] = { 0, 0 }, [3] = { 5, 5, 3 } }
    env.GetNumTalents = function(tab) return #ranks[tab] end
    env.GetTalentInfo = function(tab, i) return "t", 1, 1, i, ranks[tab][i], 5 end
    check(CX.MySpec() == "Shadow", "with no point counts on the trees, Auto adds up the talents' ranks (" .. tostring(CX.MySpec()) .. ")")
    -- Ruinous Forever Planner without a client spec falls back to its menu's last pick: Codex gives it the talents' spec
    local savedP = env.RuinousForeverPlanner
    local P = { char = { spec = "Discipline", class = "PRIEST" }, actualClass = "PRIEST",
                Data = { profiles = { PRIEST = { "Discipline", "Holy", "Shadow" } } } }
    function P.Profile(class, spec) P.char.spec = spec; return true end
    function P.AutoProfile() P.detectedSpec = nil; P.Profile("PRIEST", "Discipline") end
    env.RuinousForeverPlanner = P
    CX.HookPlanner()
    P.AutoProfile()
    check(P.char.spec == "Shadow", "Ruinous Forever Planner is set to the spec your talents say (" .. tostring(P.char.spec) .. ")")
    env.RuinousForeverPlanner = savedP
    env.GetNumTalents, env.GetTalentInfo = nil, nil
    env.UnitClass, env.GetSpecialization, env.GetSpecializationInfo, env.GetTalentTabInfo, env.RUIN_CodexDB.spec = unpack(saved)
    errorsSoFar("spec from talents")
end

print("Exchange: Working Overtime")
do
    local EX = alice.env.RUIN_API:GetModule("Exchange")
    local xdb = alice.env.RUIN_ExchangeDB
    local was = xdb.overtime
    xdb.overtime = 5
    check(math.abs(EX.Overtime(0.25, 2) - 0.45) < 1e-9 and math.abs(EX.Overtime(0.75, 1) - 0.95) < 1e-9, "rank 5 adds 20% on top of a green's and a yellow's chance")
    check(EX.Overtime(0.9, 1) == 1 and EX.Overtime(1, 0) == 1, "never above 100%, and orange stays as it is")
    xdb.overtime = 2
    local c = EX.ChanceFor("Cooking", "Nothing Known", 2, 100)
    check(math.abs(c - 0.33) < 1e-9, "the chance used for Price per Point includes it (" .. tostring(c) .. ")")
    xdb.overtime = was
    errorsSoFar("working overtime")
end
