-- Exchange 0.5.2: Price per Point at a profession trainer, for recipes you
-- haven't learned. The trainer's skill requirement is where the recipe
-- starts orange; reagents come from the profession window, or the trainer's
-- tooltip when RUIN knows the reagent names.
local alice, check, errorsSoFar = T.alice, T.check, T.errorsSoFar

print("Exchange: prices at a trainer")
do
    local env = alice.env
    local X = env.RUIN_API:GetModule("Exchange")
    local db = env.RUIN_ExchangeDB
    local now = env.GetServerTime()
    local function strip(t) return (t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
    db.prices[2677] = { p = 100, t = now }      -- boar ribs 1s
    db.prices[2678] = { p = 20, t = now }       -- mild spices 20c
    db.prices[2589] = { p = 300, t = now }      -- linen 3s
    db.rskill.Cooking = nil
    db.recipeBook.Cooking = { ["Dry Pork Ribs"] = { { 2677, 1 }, { 2678, 1 } }, ["Goblin Deviled Clams"] = { { 2677, 2 } } }
    alice.ns.db.items = alice.ns.db.items or {}
    alice.ns.db.items[2589] = { n = "Linen Cloth", q = 1 }

    local services = {
        { "Dry Pork Ribs", 80 }, { "Goblin Deviled Clams", 125 }, { "Spider Sausage", 90 },
    }
    env.GetNumTrainerServices = function() return #services end
    env.GetTrainerServiceInfo = function(i) return services[i][1], "", "available" end
    env.GetTrainerServiceSkillReq = function(i) return "Cooking", services[i][2], true end
    env.GetProfessions = function() return 1 end
    env.GetProfessionInfo = function() return "Cooking", 1, 95, 150 end
    env.C_TooltipInfo = env.C_TooltipInfo or {}
    env.C_TooltipInfo.GetTrainerService = function(i)
        if i == 3 then return { lines = { { leftText = "Spider Sausage" }, { leftText = "Reagents: Linen Cloth (2)" } } } end
        return { lines = {} }
    end

    local rows = {}
    for i, sv in ipairs(services) do
        local f = env.CreateFrame("Button")
        f.name = f:CreateFontString()
        f.name:SetText(sv[1])
        rows[i] = f
    end
    env.ClassTrainerFrame = env.CreateFrame("Frame")
    env.ClassTrainerFrame:Show()
    env.ClassTrainerFrame.ScrollBox = { ForEachFrame = function(_, fn) for _, f in ipairs(rows) do fn(f) end end }
    X.HookTrainer()

    check(rows[1].ruinCost and strip(rows[1].ruinCost:GetText()) == "1s/craft",
          "an unlearned recipe whose colors RUIN doesn't know shows its Price per Craft (" .. strip(rows[1].ruinCost and rows[1].ruinCost:GetText()) .. ")")
    check(rows[2].ruinCost and strip(rows[2].ruinCost:GetText()) == "2s/craft", "one you can't learn yet too")
    check(rows[3].ruinCost and strip(rows[3].ruinCost:GetText()) == "6s/craft", "reagents read from the trainer's tooltip when the profession window never listed it")
    check(db.rskill.Cooking and db.rskill.Cooking["Dry Pork Ribs"].o == 80, "the skill a recipe needs is noted as where it starts orange")

    -- someone in the org saw Dry Pork Ribs turn yellow at 100 and grey at 120: at 95 it's still orange
    X:OnRecipeSkill({ p = "Cooking", l = { "Dry Pork Ribs", 0, 100, 0, 120 } })
    check(strip(rows[1].ruinCost:GetText()) == "1s/pt", "with its colors known it's priced per point at your skill (" .. strip(rows[1].ruinCost:GetText()) .. ")")
    env.GetProfessionInfo = function() return "Cooking", 1, 110, 150 end
    X.PaintTrainer()
    check(strip(rows[1].ruinCost:GetText()) == "2s/pt", "at 110 it's yellow, half way to grey: twice the craft price per point")
    env.GetProfessionInfo = function() return "Cooking", 1, 125, 150 end
    X.PaintTrainer()
    check(not rows[1].ruinCost:IsShown(), "once it would be grey nothing is shown")

    env.ClassTrainerFrame = nil
    errorsSoFar("trainer costs")
end
