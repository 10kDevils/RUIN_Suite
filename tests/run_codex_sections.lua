-- Codex 0.5.3: the Journal's sections fold (quests start folded), and buttons
-- that open another addon wear that addon's color. Runs after the other
-- run_features_*.lua files and shares T.
local alice, check, errorsSoFar = T.alice, T.check, T.errorsSoFar
local here = T.here or "."
local fakeQuestieDB = dofile(here .. "/fake_questiedb.lua")

print("Codex: Journal sections and addon-colored buttons")
do
    local R = alice.env.RUIN_API
    local CX = R:GetModule("Codex")
    local dbC = alice.env.RUIN_CodexDB
    local undo = fakeQuestieDB(alice, {})
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
    undo()
    errorsSoFar("codex sections")
end
