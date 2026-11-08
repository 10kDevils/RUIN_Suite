-- Exchange 0.5.3: prices show once they're known. The Leveling page prices
-- its saved recipes from current RUIN prices (not the prices when the
-- profession window was last open), the price list sorts before it cuts to
-- 200, and missing item names are asked for a few at a time.
local alice, check, errorsSoFar = T.alice, T.check, T.errorsSoFar
local Server = Server

print("Exchange shows the prices it has")
do
    local X = alice.env.RUIN_API:GetModule("Exchange")
    local db = alice.env.RUIN_ExchangeDB
    local now = alice.env.GetServerTime()
    local savedPrices, savedPlans = db.prices, db.plans

    -- a plan worked out before anyone had priced the spices
    db.prices = {}
    db.plans = { Cooking = { skill = 29, max = 75, t = now - 7200, list = {
        { name = "Spiced Wolf Meat", diff = 4, cost = 0, missing = 2, perPoint = 0, reagents = { { 2672, 1 }, { 2678, 1 } } },
        { name = "Charred Wolf Meat", diff = 4, cost = 0, missing = 1, perPoint = 0, reagents = { { 2672, 1 } } },
    } } }
    db.prices[2672] = { p = 399, t = now }
    db.prices[2678] = { p = 11, t = now }
    local live = X.LivePlan(db.plans.Cooking)
    local spiced, charred
    for _, r in ipairs(live) do if r.name == "Spiced Wolf Meat" then spiced = r else charred = r end end
    check(spiced and spiced.missing == 0 and spiced.cost == 410, "prices that arrived later count (" .. tostring(spiced and spiced.cost) .. ")")
    check(charred and charred.missing == 0 and charred.cost == 399, "for every saved recipe")
    check(live[1].name == "Charred Wolf Meat", "and the cheapest per point leads")

    alice.env.RUIN_API:OpenTab("Exchange")
    T.openAllSubTabs(alice, "Exchange")
    local ui = X.UI
    local txt = ui.levelInfo:GetText() or ""
    check(txt:find("current RUIN prices", 1, true), "the page says the costs are current")

    -- thousands of prices: the newest show, not a random 200
    db.prices = {}
    for i = 1, 600 do db.prices[100000 + i] = { p = i, t = now - 1000 + i } end
    db.prices[2589] = { p = 50, t = now + 5 }
    local rows = X.SearchRows("", nil, "Prices")
    check(#rows == 200, "200 rows (" .. #rows .. ")")
    check(rows[1].t == now + 5 and rows[2].t == now - 400, "newest first, from all of them")

    db.prices, db.plans = savedPrices, savedPlans
    errorsSoFar("exchange display")
end
