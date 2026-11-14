-- Pathfinder: the minimap's style, the bar above it, and the tracker docked to it.
local alice, check, errorsSoFar = T.alice, T.check, T.errorsSoFar

print("Pathfinder: minimap style, bar and tracker dock")
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
    -- the game's pieces that move onto the bar
    local home = env.CreateFrame("Frame")
    local pieces = {}
    for _, n in ipairs({ "TimeManagerClockButton", "GameTimeFrame", "AddonCompartmentFrame", "MiniMapTracking", "MiniMapMailFrame" }) do
        local f = env.CreateFrame("Button", n, home)
        f._parent = home
        f.SetParent = function(self, p) self._parent = p end
        f.GetParent = function(self) return self._parent end
        f:SetPoint("TOPLEFT", home, "TOPLEFT", 1, 1)
        env[n] = f
        pieces[n] = f
    end

    -- coordinates another addon printed under the map
    local stray = m:CreateFontString(nil, "OVERLAY")
    stray:SetText("8.5, 55.4")
    local strayAlpha = 1
    stray.SetAlpha = function(_, a) strayAlpha = a end
    stray.GetAlpha = function() return strayAlpha end
    local realPos = env.C_Map.GetPlayerMapPosition
    local realBest = env.C_Map.GetBestMapForUnit
    env.C_Map.GetBestMapForUnit = function() return 15 end
    env.C_Map.GetPlayerMapPosition = function() return { x = 0.4213, y = 0.6631 } end

    -- the minimap's Edit Mode box, taller than wide
    local box = env.CreateFrame("Frame")
    box.GetWidth = function() return 200 end
    box.GetHeight = function() return 240 end
    box.GetEffectiveScale = function() return 1 end
    env.MinimapCluster = box
    local holder = env.CreateFrame("Frame")
    holder.GetEffectiveScale = function() return 1 end
    m.GetParent = function() return holder end
    m.GetEffectiveScale = function() return 1 end
    local mscale = 1
    m.SetScale = function(_, v) mscale = v end
    m.GetScale = function() return mscale end
    m.GetWidth = function() return 140 end
    local mpt
    local realMSP = m.SetPoint
    m.SetPoint = function(self, a, b, ...) mpt = { a, b }; return realMSP(self, a, b, ...) end

    check(mm.Style() == "blizzard", "starts as the game's own minimap")
    check(#mm.DockChoices() == 5, "dock spots: off, above, below and the two sides")
    check(mm.SHAPES == nil and mm.SetShape == nil, "there is no square map setting")

    mm.SetStyle("pathfinder")
    check(mask == nil, "the game's round mask is never replaced")
    check(env.RUIN_PathfinderMinimapDeco and env.RUIN_PathfinderMinimapDeco:IsShown(), "Pathfinder's style draws its own ring")
    check(alpha.border == 0 and alpha.zoom == 0 and m:GetScript("OnMouseWheel") ~= nil, "the game's border and + / - buttons give way to mouse-wheel zoom")
    check(math.abs(mscale * 140 - (200 - 38)) < 0.01 and mpt and mpt[1] == "CENTER" and mpt[2] == box,
        "the map grows to fill its Edit Mode box (its shorter side), centered in it")
    local bar = env.RUIN_PathfinderMinimapBar
    check(bar and bar:IsShown() and mm.Bar() == bar, "a flat bar sits above the map")
    local onBar = true
    for n, f in pairs(pieces) do if f:GetParent() == home then onBar = false end end
    check(onBar, "the tracking button, clock, calendar, addon list and mail move into the housing")
    check(pieces.MiniMapTracking:GetAlpha() == 0 and pieces.MiniMapTracking:IsMouseEnabled() ~= false, "the tracking button is drawn flat by Pathfinder and still takes clicks")
    local foot = env.RUIN_PathfinderMinimapFoot
    check(foot and foot:IsShown() and mm.Foot() == foot, "a matching foot sits below the map")
    mm.Tick(true)
    check(mm.Coords() == "42.1, 66.3", "the foot shows your coordinates")
    check(strayAlpha == 0, "coordinates printed by the map elsewhere give way to the foot's")

    -- the tracker docks on the bar above, and grows away from the map elsewhere
    local pf = env.RUIN_API:GetModule("Pathfinder")
    local tr = env.RUIN_PathfinderTracker
    if not tr then pf.UpdateTracker(); tr = env.RUIN_PathfinderTracker end
    check(tr ~= nil, "the tracker is there to dock")
    if tr then
        local pt
        local real = tr.SetPoint
        tr.SetPoint = function(self, a, b, c, d, e) pt = { a, b, c, d, e }; return real(self, a, b, c, d, e) end
        mm.SetDock("top")
        check(pt and pt[1] == "BOTTOM" and pt[2] == bar and pt[3] == "TOP" and mm.Grow() == "up", "above: it sits on the bar and grows up")
        mm.SetDock("left")
        check(pt and pt[1] == "RIGHT" and pt[2] == m and pt[3] == "LEFT" and pt[4] < 0 and mm.Grow() == "left", "left side: it grows left")
        mm.SetDock("bottom")
        check(pt and pt[1] == "TOP" and pt[2] == foot and pt[3] == "BOTTOM" and pt[5] < 0 and mm.Grow() == "down", "below: it hangs under the foot and grows down")
        tr.justMoved = true
        tr._scripts.OnMouseUp(tr, "LeftButton")
        tr.justMoved = nil
        check(mm.Dock() == nil, "dragging the tracker off the minimap undocks it")
    end
    -- an old saved spot ("topleft") means its side
    local cdb = env.RUIN_PathfinderCharDB
    if cdb then
        cdb.trackerDock = "lefttop"
        check(mm.Dock() == "left", "a spot saved by an older Pathfinder becomes its side")
        cdb.trackerDock = nil
    end

    -- a rotating map: the N turns with it
    local cvars = { rotateMinimap = "1" }
    local realCVar = env.GetCVar
    env.GetCVar = function(k) if cvars[k] then return cvars[k] end return realCVar and realCVar(k) end
    env.GetPlayerFacing = function() return math.pi / 2 end
    local deco = env.RUIN_PathfinderMinimapDeco
    local np
    local realSP = deco.north.SetPoint
    deco.north.SetPoint = function(self, a, b, c, x, y) np = { x, y }; return realSP(self, a, b, c, x, y) end
    mm.PlaceNorth()
    check(np and np[1] > 10 and math.abs(np[2]) < 1, "facing west, north is on the map's right side")
    cvars.rotateMinimap = "0"
    mm.PlaceNorth()
    check(np and math.abs(np[1]) < 1 and np[2] > 10, "rotation off: north is back on top")
    env.GetCVar = realCVar

    mm.SetStyle("blizzard")
    local back = true
    for _, f in pairs(pieces) do if f:GetParent() ~= home then back = false end end
    check(strayAlpha == 1 and pieces.MiniMapTracking:GetAlpha() == 1, "the other coordinates and the game's own icons come back")
    check(mscale == 1, "and the map its own size")
    env.C_Map.GetPlayerMapPosition = realPos
    env.C_Map.GetBestMapForUnit = realBest
    check(back and alpha.border == 1 and alpha.zoom == 1 and not deco:IsShown() and not bar:IsShown(), "the game's look comes back as it was")
    env.SlashCmdList.RUINPATH("minimap pathfinder")
    check(mm.Style() == "pathfinder", "/path minimap pathfinder")
    env.SlashCmdList.RUINPATH("dock top")
    check(mm.Dock() == "top", "/path dock top")
    env.SlashCmdList.RUINPATH("minimap debug")
    check(T.chatHas(alice, "RUIN is hiding"), "/path minimap debug lists what's around the minimap")
    env.SlashCmdList.RUINPATH("dock off"); env.SlashCmdList.RUINPATH("minimap blizzard")
    check(mm.Dock() == nil and mm.Style() == "blizzard", "and back")
    env.RUIN_API:OpenTab("Pathfinder")
    T.openAllSubTabs(alice, "Pathfinder")
    errorsSoFar("minimap")
end

print("Pathfinder: objective tracker style")
do
    local env = alice.env
    local ot = alice.mns.RUIN_Pathfinder.Objectives
    local mm = alice.mns.RUIN_Pathfinder.Minimap
    check(ot ~= nil, "Pathfinder styles the objective tracker")
    -- a stand-in for the game's tracker: a header, a section, a quest and its lines
    local function fs()
        local f = env.CreateFrame("Frame"):CreateFontString()
        f.SetTextColor = function(self, r, g, b) self.rgb = { r, g, b } end
        return f
    end
    local otf = env.CreateFrame("Frame")
    otf.Header = env.CreateFrame("Frame"); otf.Header.Text = fs(); otf.Header.Background = otf.Header:CreateTexture()
    local mod = env.CreateFrame("Frame")
    mod.Header = env.CreateFrame("Frame"); mod.Header.Text = fs()
    local block = env.CreateFrame("Frame"); block.HeaderText = fs()
    local line = env.CreateFrame("Frame"); line.Text = fs(); line.Dash = fs()
    local done = env.CreateFrame("Frame"); done.Text = fs(); done.Dash = fs(); done.Icon = env.CreateFrame("Frame")
    local kids = { [mod] = { block }, [block] = { line, done } }
    for f, list in pairs(kids) do f.GetChildren = function() return unpack(list) end end
    otf.modules = { mod }
    otf.GetTop = function() return 600 end
    mod.GetBottom = function() return 400 end
    mod.GetHeight = function() return 180 end
    local updated = 0
    otf.Update = function() updated = updated + 1 end
    env.ObjectiveTrackerFrame = otf

    check(ot.Style() == "blizzard", "starts in the game's own look")
    ot.SetStyle("pathfinder")
    local back = env.RUIN_PathfinderObjectivesBack
    check(back and back:IsShown(), "a panel in the suite's look sits behind the tracker")
    local acc = mm.Scheme().accent
    local function is(c, want) return c and math.abs(c[1] - want[1]) < 0.01 and math.abs(c[2] - want[2]) < 0.01 end
    check(is(otf.Header.Text.rgb, acc) and is(mod.Header.Text.rgb, acc), "headers take Pathfinder's color")
    check(otf.Header.Background:GetAlpha() == 0, "the game's header backdrop gives way")
    check(block.HeaderText.rgb and block.HeaderText.rgb[1] > 0.9, "quest titles in the suite's white")
    check(line.Text.rgb and line.Text.rgb[1] < 0.8 and is(line.Dash.rgb, acc), "objectives in its grey, with an accent dash")
    check(done.Text.rgb and done.Text.rgb[2] > done.Text.rgb[1] + 0.2, "finished objectives in green")
    check(ot.SetAlpha(0.4) and ot.Alpha() == 0.4, "the panel's opacity is a setting")
    check(mm.SetAlpha(0.6) and mm.Alpha() == 0.6, "and so is the minimap frame's")
    env.SlashCmdList.RUINPATH("objectives blizzard")
    check(ot.Style() == "blizzard" and not back:IsShown() and otf.Header.Background:GetAlpha() == 1 and updated > 0,
        "/path objectives blizzard hands the tracker back to the game")
    env.ObjectiveTrackerFrame = nil
    errorsSoFar("objective tracker")
end
