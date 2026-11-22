-- Exchange 0.5.2: the modern auction house. Prices come from a full scan
-- (C_AuctionHouse.ReplicateItems, one per 15 minutes, started by itself
-- when the auction house opens) and from clicking into an item, not only
-- from the browse list.
local alice, cara, check, errorsSoFar, chatHas = T.alice, T.cara, T.check, T.errorsSoFar, T.chatHas
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
        -- sorted dearest first, as a player can sort it
        GetNumCommoditySearchResults = function() return 3 end,
        GetCommoditySearchResultInfo = function(id, i) return ({ { unitPrice = 1500 }, { unitPrice = 990 }, { unitPrice = 777 } })[i] end,
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
    check(db.prices[2318] and db.prices[2318].p == 777, "clicking into a commodity reads its cheapest unit price, however the list is sorted")
    Server.fire(cara, "ITEM_SEARCH_RESULTS_UPDATED", { itemID = 9999 })
    check(db.prices[9999] and db.prices[9999].p == 3000, "clicking into an item reads its cheapest buyout")

    -- Exchange 0.8.3: a price you just saw replaces the saved one even when
    -- it's higher (the cheaper listings were bought out)
    db.prices[2772] = { p = 900, t = env.GetServerTime() - 60, by = "Cara Cole" }
    local CH = env.C_AuctionHouse
    local saveBrowse = CH.GetBrowseResults
    rawset(CH, "GetBrowseResults", function() return { { itemKey = { itemID = 2772 }, minPrice = 1400 } } end)
    Server.fire(cara, "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    check(db.prices[2772].p == 1400, "a dearer sighting replaces a low price the auction house no longer has (" .. db.prices[2772].p .. ")")
    rawset(CH, "GetBrowseResults", saveBrowse)
    -- a share from another player that's higher doesn't replace a fresh low price either
    db.prices[2771] = { p = 500, t = env.GetServerTime() - 60, by = "Dana Dusk" }
    cara.env.RUIN_API:GetModule("Exchange"):OnPrices({ t = env.GetServerTime(), l = { 2771, 2500 } }, "Eve Ember")
    check(db.prices[2771].p == 500, "nor does a higher price someone else shares")
    cara.env.RUIN_API:GetModule("Exchange"):OnPrices({ t = env.GetServerTime(), l = { 2771, 300 } }, "Eve Ember")
    check(db.prices[2771].p == 300, "a lower one does")
    -- what you saw yourself isn't replaced by someone else's share, and a wild price is ignored
    db.prices[2773] = { p = 500, t = env.GetServerTime() - 60, by = env.UnitName("player") }
    cara.env.RUIN_API:GetModule("Exchange"):OnPrices({ t = env.GetServerTime(), l = { 2773, 450 } }, "Eve Ember")
    check(db.prices[2773].p == 500, "a share doesn't replace a price you saw yourself lately")
    db.prices[2774] = { p = 5000, t = env.GetServerTime() - 600, by = "Dana Dusk" }
    cara.env.RUIN_API:GetModule("Exchange"):OnPrices({ t = env.GetServerTime(), l = { 2774, 1 } }, "Eve Ember")
    check(db.prices[2774].p == 5000, "a price far below a recent one (a prank) is ignored")

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

    -- Exchange 0.8.5: a button on the auction house scans the whole of it and
    -- shares every price with the org right away
    do
        local X = env.RUIN_API:GetModule("Exchange")
        env.AuctionHouseFrame = env.CreateFrame("Frame", "AuctionHouseFrame", env.UIParent)
        listings = {}
        for k = 1, 130 do listings[k] = { 1, 1000 + k, 60000 + k } end
        db.lastFullScan = nil
        db.autoScan = false                     -- the button does it here, not the automatic scan
        Server.fire(cara, "AUCTION_HOUSE_SHOW")
        Server:Advance(2)
        local b = X.scanButton
        check(b and b:GetText() == "Scan & Share", "the auction house has a Scan & Share button")
        local before = replicated
        b:GetScript("OnClick")(b, "LeftButton")
        check(replicated == before + 1 and X.ScanState() == "scanning", "clicking it starts a full scan")
        Server.fire(cara, "REPLICATE_ITEM_LIST_UPDATE")
        Server:Advance(1)
        check(chatHas(cara, "Sharing 130 prices with the org"), "when it's done, every price goes to the org")
        Server:Advance(20)
        local a = alice.env.RUIN_ExchangeDB.prices
        check(a[60001] and a[60001].p == 1001 and a[60130] and a[60130].p == 1130, "and arrives for org members (all 130, in batches)")
        X.UpdateScanButton()
        check(X.ScanState() == "wait" and b:GetText():find("Next scan", 1, true), "then it waits for the game's 15 minutes")
        -- the automatic scan on opening counts: the button shares it
        db.sharedScan = nil
        X.UpdateScanButton()
        check(X.ScanState() == "share" and b:GetText() == "Share Prices", "a scan not yet shared can be shared with the button")
        local sent = Server.sent
        b:GetScript("OnClick")(b, "LeftButton")
        Server:Advance(20)
        check(Server.sent > sent and X.ScanState() == "wait", "which shares it")
        Server.fire(cara, "AUCTION_HOUSE_CLOSED")
        Server:Advance(5)
        db.autoScan = nil
        env.AuctionHouseFrame = nil
    end

    env.SlashCmdList.RUINEXCHANGE("autoscan")
    check(db.autoScan == false, "/ex autoscan turns the automatic scan off")
    env.SlashCmdList.RUINEXCHANGE("autoscan")
    env.C_AuctionHouse = real
    errorsSoFar("auction house scan")
end
