-- Codex: spell math on spell tooltips (mana per point, expected DPS/HPS),
-- with crits counted, for cast, instant, channeled and periodic spells.
local alice, check, errorsSoFar = T.alice, T.check, T.errorsSoFar

print("Codex: spell math")
do
    local env = alice.env
    local X = env.RUIN_API:GetModule("Codex")
    local P = X.ParseSpellText

    local fb = P("Hurls a fiery ball that causes 31 to 45 Fire damage and an additional 2 Fire damage over 4 sec.")
    check(fb and fb.direct == 38 and fb.periodic == 2 and fb.periodicTime == 4 and fb.school == 3 and not fb.heal, "Fireball: direct 31-45 plus 2 over 4 sec, Fire")
    local cor = P("Corrupts the target, causing 40 Shadow damage over 12 sec.")
    check(cor and not cor.direct and cor.periodic == 40 and cor.periodicTime == 12, "Corruption: periodic only")
    local am = P("Launches Arcane Missiles at the enemy, causing 26 Arcane damage each second for 3 sec.")
    check(am and am.periodic == 78 and am.periodicTime == 3, "Arcane Missiles: each second for 3 sec")
    local fh = P("Heals a friendly target for 193 to 237.")
    check(fh and fh.heal and fh.direct == 215, "Flash Heal: a heal of 193-237")
    local ren = P("Heals the target of 45 damage over 15 sec.")
    check(ren and ren.heal and ren.periodic == 45 and ren.periodicTime == 15, "Renew: healing over time")
    local dl = P("Transfers 10 health every 1 sec from the target to the caster. Lasts 5 sec.")
    check(dl and dl.periodic == 50 and dl.periodicTime == 5, "Drain Life: every 1 sec, lasts 5 sec")
    check(P("Increases your armor by 40.") == nil, "spells that don't damage or heal get nothing")

    -- the tooltip lines, with a fake spell
    local realSpell, realCrit = env.C_Spell, env.GetSpellCritChance
    local descs = {
        [133] = "Hurls a fiery ball that causes 31 to 45 Fire damage and an additional 2 Fire damage over 4 sec.",
        [5143] = "Launches Arcane Missiles at the enemy, causing 26 Arcane damage each second for 3 sec.",
        [172] = "Corrupts the target, causing 40 Shadow damage over 12 sec.",
    }
    env.C_Spell = setmetatable({
        GetSpellDescription = function(id) return descs[id] end,
        GetSpellInfo = function(id) return { castTime = ({ [133] = 2500, [5143] = 0, [172] = 0 })[id] } end,
        GetSpellPowerCost = function(id) return { { type = 0, cost = ({ [133] = 65, [5143] = 85, [172] = 35 })[id] } } end,
    }, { __index = realSpell })
    env.GetSpellCritChance = function(school) return 10 end
    local m = X.SpellMath(133)
    -- (38 + 2) * (1 + 0.1 * 0.5) = 42; 2.5 sec cast
    check(m and math.abs(m.expected - 42) < 0.01 and math.abs(m.perSecond - 42 / 2.5) < 0.01 and math.abs(m.perPoint - 65 / 42) < 0.001,
          "Fireball: crits counted, per second of the cast, mana per point (" .. tostring(m and m.expected) .. ")")
    local tip = env.CreateFrame("GameTooltip", "SpellTestTip")
    tip.GetName = function() return "SpellTestTip" end
    tip.NumLines = function() return 2 end
    env.SpellTestTipTextLeft1 = tip:CreateFontString(); env.SpellTestTipTextLeft1:SetText("Arcane Missiles")
    env.SpellTestTipTextLeft2 = tip:CreateFontString(); env.SpellTestTipTextLeft2:SetText("Channeled")
    m = X.SpellMath(5143, tip)
    check(m and math.abs(m.perSecond - 78 * 1.05 / 3) < 0.01, "Arcane Missiles: channeled, per second of the channel")
    m = X.SpellMath(172)
    check(m and math.abs(m.expected - 42) < 0.01 and math.abs(m.perSecond - 42 / 12) < 0.01, "Corruption: damage over time crits too on WoW Forever, per second of its duration")
    local added
    tip.AddDoubleLine = function(_, l, r) added = { l, r } end
    env.SpellTestTipTextLeft2:SetText("2.5 sec cast")
    X.OnSpellTooltip(tip, { id = 133 })
    check(added and added[1]:find("1.55 mana per damage") and added[2]:find("16.8 DPS"), "the tooltip gets mana per point on the left and DPS on the right (" .. tostring(added and added[1]) .. " / " .. tostring(added and added[2]) .. ")")
    -- a spell inside a macro on an action bar: the tooltip is the macro's
    added = nil
    tip.ruinSpellMath = nil          -- a new showing
    local button = { action = 7 }
    tip.GetOwner = function() return button end
    tip.GetSpell = nil
    local realAction, realMacro = env.GetActionInfo, env.GetMacroSpell
    env.GetActionInfo = function(slot) if slot == 7 then return "macro", 3 end end
    env.GetMacroSpell = function(i) return i == 3 and 133 or nil end
    X.OnMacroTooltip(tip, { type = 3 })
    check(added and added[2]:find("16.8 DPS"), "a spell in a macro gets the same line (" .. tostring(added and added[2]) .. ")")
    env.GetActionInfo, env.GetMacroSpell = realAction, realMacro
    env.C_Spell, env.GetSpellCritChance = realSpell, realCrit
    errorsSoFar("spell math")
end
