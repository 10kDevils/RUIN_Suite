-- Core 0.5.4: item lookups go out a few at a time, and when the server says
-- "too fast" RUIN names the requests (and addons) just before it.
local alice, check, errorsSoFar = T.alice, T.check, T.errorsSoFar
local Server = Server

print("Too fast: item queue and the watcher")
do
    local ns = alice.ns
    local env = alice.env

    -- the item queue
    for _ = 1, 200 do if ns.Items.Pending() == 0 then break end; Server:Advance(5) end   -- earlier tests' lookups
    Server:Advance(1)
    local sent = 0
    local CI = env.C_Item
    local realReq, realCached = CI.RequestLoadItemDataByID, CI.IsItemDataCachedByID
    CI.RequestLoadItemDataByID = function(id) if id >= 500000 and id <= 500099 then sent = sent + 1 end end
    CI.IsItemDataCachedByID = function() return false end
    for id = 500000, 500099 do ns.Items.Info(id) end
    check(sent <= 8, "a hundred unknown items: only a few asked for at once (" .. sent .. ")")
    Server:Advance(3)
    check(sent > 8 and sent < 100, "the rest follow a few at a time (" .. sent .. " after 3 s)")
    Server:Advance(10)
    check(sent == 100, "and all of them go out in the end (" .. sent .. ")")
    ns.Items.Info(500000)
    Server:Advance(1)
    check(sent == 101, "asking again later asks again")
    CI.RequestLoadItemDataByID, CI.IsItemDataCachedByID = realReq, realCached

    -- the watcher
    local printed = {}
    local realPrint = ns.Print
    ns.Print = function(_, msg) printed[#printed + 1] = msg end
    for _ = 1, 12 do ns.Throttle.Note("C_Item.RequestLoadItemDataByID") end
    ns.Throttle.Note("C_GuildInfo.GuildRoster")
    ns.Throttle.OnError("You're doing that too fast")
    local line = printed[1] or ""
    check(line:find("12× C_Item.RequestLoadItemDataByID", 1, true), "it names what was asked most just before (" .. line .. ")")
    check(line:find("GuildRoster", 1, true), "and the rest")
    ns.Throttle.OnError("Not enough rage")
    check(#printed == 1, "other error messages are ignored")
    ns.Throttle.OnError("You're doing that too fast")
    check(#printed == 1, "it says so at most once every 20 seconds in chat")
    env.SlashCmdList.RUIN("toofast")
    check(#printed >= 3 and ns.db.throttleLog and #ns.db.throttleLog == 2, "/ruin toofast lists the ones it saw")
    ns.Print = realPrint
    errorsSoFar("too fast")
end
