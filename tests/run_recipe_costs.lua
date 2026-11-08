-- Exchange 0.5.2: cost per skill point beside each recipe in the profession
-- window, from current RUIN prices.
local alice, check, errorsSoFar = T.alice, T.check, T.errorsSoFar

print("Cost per point in the profession window")
do
    local env = alice.env
    local X = env.RUIN_API:GetModule("Exchange")
    local db = env.RUIN_ExchangeDB
    local saved = db.prices
    db.prices = { [2589] = { p = 300, t = env.GetServerTime() } }   -- linen cloth 3s

    local function strip(t) return (t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
    check(strip(X.PointText(0, { { 2589, 2 } })) == "6s 00c/pt", "orange: one craft's cost per point (" .. strip(X.PointText(0, { { 2589, 2 } })) .. ")")
    check(strip(X.PointText(1, { { 2589, 1 } })) == "4s 00c/pt", "yellow: divided by a 3 in 4 chance")
    check(strip(X.PointText(2, { { 2589, 1 } })) == "12s 00c/pt", "green: 1 in 4")
    check(X.PointText(3, { { 2589, 1 } }) == nil, "grey recipes show nothing")
    check(strip(X.PointText(0, { { 999999, 1 } })) == "?/pt", "an unpriced reagent shows ?")

    -- the modern window: each recipe row gets a label
    local rows = {}
    for id = 1, 2 do
        local f = env.CreateFrame("Button")
        local data = { recipeInfo = env.C_TradeSkillUI.GetRecipeInfo(id) }
        data.recipeInfo.recipeID = id
        f.GetElementData = function() return { GetData = function() return data end } end
        rows[id] = f
    end
    local header = env.CreateFrame("Button")
    header.GetElementData = function() return { GetData = function() return { categoryInfo = {} } end } end
    rows[3] = header
    env.ProfessionsFrame = { CraftingPage = { RecipeList = { ScrollBox = {
        ForEachFrame = function(_, fn) for _, f in ipairs(rows) do fn(f) end end,
    } } } }
    X.HookRecipeCosts()
    check(rows[1].ruinCost and strip(rows[1].ruinCost:GetText()) == "6s 00c/pt", "Flask of the Titans (orange, 2 linen) reads 6s 00c/pt")
    check(rows[2].ruinCost and strip(rows[2].ruinCost:GetText()) == "4s 00c/pt", "Minor Healing Potion (yellow) reads 4s 00c/pt")
    check(not rows[3].ruinCost, "category headers get nothing")

    db.prices[2589].p = 100
    X:OnPrices({ t = env.GetServerTime() + 1, l = { 2589, 100 } }, "Cara")
    check(strip(rows[1].ruinCost:GetText()) == "2s 00c/pt", "new prices repaint the open window")

    env.SlashCmdList.RUINEXCHANGE("costs")
    check(db.pointCosts == false and not rows[1].ruinCost:IsShown(), "/ex costs hides them")
    env.SlashCmdList.RUINEXCHANGE("costs")
    check(rows[1].ruinCost:IsShown(), "and shows them again")

    env.ProfessionsFrame = nil
    db.prices = saved
    errorsSoFar("recipe costs")
end
