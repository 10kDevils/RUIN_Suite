-- Exchange 0.5.2: cost per skill point beside each recipe in the profession
-- window, from current RUIN prices.
local alice, check, errorsSoFar = T.alice, T.check, T.errorsSoFar
local Server = Server

print("Cost per point in the profession window")
do
    local env = alice.env
    local X = env.RUIN_API:GetModule("Exchange")
    local db = env.RUIN_ExchangeDB
    local saved = db.prices
    db.prices = { [2589] = { p = 300, t = env.GetServerTime() } }   -- linen cloth 3s

    local function strip(t) return (t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
    db.rskill = {}
    check(strip(X.PointText(0, { { 2589, 2 } })) == "6s/pt", "orange: one craft per point (" .. strip(X.PointText(0, { { 2589, 2 } })) .. ")")
    check(strip(X.PointText(1, { { 2589, 1 } })) == "~4s/pt", "yellow with no color levels known: a 3 in 4 guess, marked ~")
    check(strip(X.PointText(2, { { 2589, 1 } })) == "~12s/pt", "green: a 1 in 4 guess")
    check(strip(X.PointText(3, { { 2589, 1 } })) == "grey", "grey recipes say grey")
    check(strip(X.PointText(0, { { 999999, 1 } })) == "?/pt", "an unpriced reagent shows ?/pt")
    check(strip(X.CraftText({ { 2589, 2 } })) == "6s/craft", "Price per Craft: one craft's reagents")

    -- the Classic rule: chance = (grey - skill) / (grey - yellow)
    X.NoteColor("Tailoring", "Bolt of Linen", 0, 30)
    X.NoteColor("Tailoring", "Bolt of Linen", 1, 50)
    X.NoteColor("Tailoring", "Bolt of Linen", 2, 60)
    X.NoteColor("Tailoring", "Bolt of Linen", 3, 70)
    local c, exact = X.ChanceFor("Tailoring", "Bolt of Linen", 1, 55)
    check(exact and math.abs(c - 0.75) < 0.001, "yellow at 55 (yellow 50, grey 70): 75% (" .. tostring(c) .. ")")
    c = X.ChanceFor("Tailoring", "Bolt of Linen", 2, 65)
    check(math.abs(c - 0.25) < 0.001, "green at 65: 25%")
    check(strip(X.PointText(1, { { 2589, 1 } }, "Tailoring", "Bolt of Linen", 60)) == "6s/pt", "half way to grey: twice the craft price per point, no ~")
    X.NoteColor("Tailoring", "Bolt of Linen", 1, 45)
    check(db.rskill.Tailoring["Bolt of Linen"].y == 45, "a lower yellow sighting moves the yellow level down")
    -- unlearned recipes: the color they'd be at your skill
    check(X.PredictDiff("Tailoring", "Bolt of Linen", 40) == 0 and X.PredictDiff("Tailoring", "Bolt of Linen", 62) == 2
          and X.PredictDiff("Tailoring", "Bolt of Linen", 75) == 3, "an unlearned recipe's color is predicted from the levels seen")
    check(X.PredictDiff("Tailoring", "Unknown Thing", 40) == nil, "and not guessed without them")

    -- the modern window: each recipe row gets a label
    local rows = {}
    for id = 1, 3 do
        local f = env.CreateFrame("Button")
        local data = { recipeInfo = env.C_TradeSkillUI.GetRecipeInfo(id) }
        data.recipeInfo.recipeID = id
        if id == 3 then data.recipeInfo.learned = false; data.recipeInfo.relativeDifficulty = nil end
        f.GetElementData = function() return { GetData = function() return data end } end
        rows[id] = f
    end
    local header = env.CreateFrame("Button")
    header.GetElementData = function() return { GetData = function() return { categoryInfo = {} } end } end
    rows[4] = header
    env.ProfessionsFrame = { CraftingPage = { RecipeList = { ScrollBox = {
        ForEachFrame = function(_, fn) for _, f in ipairs(rows) do fn(f) end end,
    } } } }
    X.HookRecipeCosts()
    check(rows[1].ruinCost and strip(rows[1].ruinCost:GetText()) == "6s/pt", "Flask of the Titans (orange, 2 linen) reads 6s/pt")
    check(rows[2].ruinCost and strip(rows[2].ruinCost:GetText()) == "~4s/pt", "Minor Healing Potion (yellow, levels unknown) reads ~4s/pt (" .. strip(rows[2].ruinCost:GetText()) .. ")")
    check(rows[3].ruinCost and strip(rows[3].ruinCost:GetText()) == "3s/craft", "an unlearned recipe RUIN can't place shows its Price per Craft (" .. strip(rows[3].ruinCost and rows[3].ruinCost:GetText()) .. ")")
    check(not rows[4].ruinCost, "category headers get nothing")
    -- someone in the org saw where Minor Healing Potion turns yellow (100) and grey (140); you're at 120
    X:OnRecipeSkill({ p = "Alchemy", l = { "Minor Healing Potion", 0, 100, 0, 140 } })
    check(strip(rows[2].ruinCost:GetText()) == "6s/pt", "with its levels known the chance is worked out: 50%, so 6s/pt (" .. strip(rows[2].ruinCost:GetText()) .. ")")
    check(strip(rows[3].ruinCost:GetText()) == "6s/pt", "and the unlearned copy now has a Price per Point too")
    db.rskill.Alchemy = nil
    check(X.ShortMoney(1836) == "18s" and X.ShortMoney(36) == "36c" and X.ShortMoney(12050) == "1g 20s" and X.ShortMoney(250000) == "25g",
          "short money: copper drops once there's silver")

    db.prices[2589].p = 100
    X:OnPrices({ t = env.GetServerTime() + 1, l = { 2589, 100 } }, "Cara")
    check(strip(rows[1].ruinCost:GetText()) == "2s/pt", "new prices repaint the open window")

    env.SlashCmdList.RUINEXCHANGE("costs")
    check(db.pointCosts == false and not rows[1].ruinCost:IsShown(), "/ex costs hides them")
    env.SlashCmdList.RUINEXCHANGE("costs")
    check(rows[1].ruinCost:IsShown(), "and shows them again")

    -- colors seen are shared with the org
    X.NoteColor("Tailoring", "Linen Cloak", 1, 66)
    X.ShareRecipeSkill()
    Server:Advance(20)
    local ct = T.cara.env.RUIN_ExchangeDB.rskill
    check(ct and ct.Tailoring and ct.Tailoring["Linen Cloak"] and ct.Tailoring["Linen Cloak"].y == 66, "the color levels RUIN sees are shared with the org")

    env.ProfessionsFrame = nil
    db.prices = saved
    errorsSoFar("recipe costs")
end
