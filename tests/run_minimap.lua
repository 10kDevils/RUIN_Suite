-- Pathfinder 0.7.2: the minimap's shape and style, and the tracker docked to it.
local alice, check, errorsSoFar = T.alice, T.check, T.errorsSoFar

print("Pathfinder: minimap shape, style and tracker dock")
do
    local env = alice.env
    local mm = alice.mns.RUIN_Pathfinder.Minimap
    local m = env.Minimap
    local mask
    m.SetMaskTexture = function(_, t) mask = t end
    env.MinimapBorder = env.CreateFrame("Frame")
    env.MinimapZoomIn = env.CreateFrame("Button")
    local alpha = {}
    env.MinimapBorder.SetAlpha = function(_, a) alpha.border = a end
    env.MinimapBorder.GetAlpha = function() return 1 end
    env.MinimapZoomIn.SetAlpha = function(_, a) alpha.zoom = a end
    env.MinimapZoomIn.GetAlpha = function() return 1 end
    check(mm.Shape() == "round" and mm.Style() == "blizzard", "starts as the game's round minimap")
    mm.SetStyle("pathfinder"); mm.SetStyle("blizzard")
    check(mask == nil, "a round map's mask is the game's own: RUIN never replaces it")
    check(#mm.DockChoices() == 5, "a round minimap: off, above, below and the two sides")

    mm.SetShape("square")
    check(mask and mask:find("WHITE8X8", 1, true) and env.GetMinimapShape and env.GetMinimapShape() == "SQUARE",
        "square: a square mask, and other addons are told the minimap is square")
    check(alpha.border == 0, "the game's round border is hidden on a square map")
    check(#mm.DockChoices() == 13, "a square minimap: both ends of every edge too")

    mm.SetStyle("pathfinder")
    check(env.RUIN_PathfinderMinimapDeco and env.RUIN_PathfinderMinimapDeco:IsShown(), "Pathfinder's style draws its own edge")
    check(alpha.zoom == 0 and m:GetScript("OnMouseWheel") ~= nil, "and the + / - buttons give way to mouse-wheel zoom")

    -- the tracker docks to a spot and grows away from it
    local pf = env.RUIN_API:GetModule("Pathfinder")
    local tr = env.RUIN_PathfinderTracker
    if not tr then pf.UpdateTracker(); tr = env.RUIN_PathfinderTracker end
    check(tr ~= nil, "the tracker is there to dock")
    if tr then
        local pt
        local real = tr.SetPoint
        tr.SetPoint = function(self, a, b, c, d, e) pt = { a, b, c, d, e }; return real(self, a, b, c, d, e) end
        mm.SetDock("topleft")
        check(pt and pt[1] == "BOTTOMLEFT" and pt[2] == m and pt[3] == "TOPLEFT" and pt[5] > 0, "above, left edge: it sits on the map's top and grows up")
        mm.SetDock("left")
        check(pt and pt[1] == "RIGHT" and pt[3] == "LEFT" and pt[4] < 0 and mm.Grow() == "left", "left side: it grows left")
        mm.SetDock("bottomright")
        check(pt and pt[1] == "TOPRIGHT" and pt[3] == "BOTTOMRIGHT" and pt[5] < 0 and mm.Grow() == "down", "below, right edge: it grows down")
        mm.SetDock("righttop")
        check(pt and pt[1] == "TOPLEFT" and pt[3] == "TOPRIGHT" and mm.Grow() == "right", "right side, top: it grows right")
        -- round again: a corner spot moves to the nearest side
        mm.SetShape("round")
        check(mm.Dock() == "right" and pt[1] == "LEFT" and pt[3] == "RIGHT", "back to round, the dock moves to the nearest round spot")
        check(mask and mask:find("CircleMask", 1, true) and env.GetMinimapShape == nil, "and the round mask comes back")
        -- dragging it off frees it
        tr.justMoved = true
        tr._scripts.OnMouseUp(tr, "LeftButton")
        tr.justMoved = nil
        check(mm.Dock() == nil, "dragging the tracker off the minimap undocks it")
    end
    mm.SetStyle("blizzard")
    check(alpha.border == 1 and alpha.zoom == 1 and not env.RUIN_PathfinderMinimapDeco:IsShown(), "the game's look comes back as it was")
    env.SlashCmdList.RUINPATH("minimap square")
    check(mm.Shape() == "square", "/path minimap square")
    env.SlashCmdList.RUINPATH("dock top")
    check(mm.Dock() == "top", "/path dock top")
    env.SlashCmdList.RUINPATH("dock off"); env.SlashCmdList.RUINPATH("minimap round")
    check(mm.Dock() == nil and mm.Shape() == "round", "and back")
    env.RUIN_API:OpenTab("Pathfinder")
    T.openAllSubTabs(alice, "Pathfinder")
    errorsSoFar("minimap")
end
