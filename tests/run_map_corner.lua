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
