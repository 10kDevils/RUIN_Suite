-- Core 0.5.3: anything with the down arrow opens a list (W.Cycle included),
-- long lists scroll, and the hand-made pickers (Codex spec, Exchange
-- profession, Muster event, Pathfinder route) open lists too.
local alice, check, errorsSoFar = T.alice, T.check, T.errorsSoFar

print("Dropdowns: an arrow means a list")
do
    local W = alice.ns.Widgets
    local page = alice.env.CreateFrame("Frame", nil, alice.env.UIParent)
    local picked = "B"
    local c = W.Cycle(page, 120, { "A", "B", "C" }, function() return picked end, function(v) picked = v end, "Pick: ")
    check(c:GetText() == "Pick: B", "a Cycle shows its value")
    c._scripts.OnClick(c, "LeftButton")
    check(picked == "B" and c.menu._shown ~= false and c.items[3] and c.items[3]:GetText() == "C", "clicking it opens the list instead of jumping to the next choice")
    c.items[3]._scripts.OnClick(c.items[3])
    check(picked == "C" and c:GetText() == "Pick: C", "picking from the list sets it and closes the list")
    check(type(c.Refresh) == "function", "Refresh still works with a dot or a colon")
    c.Refresh(); c:Refresh()

    -- a long list scrolls, starting with the current choice in view
    local many = {}
    for i = 1, 30 do many[i] = "Route " .. i end
    local cur = "Route 25"
    local d = W.Dropdown(page, 160, many, function() return cur end, function(v) cur = v end)
    d:Open()
    local shown = 0
    for _, it in ipairs(d.items) do if it._shown ~= false then shown = shown + 1 end end
    local hasCurrent = false
    for i = 1, 14 do if d.items[i] and d.items[i]:GetText() == "Route 25" then hasCurrent = true end end
    check(#d.items == 14 and hasCurrent, "a 30-entry list shows 14 at a time, with the current one in view")
    check(d.menu.more:GetText():find("of 30", 1, true), "and says there's more to scroll to")
    local first = d.items[1]:GetText()
    d.menu._scripts.OnMouseWheel(d.menu, 1)
    check(d.items[1]:GetText() ~= first, "the mouse wheel scrolls it")

    -- the hand-made pickers
    local R = alice.env.RUIN_API
    R:OpenTab("Pathfinder")
    T.openAllSubTabs(alice, "Pathfinder")
    local pf = R:GetModule("Pathfinder")
    local pick = pf.UI and pf.UI.pick
    if pick then
        pick._scripts.OnClick(pick, "LeftButton")
        check(pick.items and pick.items[1] and pick.items[1]:GetText() ~= "", "Pathfinder's route picker opens a list of routes")
        local want = pick.items[2] and pick.items[2]:GetText()
        if pick.items[2] then pick.items[2]._scripts.OnClick(pick.items[2]) end
        check(want == nil or pick:GetText() == want, "and picking one shows it")
    else
        check(false, "Pathfinder's route picker is there")
    end
    page:Hide()
    errorsSoFar("dropdowns")
end
