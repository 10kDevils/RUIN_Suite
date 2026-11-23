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

    -- Exchange 0.8.5: scanning the whole time the auction house is open,
    -- item by item: the reagents of your crafts, then gear you can use, then
    -- everything else; paced, only on the browse list, never over your searches
    do
        local X = env.RUIN_API:GetModule("Exchange")
        local AH = env.C_AuctionHouse
        local sent, ready = {}, true
        rawset(AH, "MakeItemKey", function(id) return { itemID = id } end)
        rawset(AH, "SendSearchQuery", function(key) sent[#sent + 1] = key.itemID end)
        rawset(AH, "IsThrottledMessageSystemReady", function() return ready end)
        rawset(AH, "SendBrowseQuery", function() end)
        local mode = 1
        env.AuctionHouseFrameDisplayMode = { Buy = 1, ItemBuy = 2 }
        env.AuctionHouseFrame = env.CreateFrame("Frame", "AuctionHouseFrame", env.UIParent)
        env.AuctionHouseFrame.GetDisplayMode = function() return mode end
        env.AuctionHouseFrame:Show()
        check(X.scanButton == nil and X.ShareScan == nil, "no Scan & Share button any more")
        -- what to look for, in order
        db.recipeBook = { Tailoring = { ["Bolt of Linen Cloth"] = { { 2589, 2 } } } }
        db.prices[2589] = { p = 2000, t = 0, by = "Somebody" }       -- an old price: looked at again
        db.prices[8000] = { p = 500, t = 0, by = "Somebody" }
        db.prices[9001] = { p = 900, t = 0, by = "Somebody" }
        local realEquip = env.IsEquippableItem
        env.IsEquippableItem = function(id) return id == 9001 end
        local list, tiers = X.BuildScanQueue()
        check(list[1] == 2589 and tiers[1] >= 1, "your crafts' reagents first")
        local pos9001, pos8000
        for k, id in ipairs(list) do if id == 9001 then pos9001 = k elseif id == 8000 then pos8000 = k end end
        check(pos9001 and pos8000 and pos9001 < pos8000 and tiers[2] >= 1, "then gear you can use, then everything else")
        -- paced, and only while it's allowed
        db.lastFullScan = env.GetServerTime()                        -- no full scan for now
        Server.fire(cara, "AUCTION_HOUSE_SHOW")
        Server:Advance(1.2)
        sent = {}
        Server:Advance(10)
        check(#sent >= 5 and #sent <= 8 and sent[1] == 2589, "it searches item by item, about one every 1.5 seconds, reagents first (" .. #sent .. " in 10 s)")
        mode = 2
        local n = #sent
        Server:Advance(5)
        check(#sent == n, "not while you're looking at an item (only on the browse list)")
        mode = 1
        AH.SendBrowseQuery({})
        n = #sent
        Server:Advance(4)
        check(#sent == n, "a search of yours pauses it")
        Server:Advance(5)
        check(#sent > n, "and it carries on after")
        ready = false
        n = #sent
        Server:Advance(5)
        check(#sent == n, "it waits for the game's query throttle")
        ready = true
        -- what it reads goes to the org, every minute, no cap
        local before = Server.sent
        Server.fire(cara, "COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
        Server:Advance(65)
        check(Server.sent > before, "what it reads goes to the org every minute while it scans")
        Server.fire(cara, "AUCTION_HOUSE_CLOSED")
        n = #sent
        Server:Advance(5)
        check(#sent == n, "and it stops when you close the auction house")
        env.IsEquippableItem = realEquip
        env.AuctionHouseFrame = nil
        db.recipeBook = {}
    end

    env.SlashCmdList.RUINEXCHANGE("autoscan")
    check(db.autoScan == false, "/ex autoscan turns the automatic scan off")
    env.SlashCmdList.RUINEXCHANGE("autoscan")
    env.C_AuctionHouse = real
    errorsSoFar("auction house scan")
end
