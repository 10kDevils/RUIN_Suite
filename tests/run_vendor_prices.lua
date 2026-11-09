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

    -- recipe costs use the cheaper one
    local function strip(t) return (t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
    check(strip(X.CraftText({ { 2678, 2 } })) == "20c/craft", "Price per Craft uses the vendor price when it's cheaper (" .. strip(X.CraftText({ { 2678, 2 } })) .. ")")

    -- shared with RUIN when the window closes
    env.UnitName = realUnitName
    Server.fire(alice, "MERCHANT_CLOSED")
    Server:Advance(20)
    local cv = cara.env.RUIN_ExchangeDB.vendor
    check(cv and cv[2678] and cv[2678].p == 10 and cv[2678].by == "Tharynn Bouden", "closing the merchant shares its prices with RUIN")

    errorsSoFar("vendor prices")
end
