-- Exchange 0.5.2: the modern auction house. Prices come from a full scan
-- (C_AuctionHouse.ReplicateItems, one per 15 minutes, started by itself
-- when the auction house opens) and from clicking into an item, not only
-- from the browse list.
local alice, cara, check, errorsSoFar = T.alice, T.cara, T.check, T.errorsSoFar
local Server = Server

print("Auction house full scan")
do
    local env = cara.env
    local db = env.RUIN_ExchangeDB
    local listings = {          -- count, buyout, item id
        { 5, 5000, 2770 },      -- copper ore 1000 each
        { 1, 900, 2770 },       -- cheaper single
        { 20, 40000, 2589 },    -- linen 2000 each
        { 1, 0, 4306 },         -- bid only: no price
        { 1, 123456, 7000 },
    }
    local replicated = 0
    local real = env.C_AuctionHouse
    env.C_AuctionHouse = setmetatable({
        ReplicateItems = function() replicated = replicated + 1 end,
        GetNumReplicateItems = function() return #listings end,
        GetReplicateItemInfo = function(i)
            local l = listings[i + 1]
            if not l then return nil end
            return "x", 1, l[1], 1, true, 1, "", 0, 0, l[2], 0, false, nil, "Seller", nil, 0, l[3], true
        end,
        GetCommoditySearchResultInfo = function(id, i) return i == 1 and { unitPrice = 777 } or nil end,
        GetNumItemSearchResults = function() return 3 end,
        GetItemSearchResultInfo = function(_, i)
            return ({ { buyoutAmount = 5000, quantity = 1 }, { buyoutAmount = 3000, quantity = 1 }, { quantity = 1 } })[i]
        end,
    }, { __index = real })
    db.lastFullScan = nil

    env.SlashCmdList.RUINEXCHANGE("scan")
    check(replicated == 0, "no scan with the auction house closed")

    Server.fire(cara, "AUCTION_HOUSE_SHOW")
    Server:Advance(2)
    check(replicated == 1, "opening the auction house starts a full scan by itself")
    Server.fire(cara, "REPLICATE_ITEM_LIST_UPDATE")
    Server:Advance(1)
    check(db.prices[2770] and db.prices[2770].p == 900, "the cheapest listing per unit wins (" .. tostring(db.prices[2770] and db.prices[2770].p) .. ")")
    check(db.prices[2589] and db.prices[2589].p == 2000, "stacks are priced per unit")
    check(not db.prices[4306], "bid-only listings give no price")
    check(db.lastFullScan, "the scan time is kept")

    env.SlashCmdList.RUINEXCHANGE("scan")
    Server:Advance(1)
    check(replicated == 1, "a second scan within 15 minutes waits")

    Server.fire(cara, "COMMODITY_SEARCH_RESULTS_UPDATED", 2318)
    check(db.prices[2318] and db.prices[2318].p == 777, "clicking into a commodity reads its cheapest unit price")
    Server.fire(cara, "ITEM_SEARCH_RESULTS_UPDATED", { itemID = 9999 })
    check(db.prices[9999] and db.prices[9999].p == 3000, "clicking into an item reads its cheapest buyout")

    Server.fire(cara, "AUCTION_HOUSE_CLOSED")
    Server:Advance(30)
    local a = alice.env.RUIN_ExchangeDB.prices
    check(a[7000] and a[7000].p == 123456 and a[2318] and a[2318].p == 777, "closing the auction house shares the scan with RUIN")

    -- the items in your bags come first: their prices are written as soon as
    -- they're read (before the rest of the scan) and are always shared
    do
        local X = env.RUIN_API:GetModule("Exchange")
        cara.bag = { { itemID = 2589, stackCount = 5 } }
        local more = {}
        for k = 1, 3200 do more[k] = { 1, 100 + k, 50000 + k } end      -- three chunks of other items
        more[3100] = { 1, 1500, 2589 }                                    -- your linen, late in the list
        listings = more
        db.lastFullScan = nil
        db.prices[2589] = { p = 2000, t = env.GetServerTime() - 99999 }
        Server.fire(cara, "AUCTION_HOUSE_SHOW")
        Server:Advance(2)
        Server.fire(cara, "REPLICATE_ITEM_LIST_UPDATE")
        local seenEarly = db.prices[2589].p == 1500 and not db.prices[53199]
        Server:Advance(1)
        check(X.BagItemIds()[2589], "the scan knows what's in your bags")
        check(db.prices[2589].p == 1500 and db.prices[53199], "your bag items' prices are recorded, then the rest")
        check(seenEarly or db.prices[2589].p == 1500, "yours are kept up to date first")
        Server.fire(cara, "AUCTION_HOUSE_CLOSED")
        Server:Advance(30)
        cara.bag = {}
    end

    env.SlashCmdList.RUINEXCHANGE("autoscan")
    check(db.autoScan == false, "/ex autoscan turns the automatic scan off")
    env.SlashCmdList.RUINEXCHANGE("autoscan")
    env.C_AuctionHouse = real
    errorsSoFar("auction house scan")
end
