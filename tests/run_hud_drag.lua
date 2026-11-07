-- Floating windows (Core 0.5.3): they move the moment the left button goes
-- down, from anywhere on them (the party strip's rows too), and a click badge
-- still tells a click from a drag. Runs after the other run_features_*.lua files.
local alice, check, errorsSoFar = T.alice, T.check, T.errorsSoFar

print("Floating windows: easy to drag")
do
    local W = alice.ns.Widgets
    local store = {}
    local f = W.HudFrame("RUIN_TestHud", "Guild", store, "pos", { "CENTER" })
    local moves, stops, left, top = 0, 0, 100, 200
    f.StartMoving = function() moves = moves + 1 end
    f.StopMovingOrSizing = function() stops = stops + 1 end
    f.GetLeft = function() return left end
    f.GetTop = function() return top end
    f.GetPoint = function() return "TOPLEFT", nil, "BOTTOMLEFT", left, top end
    local row = alice.env.CreateFrame("Frame", nil, f)
    f:DragBy(row)
    row._scripts.OnMouseDown(row, "LeftButton")
    check(moves == 1 and f.moving, "pressing on a row starts moving the window at once, no drag threshold")
    left = 160
    row._scripts.OnMouseUp(row, "LeftButton")
    check(stops == 1 and not f.moving and f.justMoved and store.pos and store.pos.x == 160, "letting go stops it, keeps the spot, and knows it moved")
    f._scripts.OnMouseDown(f, "RightButton")
    check(moves == 1, "only the left button moves it")
    -- a module's own OnMouseUp (a click badge): the watcher still ends the move
    local down = true
    alice.env.IsMouseButtonDown = function() return down end
    f:SetScript("OnMouseUp", function() end)
    f._scripts.OnMouseDown(f, "LeftButton")
    check(f.moving, "moving again")
    down = false
    for _, fr in ipairs(alice.frames) do
        if fr._scripts and fr._scripts.OnUpdate and fr ~= f then pcall(fr._scripts.OnUpdate, fr, 0.016) end
    end
    check(not f.moving and not f.justMoved, "when the button comes up the move ends even if the window's own OnMouseUp was replaced; it didn't move, so it was a click")
    alice.env.IsMouseButtonDown = nil
    f:Hide()
    errorsSoFar("floating windows")
end
