-- RUIN Core: Settings > Customization, the game frames' looks moved from
-- Pathfinder, with Pathfinder's tracker and waypoint sections added to it.
-- Runs inside run_features.lua.
local alice, check = T.alice, T.check

print("Core: Settings > Customization")
do
    local env, ns = alice.env, alice.ns
    local CU = ns.Customize
    check(CU and env.RUIN_API.Looks and env.RUIN_API.Minimap and env.RUIN_API.Objectives and env.RUIN_API.WorldMap,
        "the game frames' looks are Core's")
    check(alice.mns.RUIN_Pathfinder.Minimap == env.RUIN_API.Minimap, "Pathfinder uses Core's")
    ns.UI:SelectSettingsTab("Customization")
    local st = ns.UI.settings.tabs
    st:Select(2)
    local titles = table.concat(CU.titles or {}, ",")
    check(titles == "Game Frames,Tracker,Waypoint,Pathfinder Controls", "the tab holds Game Frames and Pathfinder's sections (" .. titles .. ")")
    local pfNames
    for _, t in ipairs(alice.subtabs) do
        if t.names and t.names[1] == "Quests" then pfNames = table.concat(t.names, ",") end
    end
    check(pfNames == nil or pfNames == "Quests,Guide,Routes,Record", "Pathfinder no longer has its own Customization tab")
    -- one look for everything, the tracker and waypoint included
    local pf = env.RUIN_API:GetModule("Pathfinder")
    local L = env.RUIN_API.Looks
    check(L.SetAllStyles("codex") and L.AllStyles() == "codex" and pf.TrackerStyle() == "codex" and pf.PinStyle() == "codex"
        and env.RUIN_API.WorldMap.Style() == "codex", "All styles reaches the frames, the tracker and the waypoint")
    L.SetAllStyles("blizzard")
    -- the looks set in Pathfinder come along once
    local to = {}
    CU.Migrate(to, { mmStyle = "muster", otAlpha = 0.5, route = "x" })
    check(to.mmStyle == "muster" and to.otAlpha == 0.5 and to.route == nil, "the frame looks you set in Pathfinder carry over")
    local again = { lookFromPathfinder = true }
    CU.Migrate(again, { mmStyle = "muster" })
    check(again.mmStyle == nil, "only once")
    check(env.RUIN_CoreCharDB and env.RUIN_CoreCharDB.lookFromPathfinder, "kept per character in Core")
    st:Select(1)
end
