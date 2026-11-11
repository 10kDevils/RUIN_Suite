-- Exchange 0.5.2: vendor prices. Seen at a merchant, shared with RUIN, and
-- used only where they're cheaper than the auction house, marked as vendor.
local alice, cara, check, errorsSoFar = T.alice, T.cara, T.check, T.errorsSoFar
local Server = Server

print("Exchange: vendor prices")
do
    local env = alice.env
    local X = env.RUIN_API:GetModule("Exchange")
    local db = env.RUIN_ExchangeDB
    local now = env.GetServerTime()
    db.prices[2678] = { p = 40, t = now }           -- Mild Spices: 40c on the AH
    db.prices[2589] = { p = 300, t = now }          -- Linen: 3s on the AH
    db.vendor = {}
    local stock = {                                  -- id, price, stack, available, extended cost
        { 2678, 10, 1, -1 },                          -- spices 10c: cheaper than the AH
        { 2589, 2000, 5, -1 },                        -- linen 4s each: dearer than the AH
        { 3371, 20, 1, -1 },                          -- vial: no AH price at all
        { 4400, 500, 1, 3 },                          -- limited stock: skipped
        { 4401, 0, 1, -1, true },                     -- token item: skipped
    }
    local realUnitName = env.UnitName
    env.GetMerchantNumItems = function() return #stock end
    env.GetMerchantItemID = function(i) return stock[i] and stock[i][1] end
    env.GetMerchantItemInfo = function(i) local s = stock[i]; return "x", 1, s[2], s[3], s[4], true, true, s[5] end
    env.UnitName = function(u) if u == "npc" then return "Tharynn Bouden" end return realUnitName(u) end
    local realTI = env.C_TooltipInfo
    env.C_TooltipInfo = setmetatable({ GetUnit = function(u)
        if u == "npc" then return { lines = { { leftText = "Tharynn Bouden" }, { leftText = "Trade Goods" }, { leftText = "Level 40" } } } end
    end }, { __index = realTI })

    Server.fire(alice, "MERCHANT_SHOW")
    Server:Advance(1)
    check(db.vendor[2678] and db.vendor[2678].p == 10 and db.vendor[2678].by == "Tharynn Bouden", "a merchant's prices are kept, with the vendor's name")
    check(db.vendor[2589] and db.vendor[2589].p == 400, "stacks are priced per item")
    check(not db.vendor[4400] and not db.vendor[4401], "limited stock and token items are left out")

    local p, src, by = X.BuyPrice(2678)
    check(p == 10 and src == "vendor" and by == "Tharynn Bouden", "cheaper at the vendor: the vendor price is used, marked as vendor")
    p, src = X.BuyPrice(2589)
    check(p == 300 and src == nil, "dearer at the vendor: the auction house price stays")
    p, src = X.BuyPrice(3371)
    check(p == 20 and src == "vendor", "no auction house price: the vendor price is used")
    check(X.PriceOf(2678) == 40, "the auction house price itself is untouched")

    check(db.vendor[2678].kind == "Trade Goods", "the merchant's title is kept too")
    local P = alice.env.RUIN_API.Widgets.PlainMoney
    local function plainLines(t) local o = {} for i, l in ipairs(t or {}) do o[i] = (P(l):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end return o end
    local lines = plainLines(X.PriceLines("item:2678"))
    check(lines[1] == "RUIN: Exchange" and lines[2]:find("^AH price: 40c") and lines[3] == "Vendor: 10c from Trade Goods NPC",
          "the tooltip's RUIN: Exchange section: the AH price, then the cheaper merchant by kind (" .. tostring(lines[2]) .. " / " .. tostring(lines[3]) .. ")")
    check((X.PriceLines("item:2678")[2] or ""):find("UI%-CopperIcon"), "with the game's coin icons")
    -- a stack of 6: the AH price for the stack, with the price each
    lines = plainLines(X.PriceLines("item:2678", 6))
    check(lines[2]:find("^AH price: 2s 40c %(40c each%)"), "a stack is priced as the stack (" .. tostring(lines[2]) .. ")")
    -- where to sell: the AH when it beats the vendor's buying price by enough, else the vendor
    db.prices[2678].p = 40
    lines = plainLines(X.PriceLines("item:2678", 6))
    local last = lines[#lines]
    check(last:find("^Sell on AH: 2s 40c") or last:find("^Sell to Vendor:"), "the last line says where to sell, for the whole stack (" .. last .. ")")
    -- disenchant: recommended when the mats are worth more, or the likely mat is blue or better
    alice.items[301] = { name = "Ridge Cleaver", link = "|cff1eff00|Hitem:301::|h[Ridge Cleaver]|h|r", q = 2, ilvl = 22, loc = "INVTYPE_2HWEAPON", sell = 300, classID = 2 }
    alice.items[10998] = { name = "Lesser Astral Essence", link = "|cff1eff00|Hitem:10998::|h[Lesser Astral Essence]|h|r", q = 2, sell = 0 }
    alice.items[10940] = { name = "Strange Dust", link = "|cffffffff|Hitem:10940::|h[Strange Dust]|h|r", q = 1, sell = 0 }
    alice.items[10978] = { name = "Small Glimmering Shard", link = "|cff0070dd|Hitem:10978::|h[Small Glimmering Shard]|h|r", q = 3, sell = 0 }
    local Y = X.DisenchantYield(301)
    check(Y and Y[1][1] == 10940 and math.abs(Y[2][2] - 0.75) < 0.001 and Y[2][1] == 10998, "a green weapon breaks mostly into essence (" .. tostring(Y and #Y) .. ")")
    db.prices[301] = { p = 400, t = env.GetServerTime() }
    db.prices[10998] = { p = 2000, t = env.GetServerTime() }
    db.prices[10940] = { p = 300, t = env.GetServerTime() }
    db.prices[10978] = { p = 1500, t = env.GetServerTime() }
    local L = plainLines(X.PriceLines("item:301"))
    check(L[#L]:find("^Disenchant: ~") and L[#L]:find("Lesser Astral Essence"), "Disenchant when the mats beat the AH and the vendor (" .. L[#L] .. ")")
    db.prices[10998].p, db.prices[10940].p, db.prices[10978].p = 10, 10, 10
    L = plainLines(X.PriceLines("item:301"))
    check(L[#L]:find("^Sell to Vendor: 3s"), "otherwise sell it: 4s on the AH nets less than the vendor's 3s after the deposit and cut (" .. L[#L] .. ")")
    db.prices[301].p = 1000
    L = plainLines(X.PriceLines("item:301"))
    check(L[#L] == "Sell on AH: 10s  (nets 8s 50c)", "the AH when it's worth it after the 1 silver deposit and 5% cut (" .. L[#L] .. ")")
    alice.items[302] = { name = "Bright Helm", link = "|cff0070dd|Hitem:302::|h[Bright Helm]|h|r", q = 3, ilvl = 24, loc = "INVTYPE_HEAD", sell = 300, classID = 4 }
    db.prices[302] = { p = 99999, t = env.GetServerTime() }
    L = plainLines(X.PriceLines("item:302"))
    check(L[#L]:find("^Sell on AH"), "disenchanting is only about the mats' value: a pricey blue sells (" .. L[#L] .. ")")
    db.prices[302].p = 500
    db.prices[10978].p = 1500
    L = plainLines(X.PriceLines("item:302"))
    check(L[#L]:find("^Disenchant: ~15s") and L[#L]:find("Small Glimmering Shard"), "and a cheap one is disenchanted (" .. L[#L] .. ")")

    -- craft: a reagent that makes something worth more than the reagents
    alice.items[6888] = { name = "Herb Baked Egg", link = "|cffffffff|Hitem:6888::|h[Herb Baked Egg]|h|r", q = 1, sell = 6 }
    alice.items[6889] = { name = "Small Egg", link = "|cffffffff|Hitem:6889::|h[Small Egg]|h|r", q = 1, sell = 4 }
    local guid = alice.env.RUIN_API:GetPlayerGUID()
    db.crafters[guid] = { name = "Alice Ash", profs = { Cooking = { "Herb Baked Egg" } }, made = { Cooking = { i = { 6888 }, q = { 1 } } } }
    db.recipeBook.Cooking = db.recipeBook.Cooking or {}
    db.recipeBook.Cooking["Herb Baked Egg"] = { { 6889, 1 }, { 2678, 1 } }
    db.prices[6888] = { p = 5000, t = env.GetServerTime() }
    db.prices[6889] = { p = 100, t = env.GetServerTime() }
    L = plainLines(X.PriceLines("item:6889"))
    check(L[#L - 1] == "Craft: Herb Baked Egg" and L[#L]:find("^%(sells ~"), "a reagent says Craft when what it makes sells for more, the sums on the line below (" .. L[#L - 1] .. " / " .. L[#L] .. ")")
    db.prices[6888].p = 120
    L = plainLines(X.PriceLines("item:6889"))
    check(not L[#L]:find("^Craft") and not L[#L]:find("^%(sells"), "and doesn't when it doesn't (" .. L[#L] .. ")")
    db.crafters[guid] = nil
    check(X.DisenchantYield(2678) == nil, "things that aren't gear can't be disenchanted")

    -- the section is boxed: a faint gold border round its lines
    local tip = env.CreateFrame("GameTooltip", "RuinBoxTestTip")
    tip.GetName = function() return "RuinBoxTestTip" end
    for i = 1, 3 do env["RuinBoxTestTipTextLeft" .. i] = tip:CreateFontString() end
    X.BoxLines(tip, 1, 3)
    check(tip.ruinBox and tip.ruinBox.fill and tip.ruinBox.top and tip.ruinBox.left, "the Exchange section gets its box")

    -- recipe costs use the cheaper one
    local function strip(t) return (alice.env.RUIN_API.Widgets.PlainMoney(t or "")):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
    check(strip(X.CraftText({ { 2678, 2 } })) == "20c/craft", "Price per Craft uses the vendor price when it's cheaper (" .. strip(X.CraftText({ { 2678, 2 } })) .. ")")

    -- shared with RUIN when the window closes
    env.UnitName = realUnitName
    Server.fire(alice, "MERCHANT_CLOSED")
    Server:Advance(20)
    local cv = cara.env.RUIN_ExchangeDB.vendor
    check(cv and cv[2678] and cv[2678].p == 10 and cv[2678].by == "Tharynn Bouden", "closing the merchant shares its prices with RUIN")
    check(cv[2678].kind == "Trade Goods", "with the merchant's title")
    env.C_TooltipInfo = realTI

    errorsSoFar("vendor prices")
end
