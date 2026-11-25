-- RUIN performance probe: the measuring half of the Optimizer agent.
--
-- Builds the same populated multi-client org as render/render.lua, then measures what the
-- addons cost while they run, by source (file:line of the function doing the work):
--   * events: which handlers run for which game events, how often, CPU and the worst single call,
--     with a burst of the events the game fires most (bags, auras, combat log, roster, chat...)
--   * OnUpdate: every frame with an OnUpdate script; the shown ones are run for 10 s at 60 fps
--   * timers: one simulated hour of C_Timer work, runs and CPU per source, and what is still pending
--   * frames: how many frames, textures and font strings exist, under which top-level window,
--     and which texture files are loaded into many separate textures (reuse candidates)
--   * memory: Lua memory after loading, after a tour of every page, and after the hour (growth)
-- CPU numbers come from the simulator, so compare them with each other and between runs, not
-- with the game. Writes <outdir>/perf.json and <outdir>/PERF.md; with a previous perf.json it
-- also prints what got better or worse.
--
--   texlua qa/run51.lua qa/perf.lua <outdir> [previous perf.json]
-- (RUIN_CORE_DIR must point at RUIN_Core; sibling addon folders must be named RUIN_<Module>.)

local here = os.getenv("QAHERE") or "/home/claude/stage/tests/qa"
local OUT = arg[1] or "/tmp/ruin-perf"
local PREV = arg[2]
os.execute("mkdir -p '" .. OUT .. "'")

collectgarbage("collect")
local memStart = collectgarbage("count")

-- 1. The populated world (render.lua writes its pages to a scratch folder we ignore).
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
    if mf and rawget(mf, "_points") then ui = c end
end
assert(ui, "no UI client in scenario")
collectgarbage("collect")
local memLoaded = collectgarbage("count")

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local clock = os.clock
local function src(fn)
    if type(fn) ~= "function" then return "?" end
    local i = debug.getinfo(fn, "S")
    local s = (i.short_src or "?"):gsub("^.*/(RUIN_%w+/)", "%1"):gsub("^%.%./", "")
    return s .. ":" .. (i.linedefined or 0)
end
local function isAddon(s) return s:find("^RUIN_") ~= nil end
local function upvalue(fn, name)
    for i = 1, 60 do
        local n, v = debug.getupvalue(fn, i)
        if not n then return nil end
        if n == name then return v end
    end
