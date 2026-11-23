-- RUIN QA explorer: the "monkey" half of the Tester agent.
--
-- Builds the same populated multi-client org as render/render.lua (so every page has data), then
-- exercises the UI the way a curious player would and records anything that breaks:
--   * click every visible button / check box / tab on every page and sub-page
--   * hover everything (tooltip builders)
--   * type awkward text into every edit box (empty, huge, colour codes, format characters, unicode)
--   * move every slider and open every dropdown
--   * run every slash command with no argument, "help", "status" and nonsense
--   * fire common WoW events at every client and let a day of game time pass
-- Findings go to <outdir>/explore-findings.jsonl (one JSON object per line); layout dumps of the
-- states reached go to <outdir>/explore--*.json for lint.py.
--
--   texlua qa/run51.lua qa/explore.lua <outdir>
-- (RUIN_CORE_DIR must point at RUIN_Core; sibling addon folders must be named RUIN_<Module>.)

local here = arg[0]:match("^(.*)/") or "."
local OUT = arg[1] or "/tmp/ruin-qa"
os.execute("mkdir -p '" .. OUT .. "'")

-- 1. Build the populated world (render.lua writes its pages to a scratch folder we ignore).
local sceneDir = OUT .. "/scene"
arg[1] = sceneDir
local myself = arg[0]
arg[0] = here .. "/../render/render.lua"
local ok, err = pcall(dofile, arg[0])
arg[0] = myself
if not ok then io.stderr:write("scenario failed: " .. tostring(err) .. "\n"); os.exit(2) end
local F = RENDER_F
local ui
for _, c in ipairs(Server.clients) do
    local mf = c.env.RUIN_MainFrame
    if mf and rawget(mf, "_points") then ui = c end   -- the client built on the layout engine
end
assert(ui, "no UI client in scenario")
local API = ui.env.RUIN_API

