-- Exchange prices each bundle a Waylaid Crate asks for, on the crate's own
-- tooltip lines. Runs inside run_features.lua.
local alice, check = T.alice, T.check

print("Exchange: Waylaid Crate bundle prices")
do
    local env = alice.env
    local ex = env.RUIN_API:GetModule("Exchange")
    local db = env.RUIN_ExchangeDB
    local saved = {}
    for _, e in ipairs({ { 11176, "Dream Dust", 18000 }, { 11175, "Greater Nether Essence", 90000 } }) do
        local id, name, p = e[1], e[2], e[3]
        saved[id] = db.prices[id]
        db.prices[id] = { p = p, t = env.GetServerTime() }
        env.RUIN_ItemCache = env.RUIN_ItemCache or {}
    end
    local realIdByName = env.RUIN_API.Items.IdByName
    env.RUIN_API.Items.IdByName = function(n) return ({ ["Dream Dust"] = 11176, ["Greater Nether Essence"] = 11175 })[n] or realIdByName(n) end
    local text = "Use: Fill the crate with any bundle from the following list:\n- 20 Dream Dust\n- 4 Greater Nether Essence\n- 6 Unpriced Shard"
    local out = ex.CrateText(text) or ""
    local dust = out:match("%- 20 Dream Dust  ([^\n]+)")
    check(dust and env.RUIN_API.Widgets.PlainMoney(dust) == "36g", "20 Dream Dust shows what 20 cost, in coins (" .. tostring(dust) .. ")")
    check(out:find("- 4 Greater Nether Essence  ", 1, true), "every priced bundle gets its cost")
    check(out:find("- 6 Unpriced Shard$"), "a bundle nobody has priced is left as it was")
    check(ex.CrateText(out) == nil, "a crate already priced isn't priced twice")
    env.RUIN_API.Items.IdByName = realIdByName
    for id, v in pairs(saved) do db.prices[id] = v end
end
