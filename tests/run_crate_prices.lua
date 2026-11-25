-- Exchange lists the bundles a Waylaid Crate asks for in its RUIN: Exchange
-- box, each with what it costs on the auction house. Runs inside run_features.lua.
local alice, check = T.alice, T.check

print("Exchange: Waylaid Crate bundles in the Exchange box")
do
    local env = alice.env
    local ex = env.RUIN_API:GetModule("Exchange")
    local db = env.RUIN_ExchangeDB
    local saved = {}
    for id, p in pairs({ [13463] = 1300, [13465] = 1050 }) do saved[id] = db.prices[id]; db.prices[id] = { p = p, t = env.GetServerTime() } end
    saved[13467] = db.prices[13467]; db.prices[13467] = nil
    -- a tooltip whose lines the game wrote
    local lines = { "Waylaid Crate: Flowering Artisan Herbs",
        "Use: Fill the crate with any bundle from the following list:\n- 20 Dreamfoil\n- 20 Mountain Silversage\n- 20 Icecap", "Requires Level 35" }
    local tip = { GetName = function() return "RuinCrateTip" end, NumLines = function() return #lines end }
    for i = 1, 3 do env["RuinCrateTipTextLeft" .. i] = { GetText = function() return lines[i] end } end
    local b = ex.CrateBundles(tip)
    check(b and #b == 3 and b[1].n == 20 and b[1].name == "Dreamfoil" and b[1].id == 13463, "the crate's bundles are read from its tooltip, even items never seen by name")
    local out = ex.CrateLines(b)
    local W = env.RUIN_API.Widgets
    check(out[1]:find("Fill it with", 1, true), "the box says what fills it")
    check(W.PlainMoney(out[2]):find("20 Dreamfoil:|r 2g 60s", 1, true), "each bundle shows its total AH price (" .. W.PlainMoney(out[2]) .. ")")
    check(W.PlainMoney(out[2]):find("(13s each)", 1, true), "and the price of one")
    check(out[4]:find("20 Icecap", 1, true) and out[4]:find("none yet", 1, true), "a reagent with no AH price says none yet")
    check(lines[2]:find("- 20 Dreamfoil\n", 1, true), "the game's own lines are left as they are")
    lines[1] = "Linen Cloth"
    check(ex.CrateBundles(tip) == nil, "other items get no bundle list")
    for id, v in pairs(saved) do db.prices[id] = v end
end
