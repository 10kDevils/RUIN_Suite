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