---------------------------------------------------------------------------
-- Findings
---------------------------------------------------------------------------
local findings, seen = {}, {}
local function sha(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return string.format("%08x", h)
end
local function norm(msg)
    msg = tostring(msg)
    for _, c in ipairs(Server.clients) do msg = msg:gsub(c.name:gsub("%p", "%%%0") .. ": ", "") end
    msg = msg:gsub("^[^\n]-/(RUIN_%w+/)", "%1"):gsub("0x%x+", "0x"):gsub("%d+", "#"):gsub("table: [%w]+", "table")
    return msg
end
local function report(kind, where, msg, extra)
    local key = kind .. "|" .. norm(msg)
    local f = seen[key]
    if f then f.count = f.count + 1; if #f.where < 6 then table.insert(f.where, where) end; return end
    f = { id = "E-" .. sha(key), kind = kind, severity = kind == "lua-error" and "high" or "medium",
          message = tostring(msg):gsub("^[^\n]-/(RUIN_%w+/)", "%1"):sub(1, 400), where = { where }, count = 1 }
    if extra then for k, v in pairs(extra) do f[k] = v end end
    seen[key] = f
    findings[#findings + 1] = f
end

local BUDGET = tonumber(os.getenv("QA_STEP_BUDGET") or "") or 4e8   -- VM instructions per action
local VERBOSE = os.getenv("QA_VERBOSE")
local function protect(where, fn, ...)
    if VERBOSE then io.stderr:write(string.format("[%.0fs] %s\n", os.clock(), where)) end
    local count = 0
    debug.sethook(function()
        count = count + 1
        if count * 1e5 > BUDGET then debug.sethook(); error("QA watchdog: action ran over budget (likely an endless loop)", 2) end
    end, "", 1e5)
    local okc, e = xpcall(fn, function(m) return tostring(m) .. "\n" .. (debug.traceback("", 2):gsub("\n%s+%[C%]:[^\n]*", ""):sub(1, 600)) end, ...)
    debug.sethook()
    if not okc then report(tostring(e):find("QA watchdog", 1, true) and "hang" or "lua-error", where, e) end
    return okc
end
local function drainServerErrors(where)
    for _, e in ipairs(Server.errors) do report("lua-error", where, e) end
    Server.errors = {}
end

---------------------------------------------------------------------------
-- Frame helpers
---------------------------------------------------------------------------
local function clean(t) return (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("^%s+", ""):sub(1, 40)) end
local function label(fr)
    local t = rawget(fr, "_text")
    if type(t) == "string" and t:find("%S") then return clean(t) end
    for _, r in ipairs(rawget(fr, "_regions") or {}) do
        local rt = rawget(r, "_text")
        if type(rt) == "string" and rt:find("%S") then return clean(rt) end
    end
    for _, c in ipairs(rawget(fr, "_children") or {}) do
        for _, r in ipairs(rawget(c, "_regions") or {}) do
            local rt = rawget(r, "_text")
            if type(rt) == "string" and rt:find("%S") then return clean(rt) end
        end
    end
    local n = fr.GetName and fr:GetName()
    if n then return n end
    return fr._type or "frame"
end

local function visibleChain(fr)
    local p = fr
    while p do
        if p._shown == false then return false end
        p = p._parent
    end
    return true
end

-- every frame under UIParent, depth-first (the layout engine keeps children on _children)
local function walk(root, out, seenF)
    if not root or seenF[root] then return end
    seenF[root] = true
    out[#out + 1] = root
    for _, c in ipairs(rawget(root, "_children") or {}) do walk(c, out, seenF) end
end
local function frames()
    local out, seenF = {}, {}
    walk(ui.env.UIParent, out, seenF)
    for k, v in pairs(ui.env) do
        if type(k) == "string" and k:match("^RUIN") and type(v) == "table" and rawget(v, "_scripts") then walk(v, out, seenF) end
    end
    return out
end

-- visible interactive frames right now (a snapshot, so clicking can't break the iteration)
local function interactive()
    local out = {}
    for _, fr in ipairs(frames()) do
        local s = rawget(fr, "_scripts")
        if s and visibleChain(fr) and not rawget(fr, "_disabled")
           and (s.OnClick or s.OnMouseUp or s.OnMouseDown or s.OnValueChanged or s.OnEnterPressed or s.OnTextChanged
                or s.OnEnter or fr._type == "EditBox") then
            out[#out + 1] = fr
        end
    end
    return out
end

local DANGEROUS = { "Leave", "Disband", "Reset", "Wipe", "Forget", "Delete all", "Remove guild", "Clear all", "Quit", "Logout" }
local function dangerous(lbl)
    for _, d in ipairs(DANGEROUS) do if lbl:find(d, 1, true) then return true end end
    return false
end

local function closePopups()
    for _, n in ipairs({ "RUIN_ConfirmDialog", "RUIN_TextDialog", "RUIN_WhatsNew", "RUIN_ExchangeScan", "RUIN_PathfinderAlerts",
                         "RUIN_PathfinderWaypointEditor" }) do
        local f = ui.env[n]
        if f and f.Hide then pcall(f.Hide, f) end
    end
end

local dumpN = 0
local function dump(tag)
    dumpN = dumpN + 1
    local fh = io.open(string.format("%s/explore--%03d-%s.json", OUT, dumpN, tag:lower():gsub("[^%w]+", "-")), "w")
    if fh then
        fh:write(F.json({ w = F.SCREEN_W, h = F.SCREEN_H, regions = F.Dump() }))
        fh:close()
    end
end

---------------------------------------------------------------------------
-- Phase A: click, hover and type on every page
---------------------------------------------------------------------------
local EDIT_INPUTS = { "", "x", string.rep("W", 300), "|cffff0000red|r", "%s %d %%", "|Hitem:1::|h[Fake]|h", "Ünïcödé ✓ 日本語",
                      "line1\nline2", "  spaces  ", "-1", "999999999999", "0" }

local stats = { clicks = 0, hovers = 0, edits = 0, sliders = 0, pages = 0 }

local function exerciseFrame(where, fr)
    local lbl = label(fr)
    local s = fr._scripts
    local here2 = where .. " > " .. lbl
    -- tooltips
    for _, ev in ipairs({ "OnEnter", "OnLeave" }) do
        if s[ev] then stats.hovers = stats.hovers + 1; protect(here2 .. " (" .. ev .. ")", s[ev], fr) end
    end
    -- edit boxes
    if s.OnTextChanged or s.OnEnterPressed or fr._type == "EditBox" then
        for _, text in ipairs(EDIT_INPUTS) do
            stats.edits = stats.edits + 1
            if fr.SetText then fr:SetText(text) end
            if s.OnTextChanged then protect(here2 .. " (typed '" .. text:sub(1, 12) .. "')", s.OnTextChanged, fr, true) end
            if s.OnEnterPressed then protect(here2 .. " (Enter after '" .. text:sub(1, 12) .. "')", s.OnEnterPressed, fr) end
            if s.OnEditFocusLost then protect(here2 .. " (focus lost)", s.OnEditFocusLost, fr) end
        end
        if fr.SetText then fr:SetText("") end
        return
    end
    -- sliders
    if s.OnValueChanged then
        local lo, hi = 0, 100
        if fr.GetMinMaxValues then local a, b = fr:GetMinMaxValues(); if type(a) == "number" and type(b) == "number" then lo, hi = a, b end end
        for _, v in ipairs({ lo, hi, (lo + hi) / 2 }) do
            stats.sliders = stats.sliders + 1
            if fr.SetValue then fr:SetValue(v) end
            protect(here2 .. " (value " .. tostring(v) .. ")", s.OnValueChanged, fr, v, true)
        end
    end
    -- clicks
    if not dangerous(lbl) then
        local btns = fr._type == "CheckButton" and { "LeftButton", "LeftButton" } or { "LeftButton", "RightButton" }
        for _, b in ipairs(btns) do
            if s.OnClick then stats.clicks = stats.clicks + 1; protect(here2 .. " (" .. b .. " click)", s.OnClick, fr, b) end
            if s.OnMouseUp then stats.clicks = stats.clicks + 1; protect(here2 .. " (" .. b .. " mouse up)", s.OnMouseUp, fr, b) end
        end
    end
end

local exercised = {}            -- frame -> true, so each control is tried once per run
local MAX_DEPTH = tonumber(os.getenv("QA_DEPTH") or "") or 2
local MAX_FRAMES = tonumber(os.getenv("QA_MAX_FRAMES") or "") or 6000

local function drainLayoutErrors(where)
    for _, e in ipairs(F.errors) do report("lua-error", where, e) end
    for i = #F.errors, 1, -1 do F.errors[i] = nil end
end

-- sub-tab buttons (from every W.SubTabs row built so far) are clicked after the page's content
local function subtabButtons()
    local set = {}
    for _, st in ipairs(RENDER_SUBTABS or {}) do
        for _, b in ipairs(st.obj.buttons or {}) do set[b] = true end
    end
    return set
end
local mainTabs = {}

local frameCount = 0
local function exploreState(where, depth)
    local isSub = subtabButtons()
    local content, tabs = {}, {}
    for _, fr in ipairs(interactive()) do
        if not mainTabs[label(fr)] then
            if isSub[fr] then tabs[#tabs + 1] = fr else content[#content + 1] = fr end
        end
    end
    local list = content
    for _, fr in ipairs(tabs) do list[#list + 1] = fr end
    local known = {}
    for _, fr in ipairs(list) do known[fr] = true end
    for _, fr in ipairs(list) do
        if frameCount >= MAX_FRAMES then return end
        if not exercised[fr] and visibleChain(fr) then
            exercised[fr] = true
            frameCount = frameCount + 1
            exerciseFrame(where, fr)
            protect(where .. " (after " .. label(fr) .. ")", function() Server:Advance(0.2) end)
            drainServerErrors(where); drainLayoutErrors(where)
            -- the click showed controls that weren't there before (a sub-tab, a dialog, a list): explore them
            if depth < MAX_DEPTH then
                local fresh = false
                for _, g in ipairs(interactive()) do
                    if not known[g] and not exercised[g] then fresh = true; break end
                end
                if fresh then
                    local sub = where .. " > " .. label(fr)
                    exploreState(sub, depth + 1)
                    protect("dump " .. sub, dump, sub)
                    for _, g in ipairs(interactive()) do known[g] = true end
                end
            end
        end
    end
end

local function exercisePage(where)
    stats.pages = stats.pages + 1
    closePopups()
    exploreState(where, 0)
    protect(where .. " (settle)", function() Server:Advance(2) end)
    drainServerErrors(where); drainLayoutErrors(where)
    protect("dump " .. where, dump, where)
    closePopups()
end

local labels = {}
protect("TabLabels", function() labels = ui.ns.UI:TabLabels() end)
for _, t in ipairs(labels) do mainTabs[t] = true end
for _, tab in ipairs(labels) do
    protect("open tab " .. tab, function() API:OpenTab(tab) end)
    protect("open tab settle", function() Server:Advance(1) end)
    drainServerErrors("open tab " .. tab)
    exercisePage("tab " .. tab)
end

---------------------------------------------------------------------------
-- Phase B: slash commands
---------------------------------------------------------------------------
local SKIP_CMD = { RELOAD = true, RELOADUI = true, LOGOUT = true, QUIT = true, CAMP = true, EXIT = true, CONSOLE = true }
local ARGS = { "", "help", "status", "list", "on", "off", "toggle", "reset-nothing", "xyzzy 12 |cffff0000bad|r", string.rep("a", 400) }
local cmds = {}
for name, fn in pairs(ui.env.SlashCmdList) do
    if not SKIP_CMD[name] and type(fn) == "function" then cmds[#cmds + 1] = name end
end
table.sort(cmds)
local ranCmds = 0
for _, name in ipairs(cmds) do
    for _, a in ipairs(ARGS) do
        ranCmds = ranCmds + 1
        protect("/" .. name:lower() .. " " .. a:sub(1, 16), ui.env.SlashCmdList[name], a)
        protect("/" .. name:lower() .. " settle", function() Server:Advance(0.3) end)
        drainServerErrors("/" .. name:lower())
    end
    closePopups()
end

---------------------------------------------------------------------------
-- Phase C: events and time
---------------------------------------------------------------------------
local EVENTS = {
    "PLAYER_ENTERING_WORLD", "PLAYER_LOGIN", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS", "GROUP_ROSTER_UPDATE",
    "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "BAG_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_TARGET_CHANGED", "PLAYER_LEVEL_UP", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "UNIT_QUEST_LOG_CHANGED",
    "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE",
    "TRADE_SKILL_CLOSE", "PLAYER_MONEY", "CHAT_MSG_LOOT", "CHAT_MSG_SYSTEM", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_CHANNEL",
    "CHAT_MSG_WHISPER", "CHAT_MSG_PARTY", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UI_ERROR_MESSAGE",
    "LOOT_OPENED", "LOOT_CLOSED", "ENCOUNTER_START", "ENCOUNTER_END", "BOSS_KILL", "INSTANCE_LOCK_START", "PLAYER_DEAD", "PLAYER_ALIVE",
    "PLAYER_UNGHOST", "GOSSIP_SHOW", "QUEST_DETAIL", "QUEST_COMPLETE", "QUEST_PROGRESS", "COMBAT_LOG_EVENT_UNFILTERED", "PLAYER_LOGOUT",
    "GUILD_MOTD", "GUILD_TRADESKILL_UPDATE", "WHO_LIST_UPDATE", "FRIENDLIST_UPDATE", "ADDON_LOADED", "UNIT_SPELLCAST_SUCCEEDED",
    "PLAYER_EQUIPMENT_CHANGED", "BANKFRAME_OPENED", "GUILDBANKFRAME_OPENED", "MAIL_SHOW", "MAIL_INBOX_UPDATE", "TAXIMAP_OPENED",
    "WORLD_MAP_UPDATE", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "CHAT_MSG_COMBAT_HOSTILE_DEATH", "PARTY_KILL", "PLAYER_PVP_KILLS_CHANGED",
}
local firedEvents = 0
for _, c in ipairs(Server.clients) do
    for _, ev in ipairs(EVENTS) do
        firedEvents = firedEvents + 1
        local okc, e = pcall(Server.fire, c, ev)
        if not okc then report("lua-error", "event " .. ev, e) end
        -- also with typical wrong-ish arguments
        pcall(Server.fire, c, ev, "player")
        pcall(Server.fire, c, ev, nil, nil, nil)
    end
    protect("events settle " .. c.name, function() Server:Advance(1) end)
    drainServerErrors("events on " .. c.name)
end
-- pending timers, grouped by the function that will run (a growing pile = a timer leak)
local function timerCensus(tag)
    local by = {}
    for _, t in ipairs(Server.timers) do
        local info = debug.getinfo(t.fn, "S")
        local k = (info.short_src or "?"):gsub("^.*/(RUIN_%w+/)", "%1") .. ":" .. tostring(info.linedefined)
        by[k] = (by[k] or 0) + 1
    end
    local list = {}
    for k, n in pairs(by) do list[#list + 1] = { k = k, n = n } end
    table.sort(list, function(a, b) return a.n > b.n end)
    if VERBOSE then
        io.stderr:write(("timers %s: %d pending\n"):format(tag, #Server.timers))
        for i = 1, math.min(6, #list) do io.stderr:write(("   %5d  %s\n"):format(list[i].n, list[i].k)) end
    end
    return #Server.timers, list
end
local timersBefore = timerCensus("before time passes")

-- QA_PROFILE=1: time one simulated minute per timer source (finds what makes the clock slow)
local function timerSource(fn)
    local info = debug.getinfo(fn, "S")
    if info.short_src:find("harness") then
        for k = 1, 10 do
            local n, v = debug.getupvalue(fn, k)
            if n == "fn" and type(v) == "function" then info = debug.getinfo(v, "S"); break end
        end
    end
    return (info.short_src:gsub("^.*/(RUIN_%w+/)", "%1")) .. ":" .. info.linedefined
end
local slowTimers = {}
local function profileMinute()
    local cost, runs = {}, {}
    for _ = 1, 600 do
        for _, t in ipairs(Server.timers) do
            if not t.qaWrapped then
                local f, k = t.fn, timerSource(t.fn)
                t.fn = function() local c = os.clock(); f(); cost[k] = (cost[k] or 0) + os.clock() - c; runs[k] = (runs[k] or 0) + 1 end
                t.qaWrapped = true
            end
        end
        Server:Advance(0.1)
    end
    local list = {}
    for k, v in pairs(cost) do list[#list + 1] = { k = k, s = v, n = runs[k] } end
    table.sort(list, function(a, b) return a.s > b.s end)
    return list
end
do
    local okp, list = pcall(profileMinute)
    if okp then
        for i = 1, math.min(8, #list) do
            if VERBOSE or os.getenv("QA_PROFILE") then io.stderr:write(("  %6.2fs %6d runs  %s\n"):format(list[i].s, list[i].n, list[i].k)) end
            if list[i].s > 0.5 then
                report("slow-timer", "time passing", ("%s used %.1fs of CPU in one simulated minute (%d runs) after the UI tour"):format(list[i].k, list[i].s, list[i].n))
            end
        end
    end
end

-- game time in one-minute steps, so timers, throttles and repeating jobs all run
-- (QA_HOURS, default 2: the harness clock gets slow with many timers)
local HOURS = tonumber(os.getenv("QA_HOURS") or "") or 2
for _ = 1, HOURS * 60 do
    protect("advance a minute", function() Server:Advance(60) end)
    drainServerErrors("time passing")
end
local timersAfter, timerList = timerCensus("after time passed")
if timersAfter > math.max(500, timersBefore * 3) then
    local top = timerList[1]
    report("timer-leak", "time passing", ("pending timers grew from %d to %d during %d simulated hours; most from %s (%d)")
        :format(timersBefore, timersAfter, HOURS, top and top.k or "?", top and top.n or 0))
end
protect("dump after a day", dump, "after-a-day")
-- one more tour of every tab after all of that
for _, tab in ipairs(labels) do
    protect("open tab " .. tab, function() API:OpenTab(tab) end)
    protect("after-day settle " .. tab, function() Server:Advance(1) end)
    drainServerErrors("after-day tab " .. tab)
    protect("dump after-day " .. tab, dump, "after-day-" .. tab)
end

---------------------------------------------------------------------------
-- Phase D: saved-variable hygiene (stuff that grows without bound, junk values)
---------------------------------------------------------------------------
local function countTable(t, depth, seenT)
    depth = depth or 0
    seenT = seenT or {}
    if type(t) ~= "table" or seenT[t] or depth > 8 then return 0 end
    seenT[t] = true
    local n = 0
    for _, v in pairs(t) do n = n + 1 + countTable(v, depth + 1, seenT) end
    return n
end
for name, v in pairs(ui.env) do
    if type(name) == "string" and name:match("^RUIN_%w+DB$") and type(v) == "table" then
        local n = countTable(v)
        if n > 20000 then report("data-growth", name, name .. " holds " .. n .. " values after the simulated hours") end
        local function scan(t, path, depth, seenT)
            if depth > 6 or seenT[t] then return end
            seenT[t] = true
            for k, val in pairs(t) do
                if type(val) == "number" and (val ~= val or val == math.huge or val == -math.huge) then
                    report("bad-data", name, name .. path .. "." .. tostring(k) .. " is NaN/inf")
                elseif type(val) == "table" then
                    scan(val, path .. "." .. tostring(k), depth + 1, seenT)
                elseif type(val) == "function" then
                    report("bad-data", name, name .. path .. "." .. tostring(k) .. " is a function in saved data")
                end
            end
        end
        scan(v, "", 0, {})
    end
end

---------------------------------------------------------------------------
-- Output
---------------------------------------------------------------------------
local fh = assert(io.open(OUT .. "/explore-findings.jsonl", "w"))
for _, f in ipairs(findings) do fh:write(F.json(f), "\n") end
fh:close()
local statsLine = string.format("explore: %d pages, %d controls tried, %d clicks, %d hovers, %d typed inputs, %d slider moves, %d slash calls (%d commands), %d events, %d simulated hours -> %d findings",
    stats.pages, frameCount, stats.clicks, stats.hovers, stats.edits, stats.sliders, ranCmds, #cmds, firedEvents, HOURS, #findings)
local sf = io.open(OUT .. "/explore-stats.txt", "w")
if sf then sf:write(statsLine, "\n"); sf:close() end
print(string.format("explore: %d pages, %d clicks, %d hovers, %d typed inputs, %d slider moves, %d slash calls (%d commands), %d events -> %d findings",
    stats.pages, stats.clicks, stats.hovers, stats.edits, stats.sliders, ranCmds, #cmds, firedEvents, #findings))