end
-- the addon function behind a harness wrapper (a C_Timer ticker's run(), message delivery)
local function realSrc(fn)
    local s = src(fn)
    if not s:find("harness%.lua") then return s end
    local inner = upvalue(fn, "fn")
    if type(inner) == "function" then return src(inner) end
    if upvalue(fn, "args") then return "(addon message delivery)" end
    return s
end
local function bump(t, k, dt, extra)
    local e = t[k]
    if not e then e = { key = k, n = 0, cpu = 0, worst = 0 }; t[k] = e end
    e.n, e.cpu = e.n + 1, e.cpu + dt
    if dt > e.worst then e.worst = dt end
    if extra then e.extra = e.extra or {}; e.extra[extra] = (e.extra[extra] or 0) + 1 end
end
local function sorted(t, field, max)
    local l = {}
    for _, v in pairs(t) do l[#l + 1] = v end
    table.sort(l, function(a, b) return (a[field] or 0) > (b[field] or 0) end)
    local out = {}
    for i = 1, math.min(max or #l, #l) do out[i] = l[i] end
    return out
end
local function ms(s) return math.floor(s * 100000 + 0.5) / 100 end    -- seconds -> ms, 2 places

-- every frame of the UI client: its frames list plus everything under UIParent
local function eachFrame(fn)
    local seen = {}
    local function walk(f)
        if type(f) ~= "table" or seen[f] then return end
        seen[f] = true
        fn(f)
        for _, ch in ipairs(rawget(f, "_children") or {}) do walk(ch) end
    end
    for _, f in ipairs(ui.frames) do walk(f) end
    if F.UIParent then walk(F.UIParent) end
    return seen
end

---------------------------------------------------------------------------
-- 2. A tour of every page (so lazily built pages exist), then memory
---------------------------------------------------------------------------
local tabs = RENDER_SUBTABS or {}
local env = ui.env
pcall(function()
    local UI = env.RUIN_API and env.RUIN_API.UI
    local mf = env.RUIN_MainFrame
    if mf and mf.Show then mf:Show() end
    for _, c in ipairs(Server.clients) do
        if c == ui and c.env.SlashCmdList and c.env.SlashCmdList.RUIN then
            for _, page in ipairs({ "", "finder", "muster", "pathfinder", "codex", "exchange", "settings" }) do
                pcall(c.env.SlashCmdList.RUIN, page)
            end
        end
    end
end)
for _, st in ipairs(tabs) do
    if st.Select and st.names then for i = 1, #st.names do pcall(st.Select, st, i) end; pcall(st.Select, st, 1) end
end
collectgarbage("collect")
local memToured = collectgarbage("count")

---------------------------------------------------------------------------
-- 3. Events: wrap every OnEvent and fire a burst of the busiest game events
---------------------------------------------------------------------------
local evStats, evRegs = {}, {}
local wrapped = {}
for _, c in ipairs(Server.clients) do
    for _, f in ipairs(c.frames) do
        local h = f._scripts and f._scripts.OnEvent
        if h and not wrapped[h] then
            local s = src(h)
            for e in pairs(f._events or {}) do
                evRegs[e] = evRegs[e] or {}
                evRegs[e][s] = true
            end
            local w = function(self, e, ...)
                local t0 = clock()
                h(self, e, ...)
                if c == ui and not s:find("RUIN_Core/Core%.lua") then bump(evStats, s .. " <" .. tostring(e) .. ">", clock() - t0) end
            end
            wrapped[w] = true
            f._scripts.OnEvent = w
        end
    end
end
-- (event, how many times in the burst, args): roughly a minute of busy play
local BURST = {
    { "COMBAT_LOG_EVENT_UNFILTERED", 600 }, { "UNIT_AURA", 300, "player" }, { "UNIT_HEALTH", 300, "target" },
    { "UNIT_POWER_UPDATE", 300, "player", "MANA" }, { "SPELL_UPDATE_COOLDOWN", 120 }, { "ACTIONBAR_UPDATE_COOLDOWN", 120 },
    { "BAG_UPDATE", 120, 0 }, { "BAG_UPDATE_DELAYED", 30 }, { "UNIT_INVENTORY_CHANGED", 20, "player" },
    { "PLAYER_TARGET_CHANGED", 60 }, { "UPDATE_MOUSEOVER_UNIT", 120 }, { "CURSOR_CHANGED", 60 },
    { "MODIFIER_STATE_CHANGED", 60, "LSHIFT", 1 }, { "QUEST_LOG_UPDATE", 40 }, { "UNIT_QUEST_LOG_CHANGED", 20, "player" },
    { "GROUP_ROSTER_UPDATE", 20 }, { "GUILD_ROSTER_UPDATE", 20 }, { "FRIENDLIST_UPDATE", 10 },
    { "PLAYER_MONEY", 20 }, { "ZONE_CHANGED", 10 }, { "ZONE_CHANGED_NEW_AREA", 5 }, { "MINIMAP_UPDATE_ZOOM", 10 },
    { "CHAT_MSG_SYSTEM", 30, "You receive loot." }, { "CHAT_MSG_CHANNEL", 60, "lfg anyone", "Someone", "", "2. Trade", "", "", 0, 2, "Trade" },
    { "CHAT_MSG_LOOT", 30, "You receive loot: [Linen Cloth]." }, { "NAME_PLATE_UNIT_ADDED", 60, "nameplate1" },
    { "NAME_PLATE_UNIT_REMOVED", 60, "nameplate1" }, { "PLAYER_REGEN_DISABLED", 10 }, { "PLAYER_REGEN_ENABLED", 10 },
    { "UNIT_TARGET", 120, "target" }, { "PLAYER_XP_UPDATE", 20, "player" }, { "UPDATE_FACTION", 10 },
}
-- Core's own event bus: one frame dispatches to every module's handler, so time each handler
-- (and the internal callbacks fired with ns:Fire) by its own source
do
    local mf = ui.env.RUIN_API
    for _, f in ipairs(ui.frames) do
        local h = f._scripts and f._scripts.OnEvent
        local inner = h and upvalue(h, "h")
        local handlers = inner and upvalue(inner, "eventHandlers")
        if type(handlers) == "table" then
            for event, list in pairs(handlers) do
                for i, fn in ipairs(list) do
                    -- a module's handler sits inside Modules.lua's wrapper: name the module's function
                    local inner2 = src(fn):find("Modules%.lua") and upvalue(fn, "fn")
                    local s = src(type(inner2) == "function" and inner2 or fn)
                    for _ in pairs({ [event] = true }) do evRegs[event] = evRegs[event] or {}; evRegs[event][s] = true end
                    list[i] = function(...)
                        local t0 = clock()
                        fn(...)
                        bump(evStats, s .. " <" .. event .. ">", clock() - t0)
                    end
                end
                -- the dispatcher's own entry is not a handler
                for k in pairs(evRegs[event] or {}) do if k:find("Core%.lua:134$") then evRegs[event][k] = nil end end
            end
        end
    end
end
local burstT0 = clock()
for _, b in ipairs(BURST) do
    for _ = 1, b[2] do pcall(Server.fire, ui, b[1], select(3, unpack(b))) end
end
local burstCPU = clock() - burstT0
-- timers the burst scheduled run in the hour below
local busyRegs = {}
for _, b in ipairs(BURST) do
    local list = {}
    for s in pairs(evRegs[b[1]] or {}) do if isAddon(s) then list[#list + 1] = s end end
    table.sort(list)
    if #list > 0 then busyRegs[#busyRegs + 1] = { event = b[1], per_minute = b[2], handlers = list } end
end

---------------------------------------------------------------------------
-- 4. OnUpdate scripts: list them all, run the shown ones 10 s at 60 fps
---------------------------------------------------------------------------
local onUpdate, ouStats = {}, {}
eachFrame(function(f)
    local h = f._scripts and f._scripts.OnUpdate
    if h then
        local vis = f.IsVisible and f:IsVisible() or false
        onUpdate[#onUpdate + 1] = { src = src(h), shown = vis and true or false, name = rawget(f, "_name") }
        if vis then
            local s = src(h)
            for _ = 1, 600 do
                local t0 = clock()
                local okc = pcall(h, f, 1 / 60)
                bump(ouStats, s, clock() - t0)
                if not okc then break end
            end
        end
    end
end)

---------------------------------------------------------------------------
-- 5. One simulated hour of timers, by source
---------------------------------------------------------------------------
local tmStats = {}
local pendingBefore = #Server.timers
local realAdvance = Server.Advance
function Server:Advance(seconds)
    local stop = self.time + seconds
    while true do
        table.sort(self.timers, function(a, b) return a.t < b.t end)
        local nt = self.timers[1]
        if not nt or nt.t > stop then break end
        table.remove(self.timers, 1)
        if nt.t > self.time then self.time = nt.t end
        CURSRC = realSrc(nt.fn)
        local t0 = clock()
        local okt, e = pcall(nt.fn)
        CURSRC = nil
        bump(tmStats, realSrc(nt.fn), clock() - t0)
        if not okt then table.insert(self.errors, "timer: " .. tostring(e)) end
    end
    self.time = stop
end
local PROF, PROFX, PROFS, PROFE, PT = {}, {}, {}, {}, {}
local function sampler()
    if CURSRC then PT[CURSRC] = (PT[CURSRC] or 0) + 1 end
    local seen = {}
    local child
    local inner
    for lvl = 2, 40 do
        local i = debug.getinfo(lvl, "Sl")
        if not i then break end
        local s = (i.short_src or "?"):gsub("^.*/(RUIN_%w+/)", "%1")
        if s:find("^RUIN_") then
            local k = s .. ":" .. (i.linedefined or 0)
            if lvl == 2 or not PROFX.first then end
            if not seen[k] then seen[k] = true; PROF[k] = (PROF[k] or 0) + 1 end
            if not inner then inner = k; PROFS[k] = (PROFS[k] or 0) + 1 end
            if child then local e = k .. " -> " .. child; if not seen[e] then seen[e]=true; PROFE[e] = (PROFE[e] or 0) + 1 end end
            child = k
        end
    end
    local i = debug.getinfo(2, "Sl")
    if i then local k=(i.short_src or "?"):gsub("^.*/","")..":"..(i.currentline or 0); PROFX[k]=(PROFX[k] or 0)+1 end
end
if os.getenv("PROF") then debug.sethook(sampler, "", tonumber(os.getenv("PROF")) or 1000) end
local hourT0 = clock()
for _ = 1, 60 do Server:Advance(60) end
local hourCPU = clock() - hourT0
debug.sethook()
if os.getenv("PROF") then
  local l={} for k,v in pairs(PROF) do l[#l+1]={k,v} end table.sort(l,function(a,b) return a[2]>b[2] end)
  local f=io.open(OUT.."/prof.txt","w") for i=1,math.min(120,#l) do f:write(l[i][2],"  ",l[i][1],"\n") end
  local tl, tot = {}, 0 for k,v in pairs(PT) do tl[#tl+1]={k,v}; tot = tot + v end table.sort(tl,function(a,b) return a[2]>b[2] end)
  f:write("-- per timer source (samples), total ", tot, "\n")
  for i=1,math.min(25,#tl) do f:write(tl[i][2],"  ",tl[i][1],"\n") end
  f:write("\n-- self by function\n")
  l={} for k,v in pairs(PROFS) do l[#l+1]={k,v} end table.sort(l,function(a,b) return a[2]>b[2] end)
  for i=1,math.min(60,#l) do f:write(l[i][2],"  ",l[i][1],"\n") end
  f:write("\n-- edges\n")
  l={} for k,v in pairs(PROFE) do l[#l+1]={k,v} end table.sort(l,function(a,b) return a[2]>b[2] end)
  for i=1,math.min(250,#l) do f:write(l[i][2],"  ",l[i][1],"\n") end
  f:write("\n-- self lines\n")
  l={} for k,v in pairs(PROFX) do l[#l+1]={k,v} end table.sort(l,function(a,b) return a[2]>b[2] end)
  for i=1,math.min(80,#l) do f:write(l[i][2],"  ",l[i][1],"\n") end
  f:close()
end
Server.Advance = realAdvance
local pending = {}
for _, t in ipairs(Server.timers) do local s = realSrc(t.fn); pending[s] = (pending[s] or 0) + 1 end
local pendingList = {}
for s, n in pairs(pending) do pendingList[#pendingList + 1] = { src = s, n = n } end
table.sort(pendingList, function(a, b) return a.n > b.n end)
collectgarbage("collect")
local memHour = collectgarbage("count")

---------------------------------------------------------------------------
-- 6. Frames, textures, font strings, and texture files used many times
---------------------------------------------------------------------------
local counts = { Frame = 0, Texture = 0, FontString = 0, other = 0 }
local byWindow, texFiles, colorTex = {}, {}, 0
local function top(f)
    local p, last = f, f
    while rawget(p, "_parent") and rawget(p, "_parent") ~= F.UIParent do last = p; p = rawget(p, "_parent") end
    return rawget(p, "_name") or rawget(last, "_name") or "(unnamed)"
end
eachFrame(function(f)
    local k = rawget(f, "_type") or "Frame"
    counts.Frame = counts.Frame + 1
    local w = top(f)
    byWindow[w] = byWindow[w] or { window = w, frames = 0, textures = 0, fonts = 0 }
    byWindow[w].frames = byWindow[w].frames + 1
    for _, r in ipairs(rawget(f, "_regions") or {}) do
        local rk = rawget(r, "_type")
        if rk == "Texture" then
            counts.Texture = counts.Texture + 1
            byWindow[w].textures = byWindow[w].textures + 1
            local tex = rawget(r, "_tex")
            if tex then texFiles[tostring(tex)] = (texFiles[tostring(tex)] or 0) + 1 elseif rawget(r, "_color") then colorTex = colorTex + 1 end
        elseif rk == "FontString" then
            counts.FontString = counts.FontString + 1
            byWindow[w].fonts = byWindow[w].fonts + 1
        else
            counts.other = counts.other + 1
        end
    end
end)
local texList = {}
for path, n in pairs(texFiles) do if n >= 3 then texList[#texList + 1] = { file = path, textures = n } end end
table.sort(texList, function(a, b) return a.textures > b.textures end)
local winList = {}
for _, v in pairs(byWindow) do winList[#winList + 1] = v end
table.sort(winList, function(a, b) return a.frames + a.textures + a.fonts > b.frames + b.textures + b.fonts end)

---------------------------------------------------------------------------
-- 7. Write it out
---------------------------------------------------------------------------
local function only(list, n) local o = {}; for i = 1, math.min(n, #list) do o[i] = list[i] end; return o end
local function rows(stats, max)
    local o = {}
    for _, e in ipairs(sorted(stats, "cpu", max)) do
        o[#o + 1] = { src = e.key, calls = e.n, cpu_ms = ms(e.cpu), worst_ms = ms(e.worst), avg_us = math.floor(e.cpu / e.n * 1e6 + 0.5) }
    end
    return o
end
local hiccups = {}
for _, t in ipairs({ { "event", evStats }, { "onupdate", ouStats }, { "timer", tmStats } }) do
    for _, e in pairs(t[2]) do
        if e.worst >= 0.004 then hiccups[#hiccups + 1] = { kind = t[1], src = e.key, worst_ms = ms(e.worst), calls = e.n } end
    end
end
table.sort(hiccups, function(a, b) return a.worst_ms > b.worst_ms end)

local result = {
    memory_kb = { start = math.floor(memStart), loaded = math.floor(memLoaded), toured = math.floor(memToured),
                  after_hour = math.floor(memHour), growth_hour = math.floor(memHour - memToured) },
    cpu_ms = { event_burst = ms(burstCPU), onupdate_10s = 0, timers_hour = ms(hourCPU) },
    events = rows(evStats, 40),
    busy_event_registrations = busyRegs,
    onupdate_scripts = onUpdate,
    onupdate = rows(ouStats, 30),
    timers = rows(tmStats, 40),
    timers_pending = { before = pendingBefore, after = #Server.timers, by_source = only(pendingList, 15) },
    objects = { counts = counts, color_textures = colorTex, by_window = only(winList, 20), texture_files_reused = only(texList, 30) },
    hiccups = only(hiccups, 30),
    errors = Server.errors,
}
do local s = 0; for _, e in pairs(ouStats) do s = s + e.cpu end; result.cpu_ms.onupdate_10s = ms(s) end
-- The burst and hour totals above are wall time and include the simulator's own work (firing an
-- event walks every frame of the client; each timer run re-sorts the whole timer list), which
-- swamps the addons' share. These two add up only the timed addon calls (message delivery counts:
-- it is the addons' CHAT_MSG_ADDON handling).
do
    local s = 0
    for _, e in pairs(evStats) do s = s + e.cpu end
    result.cpu_ms.event_burst_addon = ms(s)
    s = 0
    for k, e in pairs(tmStats) do if not k:find("harness%.lua") then s = s + e.cpu end end
    result.cpu_ms.timers_hour_addon = ms(s)
end

-- minimal JSON writer
local function json(v, ind)
    ind = ind or ""
    local t = type(v)
    if t == "table" then
        local isArr = #v > 0 or next(v) == nil
        local parts, nx = {}, ind .. "  "
        if isArr then
            for _, x in ipairs(v) do parts[#parts + 1] = nx .. json(x, nx) end
            return #parts == 0 and "[]" or ("[\n" .. table.concat(parts, ",\n") .. "\n" .. ind .. "]")
        end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        for _, k in ipairs(keys) do parts[#parts + 1] = nx .. string.format("%q", k) .. ": " .. json(v[k], nx) end
        return "{\n" .. table.concat(parts, ",\n") .. "\n" .. ind .. "}"
    elseif t == "string" then
        return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
    elseif t == "number" then
        return (v == math.floor(v)) and string.format("%d", v) or string.format("%.3f", v)
    elseif t == "boolean" then return tostring(v) end
    return "null"
end
local fj = assert(io.open(OUT .. "/perf.json", "w"))
fj:write(json(result), "\n")
fj:close()

-- the report
local md = {}
local function p(s) md[#md + 1] = s end
p("# RUIN performance probe\n")
p(("Memory (KB): loaded %d, after the page tour %d, after an hour %d (hour growth %+d)."):format(
    result.memory_kb.loaded, result.memory_kb.toured, result.memory_kb.after_hour, result.memory_kb.growth_hour))
p(("CPU (simulator ms): event burst %.1f, OnUpdate 10 s %.1f, timers 1 h %.1f."):format(
    result.cpu_ms.event_burst, result.cpu_ms.onupdate_10s, result.cpu_ms.timers_hour))
p(("Addon calls only (without the simulator's own work): event burst %.1f, timers 1 h %.1f."):format(
    result.cpu_ms.event_burst_addon, result.cpu_ms.timers_hour_addon))
p(("Objects: %d frames, %d textures (%d plain colour), %d font strings. Timers pending: %d before the hour, %d after.\n"):format(
    counts.Frame, counts.Texture, colorTex, counts.FontString, pendingBefore, #Server.timers))
local function tbl(title, list, cols)
    p("## " .. title .. "\n")
    if #list == 0 then p("(none)\n"); return end
    local head, line = {}, {}
    for _, c in ipairs(cols) do head[#head + 1] = c; line[#line + 1] = "---" end
    p("| " .. table.concat(head, " | ") .. " |")
    p("| " .. table.concat(line, " | ") .. " |")
    for _, r in ipairs(list) do
        local cells = {}
        for _, c in ipairs(cols) do cells[#cells + 1] = tostring(r[c] == nil and "" or r[c]) end
        p("| " .. table.concat(cells, " | ") .. " |")
    end
    p("")
end
tbl("Hiccups (worst single call >= 4 ms)", result.hiccups, { "kind", "src", "worst_ms", "calls" })
tbl("Event handlers by CPU (UI client, burst)", only(result.events, 20), { "src", "calls", "cpu_ms", "worst_ms", "avg_us" })
p("## Busy events the addons listen to\n")
for _, b in ipairs(busyRegs) do p(("- %s (~%d/min): %s"):format(b.event, b.per_minute, table.concat(b.handlers, ", "))) end
p("")
tbl("OnUpdate (shown frames, 600 frames)", result.onupdate, { "src", "calls", "cpu_ms", "worst_ms", "avg_us" })
do
    local hidden = {}
    for _, o in ipairs(onUpdate) do if not o.shown then hidden[#hidden + 1] = o end end
    p(("OnUpdate scripts in all: %d (%d on hidden frames, which the game doesn't run).\n"):format(#onUpdate, #hidden))
end
tbl("Timers by CPU (one simulated hour)", only(result.timers, 20), { "src", "calls", "cpu_ms", "worst_ms", "avg_us" })
tbl("Timers still pending, by source", result.timers_pending.by_source, { "src", "n" })
tbl("Objects by window", result.objects.by_window, { "window", "frames", "textures", "fonts" })
tbl("Texture files loaded into 3+ textures", result.objects.texture_files_reused, { "file", "textures" })

-- compared with a previous run
if PREV then
    local f = io.open(PREV)
    if f then
        local s = f:read("*a"); f:close()
        local function num(path)
            local v = s:match('"' .. path .. '":%s*([%d%.%-]+)')
            return tonumber(v)
        end
        p("## Compared with the previous run\n")
        for _, k in ipairs({ "loaded", "toured", "after_hour", "growth_hour" }) do
            local old = num(k)
            if old then p(("- memory %s: %d -> %d KB (%+d)"):format(k, old, result.memory_kb[k], result.memory_kb[k] - old)) end
        end
        for _, k in ipairs({ "event_burst", "onupdate_10s", "timers_hour", "event_burst_addon", "timers_hour_addon" }) do
            local old = num(k)
            if old then p(("- CPU %s: %.1f -> %.1f ms"):format(k, old, result.cpu_ms[k])) end
        end
        for _, k in ipairs({ "Frame", "Texture", "FontString" }) do
            local old = num(k)
            if old then p(("- %s count: %d -> %d"):format(k, old, counts[k])) end
        end
        p("")
    end
end
if #Server.errors > 0 then
    p("## Errors during the probe\n")
    for i = 1, math.min(10, #Server.errors) do p("- " .. tostring(Server.errors[i]):sub(1, 300)) end
end
local fm = assert(io.open(OUT .. "/PERF.md", "w"))
fm:write(table.concat(md, "\n"), "\n")
fm:close()
print(("perf: loaded %d KB, hour growth %+d KB, burst %.1f ms, onupdate %.1f ms, timers %.1f ms, %d hiccups -> %s/PERF.md"):format(
    result.memory_kb.loaded, result.memory_kb.growth_hour, result.cpu_ms.event_burst, result.cpu_ms.onupdate_10s,
    result.cpu_ms.timers_hour, #hiccups, OUT))
