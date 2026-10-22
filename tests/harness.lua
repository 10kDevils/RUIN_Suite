-- Minimal WoW client simulator for RUIN Core tests (Lua 5.1).
-- Addon folders sit next to tests/ in the suite repo; override with RUIN_CORE_DIR.
local TEST_DIR = (arg and arg[0] or ""):match("^(.*)/") or "."
local ADDON_DIR = arg[1] or os.getenv("RUIN_CORE_DIR") or (TEST_DIR .. "/../RUIN_Core")
-- Core's files, in the order its TOC loads them.
local FILES = {}
do
    local toc = io.open(ADDON_DIR .. "/RUIN_Core.toc")
    for line in toc:lines() do
        local f = line:match("^%s*([%w_]+%.lua)%s*$")
        if f then FILES[#FILES + 1] = f end
    end
    toc:close()
end

Server = { epoch = os.time(), time = 0, clients = {}, byName = {}, channels = {}, timers = {}, errors = {}, guilds = {},
           sent = 0, maxLen = 0, line = 0 }

local function schedule(t, fn) table.insert(Server.timers, { t = t, fn = fn }) end

local function mockObj()
    local o = { _scripts = {}, _events = {}, _shown = true, _text = "" }
    local methods = {
        SetScript = function(self, k, f) self._scripts[k] = f end,
        GetScript = function(self, k) return self._scripts[k] end,
        RegisterEvent = function(self, e)
            -- Mirror WoW Forever: the Classic auction event does not exist.
            if e == "AUCTION_ITEM_LIST_UPDATE" then
                error('Frame:RegisterEvent(): Attempt to register unknown event "' .. e .. '"')
            end
            self._events[e] = true
        end,
        UnregisterEvent = function(self, e) self._events[e] = nil end,
        CreateFontString = function() return mockObj() end,
        CreateTexture = function() return mockObj() end,
        GetFontString = function(self) self._fs = self._fs or mockObj(); return self._fs end,
        GetStringWidth = function() return 60 end,
        GetStringHeight = function() return 14 end,
        GetChecked = function(self) return self._checked end,
        SetChecked = function(self, v) self._checked = v end,
        SetText = function(self, t) self._text = t end,
        GetText = function(self) return self._text end,
        Show = function(self) self._shown = true; if self._scripts.OnShow then self._scripts.OnShow(self) end end,
        Hide = function(self) self._shown = false end,
        IsShown = function(self) return self._shown end,
        IsVisible = function(self) return self._shown end,
        HookScript = function(self, k, f)
            local prev = self._scripts[k]
            self._scripts[k] = function(...) if prev then prev(...) end f(...) end
        end,
        GetFrameLevel = function() return 1 end,
        GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end,
        GetWidth = function() return 100 end,
        GetHeight = function() return 80 end,
    }
    return setmetatable(o, { __index = function(_, k)
        if methods[k] then return methods[k] end
        if type(k) == "string" and k:match("^%u") then return function() end end
        return nil
    end })
end

local function fire(c, event, ...)
    for _, f in ipairs(c.frames) do
        if f._events[event] and f._scripts.OnEvent then
            local ok, err = pcall(f._scripts.OnEvent, f, event, ...)
            if not ok then table.insert(Server.errors, c.name .. ": " .. tostring(err)) end
        end
    end
end
Server.fire = fire

local function lower(s) return s and s:lower() end

local function deliver(c, ...)
    local args = { ... }
    local n = select("#", ...)
    schedule(Server.time + 0.05, function() fire(c, "CHAT_MSG_ADDON", unpack(args, 1, n)) end)
end

local function route(c, prefix, text, chatType, target)
    assert(#text <= 255, "addon message over 255 bytes: " .. #text)
    assert(not text:find("\0", 1, true), "NUL in addon message")
    Server.sent = Server.sent + 1
    if #text > Server.maxLen then Server.maxLen = #text end
    if chatType == "GUILD" then
        for _, o in ipairs(Server.clients) do
            if o.guild == c.guild then deliver(o, prefix, text, "GUILD", c.name, "", 0, 0, "", 0) end
        end
    elseif chatType == "CHANNEL" then
        local chName = c.joinedById[tonumber(target)]
        assert(chName, c.name .. " sent on a channel it has not joined: " .. tostring(target))
        for _, o in ipairs(Server.clients) do
            local id = o.joined[chName]
            if id then deliver(o, prefix, text, "CHANNEL", c.name, chName, 0, id, chName, 0) end
        end
    elseif chatType == "WHISPER" then
        local o = Server.byName[target]
        if o then deliver(o, prefix, text, "WHISPER", c.name, o.name, 0, 0, "", 0) end
    else
        error("unknown chat type " .. tostring(chatType))
    end
    return 0
end

function Server:NewClient(opts)
    local env = setmetatable({}, { __index = _G })
    local c = { env = env, name = opts.name, guid = opts.guid, guild = opts.guild, rank = opts.rank,
                frames = {}, chat = {}, joined = {}, joinedById = {}, popups = {}, nextChannel = 5 }
    env._G = env
    local function cf()
        local f = mockObj()
        f.AddMessage = function(_, msg) table.insert(c.chat, msg) end
        return f
    end
    for i = 1, 10 do env["ChatFrame" .. i] = cf() end
    env.DEFAULT_CHAT_FRAME = env.ChatFrame1
    env.NUM_CHAT_WINDOWS = 10
    env.UIParent = mockObj()
    env.CreateFrame = function(_, name)
        local f = mockObj()
        table.insert(c.frames, f)
        if name then env[name] = f end
        return f
    end
    if opts.ui then opts.ui.install(env, c) end
    env.C_Timer = {
        After = function(d, fn) schedule(Server.time + d, fn) end,
        NewTicker = function(d, fn)
            local tk = { cancelled = false }
            function tk:Cancel() self.cancelled = true end
            local function run()
                if tk.cancelled then return end
                fn(tk)
                if not tk.cancelled then schedule(Server.time + d, run) end
            end
            schedule(Server.time + d, run)
            return tk
        end,
    }
    env.GetTime = function() return Server.time end
    env.GetServerTime = function() return Server.epoch + math.floor(Server.time) end
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        SendAddonMessage = function(prefix, text, chatType, target) return route(c, prefix, text, chatType, target) end,
    }
    env.Enum = { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, ChannelThrottle = 8 } }
    env.GetChannelName = function(name)
        for chName, id in pairs(c.joined) do
            if lower(chName) == lower(name) then return id, chName end
        end
        return 0
    end
    env.JoinTemporaryChannel = function(name, pw)
        local ch = Server.channels[lower(name)]
        if not ch then ch = { password = pw }; Server.channels[lower(name)] = ch end
        if ch.password ~= pw then
            schedule(Server.time + 0.1, function() fire(c, "CHAT_MSG_CHANNEL_NOTICE", "WRONG_PASSWORD", "", "", "1. " .. name, "", "", 0, 0, name) end)
            return
        end
        if env.GetChannelName(name) == 0 then
            local id = c.nextChannel
            c.nextChannel = c.nextChannel + 1
            c.joined[name] = id
            c.joinedById[id] = name
        end
    end
    -- the game's own channels hold 1-4 unless a test says otherwise
    c.defaultChannels = c.defaultChannels or { [1] = "General", [2] = "Trade", [3] = "LocalDefense", [4] = "LookingForGroup" }
    env.GetChannelList = function()
        local all = {}
        for id, n in pairs(c.defaultChannels) do all[#all + 1] = { id, n } end
        for id, n in pairs(c.joinedById) do all[#all + 1] = { id, n } end
        table.sort(all, function(a, b) return a[1] < b[1] end)
        local out = {}
        for _, e in ipairs(all) do out[#out + 1] = e[1]; out[#out + 1] = e[2]; out[#out + 1] = false end
        return unpack(out)
    end
    env.C_ChatInfo.SwapChatChannelsByChannelIndex = function(a, b)
        local function nameAt(id) return c.defaultChannels[id] and { "d", c.defaultChannels[id] } or (c.joinedById[id] and { "j", c.joinedById[id] }) end
        local na, nb = nameAt(a), nameAt(b)
        c.defaultChannels[a], c.defaultChannels[b], c.joinedById[a], c.joinedById[b] = nil, nil, nil, nil
        local function put(id, e)
            if not e then return end
            if e[1] == "d" then c.defaultChannels[id] = e[2] else c.joinedById[id] = e[2]; c.joined[e[2]] = id end
        end
        put(b, na); put(a, nb)
        c.swaps = (c.swaps or 0) + 1
    end
    env.LeaveChannelByName = function(name)
        for chName, id in pairs(c.joined) do
            if lower(chName) == lower(name) then c.joined[chName] = nil; c.joinedById[id] = nil end
        end
    end
    env.IsInGuild = function() return c.guild ~= nil end
    env.GetGuildInfo = function(u)
        if u == "target" then return c.targetGuild end
        return c.guild, "Rank" .. tostring(c.rank), c.rank
    end
    local function roster() return Server.guilds[c.guild] or {} end
    env.GetNumGuildMembers = function() return #roster() end
    env.GetGuildRosterInfo = function(i)
        local m = roster()[i]
        if not m then return nil end
        local online = m.online ~= false
        return m.name, m.rankName or ("Rank" .. tostring(m.rank)), m.rank, m.level or 20, m.className or "Warrior", m.zone or "Zone",
               m.note or "", m.officerNote or "", online, 0, m.class or "WARRIOR", 0, 0, false, false, 0, m.guid
    end
    env.C_GuildInfo = { GuildRoster = function() schedule(Server.time + 0.1, function() fire(c, "GUILD_ROSTER_UPDATE") end) end }
    env.GetGuildRosterLastOnline = function(i) local m = roster()[i]; if m and m.lastOnline then return unpack(m.lastOnline) end end
    env.SendChatMessage = function(text, chatType)
        c.sentChat = c.sentChat or {}
        table.insert(c.sentChat, { text, chatType })
        if chatType == "GUILD" and c.guild then
            local me
            for _, m in ipairs(roster()) do if m.guid == c.guid then me = m end end
            Server:GuildSay(c.guild, me or { name = c.name, guid = c.guid }, text)
        end
    end
    env.UnitGUID = function() return c.guid end
    env.UnitName = function(u) if u == "target" then return c.targetName or c.target end return c.name end
    env.UnitIsDeadOrGhost = function(u) return u == "target" and c.targetDead or false end
    env.UnitIsFriend = function(a, b) return c.targetFriendly or false end
    env.UnitClass = function() return "Warrior", "WARRIOR" end
    env.UnitLevel = function() return 20 end
    env.UnitExists = function(u) return u == "target" and c.target ~= nil end
    env.UnitIsPlayer = function() return true end
    env.GetUnitName = function() return c.target end
    env.StaticPopupDialogs = {}
    env.StaticPopup_Show = function(which, a, b, data) table.insert(c.popups, { which = which, a = a, b = b, data = data }) end
    env.ChatTypeInfo = { GUILD = { r = 0.25, g = 1, b = 0.25 }, OFFICER = { r = 0.25, g = 0.75, b = 0.25 } }
    env.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
    env.ChatFrame_AddMessageEventFilter = function() end
    env.ChatFrame_RemoveChannel = function() end
    env.UISpecialFrames = {}
    env.tinsert = table.insert
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    env.SlashCmdList = {}
    env.GetAddOnMetadata = function() return opts.version or "0.1.0" end
    env.geterrorhandler = function()
        return function(e) table.insert(Server.errors, c.name .. ": " .. tostring(e)) end
    end
    env.BackdropTemplateMixin = {}
    env.ChatFontNormal = {}
    env.ACCEPT, env.DECLINE, env.OKAY, env.CANCEL = "Accept", "Decline", "OK", "Cancel"
    env.time = os.time
    env.date = os.date
    env.print = function(...) end

    -- Map, minimap and tooltip APIs used by Core's map pins and the modules
    env.hooksecurefunc = function(t, name, fn)
        if type(t) == "string" then t, name, fn = env, t, name end
        local orig = t[name]
        t[name] = function(...) local r = { orig(...) } fn(...) return unpack(r) end
    end
    env.GetCVar = function(k) return c.cvars and c.cvars[k] or "0" end
    env.Minimap = mockObj()
    env.Minimap.GetWidth = function() return 140 end
    env.C_Minimap = { GetViewRadius = function() return 200 end }
    env.WorldMapFrame = mockObj()
    env.WorldMapFrame._shown = false
    c.worldCanvas = mockObj()
    c.worldCanvas.GetWidth = function() return 1000 end
    c.worldCanvas.GetHeight = function() return 667 end
    env.WorldMapFrame.GetCanvas = function() return c.worldCanvas end
    env.WorldMapFrame.GetMapID = function() return c.worldMapID or 1411 end
    env.WorldMapFrame.OnMapChanged = function() end
    c.tooltip = { lines = {} }
    env.GameTooltip = mockObj()
    env.GameTooltip.AddLine = function(_, l) table.insert(c.tooltip.lines, l) end
    env.GameTooltip.SetHyperlink = function(_, l) c.tooltip.link = l end
    env.CLASS_ICON_TCOORDS = { WARRIOR = { 0, 0.25, 0, 0.25 } }

    -- Extra APIs used by the modules
    c.pos = opts.pos or { map = 1411, x = 0.5, y = 0.5 }
    env.C_Map = {
        GetBestMapForUnit = function() return c.pos.map end,
        GetPlayerMapPosition = function()
            return { GetXY = function() return c.pos.x, c.pos.y end }
        end,
        GetMapWorldSize = function() return 4000, 2700 end,
        GetMapInfo = function(map)
            local names = { [1411] = "Durotar", [1414] = "Kalimdor", [1429] = "Elwynn Forest", [1415] = "Eastern Kingdoms" }
            local parents = { [1411] = 1414, [1429] = 1415 }
            if not names[map] then return nil end
            return { mapID = map, name = names[map], parentMapID = parents[map] }
        end,
        GetMapRectOnMap = function(child, parent)
            if child == 1411 and parent == 1414 then return 0.5, 0.6, 0.6, 0.7 end   -- Durotar inside Kalimdor
            return nil
        end,
    }
    env.GetPlayerFacing = function() return c.facing or 0 end
    env.GetZoneText = function() return c.zone or "Durotar" end
    env.GetSubZoneText = function() return c.subzone or "" end
    env.GetNumGroupMembers = function() return 0 end
    env.UnitFactionGroup = function() return "Alliance" end
    env.IsInInstance = function() return c.instance ~= nil, c.instance and "party" or "none" end
    env.GetInstanceInfo = function() return c.instance or "Durotar" end
    c.items = {
        [100] = { name = "New Helm", link = "|cff0070dd|Hitem:100::|h[New Helm]|h|r", minLevel = 18, loc = "INVTYPE_HEAD", sell = 500 },
        [5191] = { name = "Cruel Barb", link = "|cff0070dd|Hitem:5191::|h[Cruel Barb]|h|r", minLevel = 19, loc = "INVTYPE_HEAD", sell = 2000 },
        [2589] = { name = "Linen Cloth", link = "|cffffffff|Hitem:2589::|h[Linen Cloth]|h|r", minLevel = 0, q = 1, sell = 13, cls = "Trade Goods" },
        [3300] = { name = "Rabbit's Foot", link = "|cff9d9d9d|Hitem:3300::|h[Rabbit's Foot]|h|r", minLevel = 0, q = 0, sell = 4, cls = "Junk" },
    }
    env.GetItemInfo = function(id)
        local n = tonumber(id) or tonumber(tostring(id):match("item:(%d+)"))
        local it = n and c.items[n]
        if not it then return nil end
        return it.name, it.link, it.q or 3, it.ilvl or 20, it.minLevel or 1, it.cls or "Armor", "Plate", 20,
               it.loc or "", 134400, it.sell or 100
    end
    env.IsEquippableItem = function(link)
        local n = tonumber(tostring(link):match("item:(%d+)"))
        return n and c.items[n] and (c.items[n].loc or "") ~= ""
    end
    env.GetItemIcon = function() return 134400 end
    env.GetItemInfoInstant = function(link) return 0, "Armor", "Plate", "INVTYPE_HEAD" end
    env.GetItemStats = function(link)
        if tostring(link):find("item:100") then return { ITEM_MOD_STRENGTH_SHORT = 20, ITEM_MOD_STAMINA_SHORT = 10 } end
        if tostring(link):find("item:5191") then return { ITEM_MOD_STRENGTH_SHORT = 14, ITEM_MOD_STAMINA_SHORT = 5 } end
        return { ITEM_MOD_STRENGTH_SHORT = 10, ITEM_MOD_STAMINA_SHORT = 5 }
    end
    env.GetInventoryItemLink = function() return "|cff1eff00|Hitem:200::|h[Old Helm]|h|r" end
    env.PlaySound = function() end
    env.SOUNDKIT = { RAID_WARNING = 8959 }
    env.ChatFrame_SendTell = function(name) c.whispered = name end
    env.C_PartyInfo = { InviteUnit = function(name) c.invited = name end }
    env.InCombatLockdown = function() return false end
    c.tooltipHooks = {}
    env.TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) table.insert(c.tooltipHooks, fn) end }
    env.Enum.TooltipDataType = { Item = 0 }
    c.questTitles = {}
    c.questLog = {}
    env.C_QuestLog = { GetTitleForQuestID = function(id) return c.questTitles[id] end,
                       GetNumQuestLogEntries = function() return #c.questLog end,
                       GetInfo = function(i)
                           local q = c.questLog[i]
                           return q and { title = q.title, questID = q.id, isHeader = false } or nil
                       end,
                       IsComplete = function(id)
                           for _, q in ipairs(c.questLog) do if q.id == id then return q.complete end end
                           return false
                       end }
    env.C_AuctionHouse = { GetBrowseResults = function() return c.ahResults or {} end }
    env.C_TradeSkillUI = {
        GetAllRecipeIDs = function() return { 1, 2 } end,
        GetBaseProfessionInfo = function() return { professionName = "Alchemy", skillLevel = 120, maxSkillLevel = 150 } end,
        GetRecipeInfo = function(id) return { learned = true, name = id == 1 and "Flask of the Titans" or "Minor Healing Potion",
                                              relativeDifficulty = id == 1 and 0 or 1 } end,
        GetRecipeItemLink = function(id)
            return id == 1 and "|cffffffff|Hitem:13510::|h[Flask of the Titans]|h|r" or "|cffffffff|Hitem:118::|h[Minor Healing Potion]|h|r"
        end,
        GetRecipeSchematic = function(id)
            return { reagentSlotSchematics = { { reagents = { { itemID = 2589 } }, quantityRequired = id == 1 and 2 or 1 } } }
        end,
    }
    c.bag = {}
    env.C_Container = {
        GetContainerNumSlots = function(bag) return bag == 0 and #c.bag or 0 end,
        GetContainerItemInfo = function(bag, slot) return bag == 0 and c.bag[slot] or nil end,
    }

    c.ns = {}
    for _, file in ipairs(FILES) do
        local chunk = assert(loadfile(ADDON_DIR .. "/" .. file))
        setfenv(chunk, env)
        chunk("RUIN_Core", c.ns)
    end
    -- Remember every row of sub-tabs, so tests can open each sub-page.
    c.subtabs = {}
    local W = c.ns.Widgets
    local subTabs = W.SubTabs
    W.SubTabs = function(...)
        local obj = subTabs(...)
        table.insert(c.subtabs, obj)
        return obj
    end
    -- Optional modules: read each TOC's file list
    for _, folder in ipairs(opts.modules or {}) do
        local dir = ADDON_DIR .. "/../" .. folder
        local mns = {}
        for line in io.lines(dir .. "/" .. folder .. ".toc") do
            if line:match("%.lua%s*$") then
                local chunk = assert(loadfile(dir .. "/" .. line:match("^%s*(.-)%s*$")))
                setfenv(chunk, env)
                chunk(folder, mns)
            end
        end
        c.mns = c.mns or {}
        c.mns[folder] = mns
    end
    table.insert(Server.clients, c)
    Server.byName[c.name] = c
    fire(c, "ADDON_LOADED", "RUIN_Core")
    fire(c, "PLAYER_LOGIN")
    return c
end

function Server:Advance(seconds)
    local stop = self.time + seconds
    while true do
        table.sort(self.timers, function(a, b) return a.t < b.t end)
        local nextTimer = self.timers[1]
        if not nextTimer or nextTimer.t > stop then break end
        table.remove(self.timers, 1)
        if nextTimer.t > self.time then self.time = nextTimer.t end
        local ok, err = pcall(nextTimer.fn)
        if not ok then table.insert(self.errors, "timer: " .. tostring(err)) end
    end
    self.time = stop
end

-- A guild chat line from a roster member (client or not).
function Server:GuildSay(guild, member, text, officer)
    self.line = self.line + 1
    for _, c in ipairs(self.clients) do
        if c.guild == guild and (not officer or c.rank <= 1) then
            fire(c, officer and "CHAT_MSG_OFFICER" or "CHAT_MSG_GUILD", text, member.name, "", "", member.name,
                 "", 0, 0, "", 0, self.line, member.guid)
        end
    end
end

function Server:Slash(c, text) c.env.SlashCmdList.RUIN(text) end
