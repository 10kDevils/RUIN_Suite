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
