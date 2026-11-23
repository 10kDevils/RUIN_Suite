-- Census zone marks (Core 0.5.3 / Finder 0.5.1): the winged R alone, in the
-- corner of the zone's own map; on a continent map, on the zone as before.
-- Runs after the other run_features_*.lua files and shares T.
local alice, check, errorsSoFar = T.alice, T.check, T.errorsSoFar
local Server = Server
local here = T.here or "."

print("Map: census marks in the corner")
do
    local R = alice.env.RUIN_API
    local Map = alice.ns.Map
    local B = alice.ns.Brand
    check(B.MARK and B.MARK:find("EmblemMark", 1, true) and B.markAspect > 2, "a map mark: the winged R with no disc or ring")
    local f = io.open((os.getenv("RUIN_CORE_DIR") or (here .. "/../RUIN_Core")) .. "/Media/EmblemMark.tga", "rb")
    local h = f and f:read(18); if f then f:close() end
    local function u16(s, i) return s:byte(i) + s:byte(i + 1) * 256 end
    check(h and h:byte(3) == 2 and u16(h, 13) == 256 and u16(h, 15) == 128 and h:byte(17) == 32,
        "EmblemMark.tga is a 256x128 32-bit TGA")

    -- capture where pins are put
    local points = {}
    local function watch(frame)
        if frame._watched then return end
        frame._watched = true
        frame.SetPoint = function(self, ...) points[self] = { ... } end
        frame.SetSize = function(self, w, h) self._w, self._h = w, h end
        frame.GetWidth = function(self) return self._w or 0 end
    end
    local function draw(mapID)
        alice.worldMapID = mapID
        alice.env.WorldMapFrame._shown = true
        alice.env.WorldMapFrame._scripts.OnShow()
        for _, p in ipairs(Map.cornerPins) do watch(p) end
        for _, p in ipairs(Map.worldPins) do watch(p) end
        alice.env.WorldMapFrame._scripts.OnShow()
    end
    local function find(pool, title)
        for _, p in ipairs(pool) do if p._shown and p.pin and p.pin.title == title then return p end end
    end

    R.Map:SetPin("FinderWhere", "Durotar", { map = 1411, x = 0.5, y = 0.5, icon = B.MARK, plain = true,
        iconCoords = B.markCoords, aspect = B.markAspect, corner = true, label = "3 RUIN", title = "3 RUIN members", worldmap = true })
    draw(1411)
    local c = find(Map.cornerPins, "3 RUIN members")
    check(c and not find(Map.worldPins, "3 RUIN members"), "on the zone's own map the mark is in the corner, not in the middle of the zone")
    local pt = c and points[c]
    check(pt and pt[1] == "BOTTOMRIGHT" and pt[3] == "BOTTOMRIGHT" and pt[4] == -14 and pt[5] == 12, "bottom-right corner of the map")
    check(c and c.label._shown and c.label:GetText() == "3 RUIN", "with the member count beside it")
    check(c and c.art._shown and not c.ring._shown and not c.icon._shown, "the winged R alone: no ring, no round frame")

    draw(1414)
    local w = find(Map.worldPins, "3 RUIN members")
    check(w and not find(Map.cornerPins, "3 RUIN members"), "on the continent map it stays on the zone")
    pt = w and points[w]
    check(pt and pt[1] == "CENTER" and math.abs(pt[4] - 550) < 1 and math.abs(pt[5] + 0.65 * 667) < 1, "at the zone's centre")
    check(w and w.art._shown and not w.ring._shown and not w.label._shown, "the same plain mark, no label")
    check(w and w.zoomTo == 1411 and c and c.zoomTo == nil, "on the continent the mark knows its zone; in the corner it doesn't need to")
    local cornerW, contW = c and c:GetWidth(), w and w:GetWidth()
    check(cornerW and contW and contW < cornerW, "on the continent the mark is smaller, so it covers less of the zone (" .. tostring(contW) .. " vs " .. tostring(cornerW) .. ")")
    local wmf = alice.env.WorldMapFrame
    local went, up
    wmf.SetMapID = function(_, id) went = id end
    wmf.NavigateToParentMap = function() up = true end
    w._scripts.OnMouseUp(w, "LeftButton")
    check(went == 1411, "clicking it opens the zone's map")
    w._scripts.OnMouseUp(w, "RightButton")
    check(up, "right-clicking it zooms out, as anywhere on the map")
    local tipLines = {}
    local GT = alice.env.GameTooltip
    local realAdd = GT.AddLine
    GT.AddLine = function(_, l) tipLines[#tipLines + 1] = l end
    w._scripts.OnEnter(w)
    GT.AddLine = realAdd
    check(table.concat(tipLines, "\n"):find("Click to open", 1, true), "its tooltip says it opens the zone")
    wmf.SetMapID, wmf.NavigateToParentMap = nil, nil

    -- OpenMap's stitched map: the mark stays on its zone, and keeps its size through a zoom
    do
        local env = alice.env
        env.OpenMapAPI = { IsStitched = function() return true end, ArtTopLevel = function() return 3000 end,
            WorldFromMap = function(m, x, y) return x, y end, MapFromWorld = function(m, u, v) return u, v end }
        draw(1411)
        local s1 = find(Map.worldPins, "3 RUIN members")
        check(s1 and not find(Map.cornerPins, "3 RUIN members"), "on OpenMap's stitched map a zone's mark stays on the zone, not in the corner")
        local canvas = alice.worldCanvas
        local scale = 1
        canvas.GetEffectiveScale = function() return scale end
        env.WorldMapFrame.GetEffectiveScale = function() return 1 end
        draw(1411)
        local before = s1 and s1:GetWidth()
        scale = 4                                   -- zoomed in: the canvas is four times bigger on screen
        Map.scaleWatch:GetScript("OnUpdate")(Map.scaleWatch, 0.016)
        local after = s1 and s1:GetWidth()
        check(before and after and math.abs(after * 4 - before) < 0.01, "zooming in redraws it at the same size on screen (" .. tostring(before) .. " -> " .. tostring(after) .. ")")
        scale = 4.001
        local drawn = 0
        local realSize = s1.SetSize
        s1.SetSize = function(self, w, h) drawn = drawn + 1; realSize(self, w, h) end
        Map.scaleWatch:GetScript("OnUpdate")(Map.scaleWatch, 0.016)
        check(drawn == 0, "and doesn't redraw for a hair's change")
        s1.SetSize = realSize
        canvas.GetEffectiveScale, env.WorldMapFrame.GetEffectiveScale = nil, nil
        env.OpenMapAPI = nil
        draw(1411)
        check(find(Map.cornerPins, "3 RUIN members"), "on Blizzard's own map it's back in the corner")
    end

    -- on the map's window (above the zooming canvas): a fixed size on screen
    -- however the canvas is zoomed or swapped, placed at its canvas spot
    do
        local env = alice.env
        local wmf = env.WorldMapFrame
        local view = env.CreateFrame("Frame", nil, wmf)
        view.GetEffectiveScale = function() return 1 end
        view.GetLeft, view.GetRight, view.GetTop, view.GetBottom = function() return 0 end, function() return 1000 end, function() return 700 end, function() return 0 end
        wmf.ScrollContainer = view
        wmf.GetEffectiveScale = function() return 1 end
        local canvas = alice.worldCanvas
        local scale = 2
        canvas.GetEffectiveScale = function() return scale end
        R.Map:SetPin("Test", "quest", { map = 1411, x = 0.5, y = 0.5, title = "Quest mark", plain = true, shadow = true, icon = B.MARK })
        draw(1411)
        local q = find(Map.worldPins, "Quest mark")
        local pt = q and points[q]
        check(q and q.onView, "a mark sits on the map's window, not the canvas that zooms")
        check(q and math.abs(q:GetWidth() - 24) < 0.01 and pt and pt[2] == canvas and math.abs(pt[4] - 0.5 * 1000 * 2) < 0.01,
            "24 across on screen, at its spot on the canvas (in window units: " .. tostring(pt and pt[4]) .. ")")
        scale = 6                                   -- OpenMap zooms in a long way
        Map.scaleWatch:GetScript("OnUpdate")(Map.scaleWatch, 0.016)
        pt = points[q]
        check(math.abs(q:GetWidth() - 24) < 0.01 and math.abs(pt[4] - 0.5 * 1000 * 6) < 0.01, "zoomed in, the same size on screen, moved with its spot")
        -- out of the window: hidden (the window doesn't clip its children)
        q.GetCenter = function() return 3000, 300 end
        Map.CullWorldPins()
        check(q:GetAlpha() == 0, "a mark panned out of the window is hidden")
        q.GetCenter = function() return 500, 300 end
        Map.CullWorldPins()
        check(q:GetAlpha() == 1, "and shows again in it")
        q.GetCenter = nil
        R.Map:RemovePin("Test", "quest")
        wmf.ScrollContainer, wmf.GetEffectiveScale, canvas.GetEffectiveScale = nil, nil, nil
        draw(1411)
    end

    -- marks you can clear: right-click one, or /ruin clearmap for all; the
    -- shadow stays in step with the pin however small it is on the canvas
    do
        local cleared = 0
        R.Map:ClearMarks()      -- start clean: an active route's step mark is clearable too
        R.Map:SetPin("Test", "m1", { map = 1411, x = 0.3, y = 0.3, title = "Mark 1", plain = true, shadow = true, icon = B.MARK,
            clearable = true, onClear = function() cleared = cleared + 1 end })
        R.Map:SetPin("Test", "m2", { map = 1411, x = 0.6, y = 0.6, title = "Mark 2", clearable = true })
        R.Map:SetPin("Test", "keep", { map = 1411, x = 0.7, y = 0.2, title = "Not clearable" })
        draw(1414)
        local m1 = find(Map.worldPins, "Mark 1")
        local shadePts = {}
        m1.shade.SetPoint = function(_, ...) shadePts[#shadePts + 1] = { ... } end
        Map.DressPin(m1, m1.pin, 2.4)
        check(#shadePts == 2 and math.abs(shadePts[1][2] + 0.3) < 1e-6 and math.abs(shadePts[2][3] + 0.4) < 1e-6,
            "the shadow keeps to the pin's size: a tenth-size pin has a tenth-size shadow")
        m1.shade.SetPoint = nil
        local tip = {}
        local GT = alice.env.GameTooltip
        local realAdd = GT.AddLine
        GT.AddLine = function(_, l) tip[#tip + 1] = l end
        m1._scripts.OnEnter(m1)
        GT.AddLine = realAdd
        check(table.concat(tip, "\n"):find("Right-click to clear", 1, true), "a mark you can clear says how")
        m1._scripts.OnMouseUp(m1, "RightButton")
        check(R.Map:GetPins("Test").m1 == nil and cleared == 1, "right-clicking it clears it, and its owner hears")
        alice.env.SlashCmdList.RUIN("clearmap")
        local pins = R.Map:GetPins("Test")
        check(pins.m2 == nil and pins.keep ~= nil and alice.chat[#alice.chat]:find("Cleared 1 map mark", 1, true), "/ruin clearmap clears the rest, and leaves marks that aren't yours to clear")
        R.Map:RemovePin("Test", "keep")
        -- Pathfinder's quest mark clears itself once the quest is picked up or handed in
        local PF = R:GetModule("Pathfinder")
        if PF and PF.DoneWithQuestMark then
            R.Map:SetPin("Pathfinder", "quest", { map = 1411, x = 0.5, y = 0.5, clearable = true, qid = 123, which = "start" })
            PF.DoneWithQuestMark(999, false)
            check(R.Map:GetPins("Pathfinder").quest ~= nil, "another quest leaves Pathfinder's mark alone")
            PF.DoneWithQuestMark(123, false)
            check(R.Map:GetPins("Pathfinder").quest == nil, "picking the quest up clears its pick-up mark")
            R.Map:SetPin("Pathfinder", "quest", { map = 1411, x = 0.5, y = 0.5, clearable = true, qid = 124, which = "objective" })
            PF.DoneWithQuestMark(124, false)
            check(R.Map:GetPins("Pathfinder").quest ~= nil, "an objective mark stays while you do the quest")
            PF.DoneWithQuestMark(124, true)
            check(R.Map:GetPins("Pathfinder").quest == nil, "and clears when you hand it in")
        end
    end

    -- an ordinary pin is unchanged
    R.Map:SetPin("Test", "b", { map = 1411, x = 0.4, y = 0.4, title = "Pin B" })
    draw(1411)
    local o = find(Map.worldPins, "Pin B")
    check(o and o.ring._shown and o.icon._shown and not o.art._shown, "other pins keep their ring")
    R.Map:RemovePin("Test", "b")
    R.Map:ClearPins("FinderWhere")
    alice.env.WorldMapFrame._scripts.OnHide()
    check(not find(Map.cornerPins, "3 RUIN members"), "closing the map hides the corner mark")

    -- Finder's census pins ask for it
    local Fd = alice.mns.RUIN_Finder
    local Where = Fd and Fd.Where
    if Where and Where.UpdatePins then
        local realWhere = R.GetWhere
        R.GetWhere = function() return { zones = { { zone = "Durotar", count = 2, guilds = { ["Briar Fang"] = 2 } } } } end
        local realZone = R.Map.ZoneMapID
        R.Map.ZoneMapID = function(_, z) return z == "Durotar" and 1411 or nil end
        local db = alice.env.RUIN_FinderDB
        local was = db.wherePins
        db.wherePins = true
        Where.UpdatePins()
        local p = R.Map:GetPins("FinderWhere")["Durotar"]
        check(p and p.corner and p.plain and p.icon == B.MARK and p.label == "2 RUIN", "Finder's census pins use the plain mark, in the corner")
        db.wherePins = was
        R.GetWhere = realWhere
        R.Map.ZoneMapID = realZone
        Where.UpdatePins()
    else
        check(false, "Finder's Where is reachable")
    end
    errorsSoFar("census marks")
end
