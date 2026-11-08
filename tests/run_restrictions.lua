-- Core 0.5.3: no "blocked from an action" popup on WoW Forever (it keeps
-- the combat log for Blizzard's UI, like Retail), and no "You're doing that
-- too fast": roster requests and channel joins are spaced out.
local alice, check, errorsSoFar = T.alice, T.check, T.errorsSoFar
local Server = Server

print("Restricted events and server throttles")
do
    local ns, env = alice.ns, alice.env
    check(ns:CanRegisterEvent("COMBAT_LOG_EVENT_UNFILTERED") == true, "a client without Blizzard's restriction system may register the combat log")
    env.C_RestrictedActions = { IsAddOnRestrictionActive = function() return false end }
    check(ns:CanRegisterEvent("COMBAT_LOG_EVENT_UNFILTERED") == false and ns:CanRegisterEvent("MINIMAP_PING") == false,
        "WoW Forever (it has the restriction system) skips the combat log and the other restricted events")
    check(ns:CanRegisterEvent("PLAYER_DEAD") == true and ns:CanRegisterEvent("ENCOUNTER_END") == true, "ordinary events still register")
    check(ns:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", function() end) == false, "and registering one is skipped, so the game never blocks RUIN Core")
    env.C_RestrictedActions = nil

    -- roster requests: one per 15 seconds, the rest merged
    local asked = 0
    local realGI, realIn = env.C_GuildInfo, env.IsInGuild
    env.C_GuildInfo = setmetatable({ GuildRoster = function() asked = asked + 1 end }, { __index = realGI })
    env.IsInGuild = function() return true end
    Server:Advance(40)          -- clear of any request an earlier test made
    asked = 0
    for _ = 1, 6 do ns:RequestRoster() end
    check(asked == 1, "six roster requests in a row send one (" .. asked .. ")")
    Server:Advance(16)
    check(asked == 2, "and the rest go out together once 15 seconds have passed (" .. asked .. ")")
    ns:RequestRoster()
    check(asked == 2, "a request right after waits its turn")

    -- hovering players: the game looks up their guild, which fires
    -- PLAYER_GUILD_UPDATE for them; that must not ask for the roster
    Server:Advance(40)
    asked = 0
    for _ = 1, 10 do Server.fire(alice, "PLAYER_GUILD_UPDATE", "mouseover") end
    check(asked == 0, "hovering players never asks the server for the guild roster (" .. asked .. ")")
    Server.fire(alice, "PLAYER_GUILD_UPDATE", "player")
    check(asked == 1, "your own guild changing still does (" .. asked .. ")")
    env.C_GuildInfo, env.IsInGuild = realGI, realIn
    errorsSoFar("restrictions")
end
