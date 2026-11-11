-- Codex 0.5.3: the Journal's sections fold (quests start folded), and buttons
-- that open another addon wear that addon's color. Runs after the other
-- run_features_*.lua files and shares T.
local alice, check, errorsSoFar = T.alice, T.check, T.errorsSoFar
local here = T.here or "."
local fakeQuestDB = dofile(here .. "/fake_questdb.lua")

print("Codex: Journal sections and addon-colored buttons")
do
    local R = alice.env.RUIN_API
    local CX = R:GetModule("Codex")
    local dbC = alice.env.RUIN_CodexDB
    local undo = fakeQuestDB(alice, {})
    dbC.collapsed = {}
    local hot = CX:FindDungeon("Hall of Thanes")
    local raw = CX.JournalLines(hot, false)
    local function folded() return CX.FoldLines(raw) end
    local function find(lines, pat)
        for i, l in ipairs(lines) do if l[1]:find(pat, 1, true) then return l, i end end
    end
    local heads = {}
    for _, l in ipairs(raw) do if l.header then heads[#heads + 1] = l.header end end
    check(table.concat(heads, ",") == "quests,loot,trash,general,also", "the page has its sections: quests, loot, trash, General, also looted (" .. table.concat(heads, ",") .. ")")
    local dal = {}
    for _, l in ipairs(CX.JournalLines(CX:FindDungeon("City of Dalaran"), false)) do if l.header then dal[#dal + 1] = l.header end end
    check(table.concat(dal, ","):find("quests,about,loot", 1, true), "attunement, set and notes share an About section (" .. table.concat(dal, ",") .. ")")
    local f = folded()
    local qh = find(f, "Quests for Alliance")
    check(qh and qh.header == "quests" and qh.folded and not find(f, "Restless Spirits"), "quests start folded: the header shows, the quests don't")
    check(find(f, "Faldrim Anvilmar") and find(f, "Bosses and loot"), "the loot section starts open")
    local blank = false
    for _, l in ipairs(f) do if l[1] == " " then blank = true end end
    check(not blank, "spacer lines are gone; the section headers set the parts apart")
    qh.action()
    f = folded()
    check(find(f, "Restless Spirits") and not find(f, "Quests for Alliance").folded and dbC.collapsed.quests == false, "clicking the header opens it, and it stays open")
    find(f, "Bosses and loot").action()
    f = folded()
    check(not find(f, "Faldrim Anvilmar") and dbC.collapsed.loot == true, "any section folds, and stays folded")
    check(find(f, "Loot list:"), "the loot list's source line always shows")
    dbC.collapsed = {}

    -- buttons into another addon wear its color
    R:OpenTab("Codex")
    T.openAllSubTabs(alice, "Codex")
    local THEMES = alice.ns.THEMES
    check(CX.UI.runPost.linkColor == THEMES.Muster.color, "Post in Muster is Muster's orange")
    check(CX.UI.questRoute.linkColor == THEMES.Pathfinder.color, "Quest route is Pathfinder's green")
    local line = find(raw, "Open the quest route in Pathfinder")
    check(line and line[1]:find(alice.ns.Widgets.AddonHex("Pathfinder"), 1, true), "the quest route line is Pathfinder green too")
    -- hover areas: an item row reacts over its name only; plain rows don't take the mouse
    local detail = CX.UI.detail
    for _, row in ipairs(detail.rows) do
        row.SetHitRectInsets = function(self, l, r, t, b2) self._hit = { l, r, t, b2 } end
        row.EnableMouse = function(self, on) self._mouse = on end
    end
    local lines2 = CX.FoldLines(CX.JournalLines(hot, false))
    detail:SetItems(lines2)
    local itemRow, plainRow
    for i, row in ipairs(detail.rows) do
        local l = lines2[i]
        if l and l.link and not itemRow then itemRow = row end
        if l and not (l.header or l.link or l.name or l.quest or l.action or l.tip or l.always) and not plainRow then plainRow = row end
    end
    check(itemRow and itemRow._mouse == true and itemRow._hit and itemRow._hit[2] > 0, "an item row takes the mouse over its name only (inset " .. tostring(itemRow and itemRow._hit and itemRow._hit[2]) .. ")")
    check(plainRow and plainRow._mouse == false, "a line with nothing to show doesn't take the mouse")

    -- the wheel glides
    local sf = detail.frame
    local pos = 0
    sf.GetVerticalScrollRange = function() return 400 end
    sf.GetVerticalScroll = function() return pos end
    sf.SetVerticalScroll = function(_, v) pos = v end
    check(sf.smoothScroll and sf.weave and sf.fadeTop and sf.fadeBottom, "the detail panel scrolls smoothly, with a moving weave and edge fades")
    sf._scripts.OnMouseWheel(sf, -1)
    local glide = sf._scripts.OnUpdate
    check(glide ~= nil and pos == 0, "a wheel turn starts a glide instead of jumping")
    for _ = 1, 30 do if sf._scripts.OnUpdate then sf._scripts.OnUpdate(sf, 0.016) end end
    check(math.abs(pos - 72) < 1 and sf._scripts.OnUpdate == nil, "and settles one step down (" .. pos .. ")")
    undo()
    errorsSoFar("codex sections")
end
