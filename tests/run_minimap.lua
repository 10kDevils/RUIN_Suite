-- Pathfinder: the minimap's style, the bar above it, and the tracker docked to it.
local alice, check, errorsSoFar = T.alice, T.check, T.errorsSoFar

print("Pathfinder: minimap style and bar")
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
    check(mm.SHAPES == nil and mm.SetShape == nil, "there is no square map setting")

    mm.SetStyle("pathfinder")
    check(mask == nil, "the game's round mask is never replaced")
    check(env.RUIN_PathfinderMinimapDeco and env.RUIN_PathfinderMinimapDeco:IsShown(), "Pathfinder's style draws its own ring")
    check(alpha.border == 0 and alpha.zoom == 0 and m:GetScript("OnMouseWheel") ~= nil, "the game's border and + / - buttons give way to mouse-wheel zoom")
    check(math.abs(mscale * 140 - (200 - 44)) < 0.01 and mpt and mpt[1] == "CENTER" and mpt[2] == box,
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
    check(mm.Coords() == "42.1, 66.3" and tostring(env.RUIN_PathfinderMinimapBar.zone:GetText()):find("42.1, 66.3", 1, true),
        "your coordinates sit beside the zone name")
    check(strayAlpha == 0, "coordinates printed by the map elsewhere give way to the foot's")

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
    env.SlashCmdList.RUINPATH("minimap debug")
    check(T.chatHas(alice, "RUIN is hiding"), "/path minimap debug lists what's around the minimap")
    -- the looks: RUIN's gold and each module's color
    env.SlashCmdList.RUINPATH("minimap codex")
    local L = alice.mns.RUIN_Pathfinder.Looks
    check(mm.Style() == "codex" and mm.Scheme().color == L.Scheme("codex").color, "/path minimap codex: the minimap in Codex's colors")
    check(L.Scheme("ruin").accent[1] == 0.90 and L.Scheme("ruin").accent[2] == 0.72, "RUIN's look wears the waypoint's gold")
    check(#mm.STYLES == 8 and mm.STYLES[2] == "ruin" and mm.STYLES[3] == "core" and mm.STYLES[8] == "exchange", "the looks, in order: Blizzard, RUIN, Blue & Gold, Pathfinder, Finder, Muster, Codex, Exchange")
    env.SlashCmdList.RUINPATH("minimap blizzard")
    check(mm.Dock() == nil and mm.Style() == "blizzard", "and back (the tracker no longer docks)")
    local pf = env.RUIN_API:GetModule("Pathfinder")
    check(pf.PinStyle() == "ruin" and pf.SetPinStyle("muster") and pf.PinStyle() == "muster" and pf.SetPinStyle("blizzard") and pf.PinStyle() == "blizzard", "the waypoint's style: RUIN to start, any look, the game's own too")
    pf.SetPinStyle("ruin")
    -- every style at once
    check(pf.SetAllStyles("muster") and mm.Style() == "muster" and pf.TrackerStyle() == "muster" and pf.PinStyle() == "muster"
        and pf.AllStyles() == "muster", "one setting sets every style")
    check(pf.SetTrackerAlpha(0.5) and pf.TrackerAlpha() == 0.5, "the tracker's background opacity is a setting")
    pf.SetTrackerStyle("pathfinder")
    check(pf.AllStyles() == "mixed", "and reads Mixed when they differ")
    pf.SetAllStyles("blizzard")
    check(mm.Style() == "blizzard" and pf.PinStyle() == "blizzard" and pf.TrackerStyle() == "blizzard", "Blizzard gives everything the game's own look")
    check(pf.SetAllAlpha(0.6) and pf.AllAlpha() == 0.6 and mm.Alpha() == 0.6 and pf.TrackerAlpha() == 0.6, "one opacity for everything")
    pf.SetTrackerAlpha(0.9)
    check(pf.AllAlpha() == "mixed", "and Mixed when they differ")
    pf.SetPinStyle("ruin"); pf.SetTrackerAlpha(0.94)
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
    -- its icons: a quest marker, an item button, a collapse button, a check mark
    local poi = env.CreateFrame("Button"); poi._type = "Button"; poi.questID = 101
    poi.GetWidth = function() return 20 end
    local item = env.CreateFrame("Button"); item._type = "Button"; item.icon = item:CreateTexture(); item.itemLink = "x"
    local normal = item:CreateTexture()
    item.GetNormalTexture = function() return normal end
    mod.Header.MinimizeButton = env.CreateFrame("Button"); mod.Header.MinimizeButton._type = "Button"
    local tick = done.Icon:CreateTexture()
    done.Icon = tick
    tick.IsShown = function() return true end
    local tickArt
    tick.SetTexture = function(_, t) tickArt = t end
    env.C_QuestLog.IsComplete = env.C_QuestLog.IsComplete or function() return false end
    local realComplete = env.C_QuestLog.IsComplete
    env.C_QuestLog.IsComplete = function(q) return q == 101 end
    local kids = { [mod] = { block }, [block] = { poi, item, line, done } }
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
    check(poi:GetAlpha() == 0 and poi:IsMouseEnabled() ~= false and ot.KindOf(poi) == "poi", "the quest marker is redrawn flat and still takes clicks")
    check(normal:GetAlpha() == 0 and item:GetAlpha() == 1, "the item button keeps its item and loses the game's frame")
    check(mod.Header.MinimizeButton:GetAlpha() == 0, "the collapse button is redrawn")
    check(type(tickArt) == "string" and tickArt:find("ModernCheck"), "finished objectives get Pathfinder's check")
    check(ot.SetAlpha(0.4) and ot.Alpha() == 0.4, "the panel's opacity is a setting")
    check(mm.SetAlpha(0.6) and mm.Alpha() == 0.6, "and so is the minimap frame's")
    env.SlashCmdList.RUINPATH("objectives blizzard")
    check(ot.Style() == "blizzard" and not back:IsShown() and otf.Header.Background:GetAlpha() == 1 and updated > 0,
        "/path objectives blizzard hands the tracker back to the game")
    check(poi:GetAlpha() == 1 and normal:GetAlpha() == 1 and mod.Header.MinimizeButton:GetAlpha() == 1, "and its own icons")
    env.C_QuestLog.IsComplete = realComplete
    env.ObjectiveTrackerFrame = nil
    errorsSoFar("objective tracker")
end

print("Core: tooltips")
do
    local W = alice.env.RUIN_API.Widgets
    local long = "The game's own look, or Pathfinder's: a panel in the suite's look behind the tracker, headers in Pathfinder's color, quest titles and objectives in the suite's text colors"
    local wrapped = W.Wrap(long)
    local widest, lines = 0, 0
    for line in (wrapped .. "\n"):gmatch("(.-)\n") do lines = lines + 1; widest = math.max(widest, #line) end
    check(lines >= 4 and widest <= W.TIP_WIDTH, "long tooltip text breaks onto short lines")
    check(W.Wrap("Short tip") == "Short tip", "short text stays on one line")
    check(W.Wrap("|cffffffffcolored|r words stay whole") == "|cffffffffcolored|r words stay whole", "color codes don't count toward the width")
    errorsSoFar("tooltips")
end

print("Pathfinder: world map style")
do
    local env = alice.env
    local wm = alice.mns.RUIN_Pathfinder.WorldMap
    check(wm ~= nil, "Pathfinder styles the world map")
    local function fs()
        local f = env.CreateFrame("Frame"):CreateFontString()
        f.rgb = { 1, 0.82, 0 }
        f.SetTextColor = function(self, r, g, b) self.rgb = { r, g, b } end
        f.GetTextColor = function(self) return unpack(self.rgb) end
        return f
    end
    local wmf = env.CreateFrame("Frame")
    wmf.IsVisible = function() return true end
    wmf.BorderFrame = env.CreateFrame("Frame")
    local parchment = wmf.BorderFrame:CreateTexture()
    parchment.GetWidth = function() return 600 end
    parchment.GetHeight = function() return 400 end
    wmf.BorderFrame.TitleContainer = { TitleText = fs() }
    wmf.BorderFrame.CloseButton = env.CreateFrame("Button"); wmf.BorderFrame.CloseButton._type = "Button"
    local qmf = env.CreateFrame("Frame"); qmf.IsVisible = function() return true end
    local scroll = env.CreateFrame("Frame"); scroll.IsVisible = function() return true end
    local contents = env.CreateFrame("Frame"); contents.IsVisible = function() return true end
    scroll.Contents = contents
    local header = env.CreateFrame("Frame"); header.ButtonText = fs()
    header.CollapseButton = env.CreateFrame("Button"); header.CollapseButton._type = "Button"
    local obj = env.CreateFrame("Frame"); obj.Text = fs(); obj.Dash = fs()
    contents.GetChildren = function() return header, obj end
    env.WorldMapFrame, env.QuestMapFrame, env.QuestScrollFrame = wmf, qmf, scroll

    check(wm.Style() == "blizzard", "starts in the game's own look")
    wm.SetStyle("pathfinder")
    local back = env.RUIN_PathfinderWorldMapBack
    local acc = alice.mns.RUIN_Pathfinder.Minimap.Scheme().accent
    check(back and back:IsShown(), "a panel in the suite's look sits behind the map window")
    check(parchment:GetAlpha() == 0, "the game's frame art gives way")
    check(wmf.BorderFrame.TitleContainer.TitleText.rgb[2] == acc[2], "the title takes Pathfinder's color")
    check(wmf.BorderFrame.CloseButton:GetAlpha() == 0, "the close button is drawn flat")
    check(header.ButtonText.rgb[2] == acc[2] and header.CollapseButton:GetAlpha() == 0, "quest log headers in Pathfinder's color, flat collapse buttons")
    check(obj.Text.rgb[1] < 0.7 and obj.Dash.rgb[2] == acc[2], "objectives in the suite's grey with a green dash")
    check(wm.SetAlpha(0.5) and wm.Alpha() == 0.5, "the background's opacity is a setting")
    env.SlashCmdList.RUINPATH("worldmap blizzard")
    check(not back:IsShown() and parchment:GetAlpha() == 1 and wmf.BorderFrame.CloseButton:GetAlpha() == 1
        and wmf.BorderFrame.TitleContainer.TitleText.rgb[2] == 0.82, "/path worldmap blizzard gives the window back")
    env.WorldMapFrame, env.QuestMapFrame, env.QuestScrollFrame = nil, nil, nil
    errorsSoFar("world map")
end
