-- Exchange's watch list: Best in Slot pieces from Codex, limits, and alerts from
-- your scans and other members' shared prices. Runs inside run_features.lua.
local alice, cara, check, errorsSoFar = T.alice, T.cara, T.check, T.errorsSoFar

print("Exchange: watch list")
do
    local env = alice.env
    local ex = env.RUIN_API:GetModule("Exchange")
    local Wt = alice.mns.RUIN_Exchange.Watch
    local cx = env.RUIN_API:GetModule("Codex")
    check(Wt and Wt.AddBis, "Exchange has the watch list")
    for id in pairs(env.RUIN_ExchangeDB.watch or {}) do env.RUIN_ExchangeDB.watch[id] = nil end
    -- Best in Slot from Codex (a stand-in list: Codex leaves out what binds on pickup)
    local realBis = cx.BisBuyable
    cx.BisBuyable = function() return { { id = 7001, slot = 1, name = "Helm of Sample" }, { id = 7002, slot = 8, name = "Boots of Sample" } } end
    local n = Wt.AddBis()
    check(n == 2 and Wt.Get(7001) and Wt.Get(7001).from == "Best in Slot", "Add my Best in Slot puts Codex's buyable pieces on the list")
    check(Wt.AddBis() == 0, "adding again adds nothing twice")
    cx.BisBuyable = realBis
    -- a limit, then a price under it from your own scan
    Wt.Add(7001, 50000)
    local before = #alice.chat
    Wt.Seen(7001, 60000, "Alice Ash")
    check(#alice.chat == before and Wt.Get(7001).last == 60000, "over your limit: noted, no alert")
    Wt.Seen(7001, 45000, "Alice Ash")
    check(T.chatHas(alice, "within your limit"), "at or under it: you're told")
    local told = #alice.chat
    Wt.Seen(7001, 40000, "Alice Ash")
    check(#alice.chat == told, "once an hour per item")
    -- a member's shared price counts too
    Wt.Add(7002, nil)
    env.RUIN_ExchangeDB.watch[7002].told = nil
    ex:OnPrices({ l = { 7002, 1234 }, t = env.GetServerTime() }, "Cara Cole")
    check(T.chatHas(alice, "seen by Cara Cole"), "a price another member shares alerts too, saying who saw it")
    -- the slash command
    env.SlashCmdList.RUINEXCHANGE("watch |cff1eff00|Hitem:7003::|h[Ring]|h|r 12")
    check(Wt.Get(7003) and Wt.Get(7003).max == 120000, "/exchange watch <item> <gold> sets the limit")
    Wt.Remove(7003)
    check(Wt.Get(7003) == nil, "and Remove takes it off")
    env.RUIN_API:OpenTab("Exchange")
    T.openAllSubTabs(alice, "Exchange")
    for id in pairs(env.RUIN_ExchangeDB.watch) do env.RUIN_ExchangeDB.watch[id] = nil end
    errorsSoFar("watch list")
end
