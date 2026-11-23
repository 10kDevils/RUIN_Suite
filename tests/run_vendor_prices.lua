-- Exchange 0.5.2: vendor prices. Seen at a merchant, shared with RUIN, and
-- used only where they're cheaper than the auction house, marked as vendor.
-- Exchange 0.8.4's section layout: each way out of the bag and its value.
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
    -- prices below are written straight into the saved data, so tell Exchange
    -- they changed (in game every price goes through it, which does this)
    local function bump() X.priceGen = (X.priceGen or 0) + 1 end
    local GREEN = "|cff5cd973"
    -- the line starting with label, plain, and whether it's the green (best) one
    local function row(t, label)
        for _, l in ipairs(t or {}) do
            local plain = (P(l):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
            if plain:find("^%s*" .. label) then return plain, l:find(GREEN, 1, true) ~= nil end
        end
    end
    -- Exchange 0.8.4: the section lists what each way out of the bag is worth
    -- (vendor, disenchant or craft, the AH after its deposit and cut), the
    -- best one green; a cheaper merchant shows as Buy from vendor
    bump()
    local lines = plainLines(X.PriceLines("item:2678"))
    check(lines[1] == "RUIN: Exchange" and lines[2] == "Buy from vendor: 10c from Trade Goods NPC" and lines[3] == "AH: 0c",
          "the tooltip's RUIN: Exchange section: the cheaper merchant by kind, then what one nets on the AH (" .. tostring(lines[2]) .. " / " .. tostring(lines[3]) .. ")")
    check((X.PriceLines("item:2678")[2] or ""):find("UI%-CopperIcon"), "with the game's coin icons")
    -- a stack of 6: priced as the stack, with the price each
    lines = plainLines(X.PriceLines("item:2678", 6))
    check(lines[2] == "Buy from vendor: 60c (10c each) from Trade Goods NPC" and lines[3] == "AH: 1s 28c  (21c each)",
          "a stack is priced as the stack, the AH after the 1s deposit and 5% cut (" .. tostring(lines[2]) .. " / " .. tostring(lines[3]) .. ")")
    -- the price to expect: the one just seen while it's fresh, else the low end
    -- of the last week's prices (a misposted one left out)
    local day = math.floor(env.GetServerTime() / 86400)
    db.history[2678] = { [day] = 60, [day - 1] = 35, [day - 2] = 50, [day - 3] = 10, [day - 20] = 5 }
    db.prices[2678].p = 60
    local exp, cur = X.ExpectedPrice(2678)
    check(exp == 60 and cur == 60, "a price seen in the last two hours is the one to expect (" .. tostring(exp) .. ")")
    db.prices[2678].t = env.GetServerTime() - 3 * 3600
    exp, cur = X.ExpectedPrice(2678)
    check(exp == 35 and cur == 60, "once it's older, the week's low end, not a mispost or an old low (" .. tostring(exp) .. ")")
    bump()
    lines = plainLines(X.PriceLines("item:2678", 6))
    check(lines[3] == "AH: 99c  (17c each)", "the AH line uses that price (" .. tostring(lines[3]) .. ")")
    db.history[2678] = nil
    db.prices[2678].p, db.prices[2678].t = 40, env.GetServerTime()
    -- disenchant: recommended when the mats are worth more
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
    bump()
    local L = X.PriceLines("item:301")
    local de, deBest = row(L, "Disenchant:")
    check(de and de:find("^Disenchant: ~") and deBest and de:find("· Lesser Astral Essence", 1, true), "Disenchant is best when the mats beat the AH and the vendor (" .. tostring(de) .. ")")
    db.prices[10998].p, db.prices[10940].p, db.prices[10978].p = 10, 10, 10
    bump()
    L = X.PriceLines("item:301")
    local v, vBest = row(L, "Vendor:")
    local ah = row(L, "AH:")
    check(v == "Vendor: 3s" and vBest and ah == "AH: 2s 80c", "otherwise the vendor: 4s on the AH nets less than the vendor's 3s after the deposit and cut (" .. tostring(ah) .. ")")
    db.prices[301].p = 1000
    bump()
    ah, vBest = row(X.PriceLines("item:301"), "AH:")
    check(ah == "AH: 8s 50c" and vBest, "the AH when it's worth it after the 1 silver deposit and 5% cut (" .. tostring(ah) .. ")")
    alice.items[302] = { name = "Bright Helm", link = "|cff0070dd|Hitem:302::|h[Bright Helm]|h|r", q = 3, ilvl = 24, loc = "INVTYPE_HEAD", sell = 300, classID = 4 }
    db.prices[302] = { p = 99999, t = env.GetServerTime() }
    bump()
    ah, vBest = row(X.PriceLines("item:302"), "AH:")
    check(vBest, "disenchanting is only about the mats' value: a pricey blue sells (" .. tostring(ah) .. ")")
    db.prices[302].p = 500
    db.prices[10978].p = 1500
    bump()
    L = X.PriceLines("item:302")
    de, deBest = row(L, "Disenchant:")
    check(de == "Disenchant: ~15s  · Small Glimmering Shard" and deBest, "and a cheap one is disenchanted (" .. tostring(de) .. ")")

    -- craft: a reagent that makes something worth more than the reagents
    alice.items[6888] = { name = "Herb Baked Egg", link = "|cffffffff|Hitem:6888::|h[Herb Baked Egg]|h|r", q = 1, sell = 6 }
    alice.items[6889] = { name = "Small Egg", link = "|cffffffff|Hitem:6889::|h[Small Egg]|h|r", q = 1, sell = 4 }
    local guid = alice.env.RUIN_API:GetPlayerGUID()
    db.crafters[guid] = { name = "Alice Ash", profs = { Cooking = { "Herb Baked Egg" } }, made = { Cooking = { i = { 6888 }, q = { 1 } } } }
    db.recipeBook.Cooking = db.recipeBook.Cooking or {}
    db.recipeBook.Cooking["Herb Baked Egg"] = { { 6889, 1 }, { 2678, 1 } }
    db.prices[6888] = { p = 5000, t = env.GetServerTime() }
    db.prices[6889] = { p = 100, t = env.GetServerTime() }
    bump()
    L = X.PriceLines("item:6889")
    local cr, crBest = row(L, "Craft:")
    local margin = row(L, "Margin:")
    check(cr and crBest and row(L, "Herb Baked Egg") and margin and margin:find("sells for 50s"), "a reagent says Craft when what it makes sells for more, the sums below it (" .. tostring(cr) .. " / " .. tostring(margin) .. ")")
    db.prices[6888].p = 120
    bump()
    margin = row(X.PriceLines("item:6889"), "Margin:")
    check(margin and margin:find("%+10c") and margin:find("sells for 1s 20c"), "and the margin shrinks with what it sells for (" .. tostring(margin) .. ")")
    -- soulbound: never the auction house; disenchant, craft or vendor
    db.prices[6888].p = 5000
    bump()
    L = plainLines(X.PriceLines("item:6889", 1, true))
    check(L[2] == "Soulbound: can't be auctioned" and row(X.PriceLines("item:6889", 1, true), "Craft:"), "a soulbound reagent still says Craft, never the AH (" .. tostring(L[2]) .. ")")
    for _, l in ipairs(L) do check(not l:find("AH:"), "no AH line for a soulbound item (" .. l .. ")") end
    db.crafters[guid] = nil
    db.prices[302].p = 999999
    bump()
    L = X.PriceLines("item:302", 1, true)
    de, deBest = row(L, "Disenchant:")
    check(de == "Disenchant: ~15s  · Small Glimmering Shard" and deBest and row(L, "Vendor:") and not row(L, "AH:"), "a pricey soulbound blue is disenchanted, not sold on the AH, with the vendor price beside (" .. tostring(de) .. ")")
    db.prices[10978].p = 10
    bump()
    v, vBest = row(X.PriceLines("item:302", 1, true), "Vendor:")
    check(v == "Vendor: 3s" and vBest, "and vendored when the mats are worth less (" .. tostring(v) .. ")")
    alice.items[302].bind = 1
    bump()
    L = X.PriceLines("item:302")
    v, vBest = row(L, "Vendor:")
    check(v == "Vendor: 3s" and vBest and not row(L, "AH:"), "an item that binds when picked up counts as soulbound on its own (" .. tostring(v) .. ")")
    alice.items[302].bind = nil
    db.prices[10978].p = 1500
    bump()
    local realSlots = env.C_Container.GetContainerNumSlots
    env.C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end
    local realCI = env.C_Container.GetContainerItemInfo
    env.C_Container.GetContainerItemInfo = function() return { hyperlink = alice.items[302].link, stackCount = 1, isBound = true } end
    local items = X:SweepBags()
    check(items[1] and items[1].label == "disenchant", "the bag sweep labels a soulbound item Disenchant, not Sell (AH) (" .. tostring(items[1] and items[1].label) .. ")")
    env.C_Container.GetContainerItemInfo, env.C_Container.GetContainerNumSlots = realCI, realSlots
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
