-- Codex marks the best quest reward for you (RewardPick). Runs inside run_features.lua.
local alice, check, errorsSoFar = T.alice, T.check, T.errorsSoFar

print("Codex: best quest reward")
do
    local env = alice.env
    local cx = env.RUIN_API:GetModule("Codex")
    local RP = alice.mns.RUIN_Codex.RewardPick
    check(RP and RP.Weigh, "Codex has the reward picker")
    local saved = { n = env.GetNumQuestChoices, link = env.GetQuestItemLink, info = env.GetItemInfo, cmp = cx.Compare, use = cx.CanUse,
                    frame = env.QuestInfoRewardsFrame }
    local links = { "|cff1eff00|Hitem:9001::|h[Sturdy Belt]|h|r", "|cff1eff00|Hitem:9002::|h[Fine Boots]|h|r", "|cff1eff00|Hitem:9003::|h[Plate Helm]|h|r" }
    local pct = { [9001] = 4, [9002] = 18, [9003] = 50 }
    local price = { [9001] = 120, [9002] = 90, [9003] = 400 }
    env.GetNumQuestChoices = function() return 3 end
    env.GetQuestItemLink = function(_, i) return links[i] end
    env.GetItemInfo = function(l)
        local id = tonumber(tostring(l):match("item:(%d+)"))
        if price[id] then return "x", l, 2, 20, 20, "Armor", "Mail", 1, "INVTYPE_FEET", 0, price[id] end
        return saved.info(l)
    end
    cx.Compare = function(_, l) local id = tonumber(l:match("item:(%d+)")); return pct[id], 8 end
    cx.CanUse = function(id) return id ~= 9003 end         -- a plate helm a mail wearer can't use
    local buttons = {}
    for i = 1, 3 do buttons[i] = env.CreateFrame("Button", nil, env.UIParent) end
    env.QuestInfoRewardsFrame = { RewardButtons = buttons }
    local w = RP.Show()
    check(w and w.best == 2 and math.floor(w.pct) == 18, "the best upgrade you can use is marked (+18% boots, not the plate helm)")
    check(T.chatHas(alice, "Best reward for you"), "and named in chat")
    pct = { [9001] = -5, [9002] = 0, [9003] = 50 }
    w = RP.Show()
    check(w and not w.best and w.sell == 3, "with no upgrade, the one that sells for the most is marked")
    check(T.chatHas(alice, "sells for the most"), "and chat says so")
    env.GetNumQuestChoices = function() return 1 end
    check(RP.Weigh() == nil, "a single reward needs no pick")
    env.GetNumQuestChoices, env.GetQuestItemLink, env.GetItemInfo = saved.n, saved.link, saved.info
    cx.Compare, cx.CanUse, env.QuestInfoRewardsFrame = saved.cmp, saved.use, saved.frame
    errorsSoFar("reward pick")
end
