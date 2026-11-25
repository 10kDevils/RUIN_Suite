-- Focused scenario: Waylaid Crate tooltip prices on a GameTooltip-like model.
-- Run from tests/: texlua qa/run51.lua /tmp/ruin-crate/scn/crate_scenario.lua
package.path = package.path
local here = "/home/claude/stage/tests"
arg[0] = here .. "/run_features.lua"
dofile(here .. "/harness.lua")

local pass, fail, notes = 0, 0, {}
local function check(c, label) if c then pass = pass + 1; print("  ok   " .. label) else fail = fail + 1; print("  FAIL " .. label) end end

local MODULES = { "RUIN_Exchange" }
Server.guilds["Ashen Order"] = { { name = "Alice Ash", rank = 0, guid = "Player-1-00000001" } }
local alice = Server:NewClient({ name = "Alice Ash", guid = "Player-1-00000001", guild = "Ashen Order", rank = 0, modules = MODULES })
Server:Advance(10)
local env = alice.env
local ex = env.RUIN_API:GetModule("Exchange")
local db = env.RUIN_ExchangeDB
local hook = alice.tooltipHooks[1]
check(hook ~= nil, "Exchange registered a tooltip post-call")

---------------------------------------------------------------------------
-- text measuring (same rules as tests/render/frames.lua; a coin icon ~ font height + 2)
local function plainT(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("|T.-|t", "WW"):gsub("|n", "\n"):gsub("\194\160", " ")
    return s
end
local function lineW(line, size)
    local w = 0
    for ch in line:gmatch(".") do
        if ch:match("[A-Z0-9MW@%%]") then w = w + 0.66 elseif ch:match("[iljI%.,:;'!|]") then w = w + 0.30
        elseif ch == " " then w = w + 0.30 else w = w + 0.54 end
    end
    return w * size
end
local function widest(text, size)
    local m = 0
    for l in (plainT(text) .. "\n"):gmatch("(.-)\n") do m = math.max(m, lineW(l, size)) end
    return m
end

---------------------------------------------------------------------------
-- GameTooltip model: lines are TextLeftN font strings; on Show the tooltip
-- sizes to max(min width - pad, widest unwrapped line, wrapped lines capped at
-- WRAP_DEFAULT) and wrapping lines wrap within that width.
local PAD, WRAP_DEFAULT = 20, 220
local function newFS(name)
    local fs = { _text = "", _wrap = true, _size = 12, _w = nil, _name = name }
    function fs:SetText(t) self._text = t or "" end
    function fs:GetText() return self._text ~= "" and self._text or nil end
    function fs:SetWordWrap(v) self._wrap = v and true or false end
    function fs:GetWordWrap() return self._wrap end
    function fs:GetFont() return "Fonts\\FRIZQT__.TTF", self._size, "" end
    function fs:SetFont(_, s) self._size = s or self._size end
    function fs:GetStringWidth() return widest(self._text, self._size) end
    function fs:SetWidth(w) self._w = (w and w > 0) and w or nil; self._userW = self._w end
    function fs:GetWidth() return self._w or self:GetStringWidth() end
    function fs:Hide() end
    function fs:Show() end
    return fs
end

local tip = { _lines = {}, _hooks = {}, _shown = false, _minW = 0, _w = 0, _item = nil }
env.RuinTestTip = tip
local NAME = "RuinTestTip"
function tip:GetName() return NAME end
function tip:NumLines() return #self._lines end
function tip:HookScript(k, f) self._hooks[k] = self._hooks[k] or {}; table.insert(self._hooks[k], f) end
local function fire(k) for _, f in ipairs(tip._hooks[k] or {}) do f(tip) end end
function tip:SetMinimumWidth(w) self._minW = w or 0 end
function tip:GetWidth() return self._w end
function tip:SetWidth(w) self._w = w end
function tip:CreateFontString() return newFS("measure") end
function tip:GetItem() if self._item then return self._item[1], self._item[2] end end
function tip:AddLine(text, r, g, b, wrap)
    local i = #self._lines + 1
    local fs = env[NAME .. "TextLeft" .. i]
    if not fs then fs = newFS("L" .. i); env[NAME .. "TextLeft" .. i] = fs end
    fs:SetText(text); fs._wrap = wrap and true or false   -- the game sets wrap per AddLine
    self._lines[i] = fs
end
function tip:AddDoubleLine(l, r) self:AddLine(tostring(l) .. "    " .. tostring(r)) end
function tip:ClearLines()
    for _, fs in ipairs(self._lines) do fs:SetText("") end
    self._lines = {}; self._item = nil
    fire("OnTooltipCleared")
end
function tip:Layout()
    local w = math.max(0, self._minW - PAD)
    for _, fs in ipairs(self._lines) do
        local sw = fs:GetStringWidth()
        if fs._wrap then sw = math.min(sw, WRAP_DEFAULT) end
        if fs._userW and fs._userW > sw then sw = fs._userW end
        w = math.max(w, sw)
    end
    self._w = w + PAD
    for _, fs in ipairs(self._lines) do fs._w = fs._userW or w end
    self._inner = w
end
function tip:Show()
    self:Layout()
    if not self._shown then self._shown = true; fire("OnShow") end
end
function tip:Hide() self._shown = false; self:ClearLines() end
function tip:IsShown() return self._shown end
function tip:GetHeight() return 100 end
function tip:SetHeight() end

-- show an item: clear, add the game's lines, run post-calls, show
local function showItem(id, name, lines)
    tip:ClearLines()
    tip._item = { name, "|cffffffff|Hitem:" .. id .. "::|h[" .. name .. "]|h|r" }
    tip:AddLine(name)
    for _, l in ipairs(lines) do tip:AddLine(l[1], 1, 1, 1, l[2]) end
    hook(tip, nil)
    tip:Show()
end
local function showSpell(lines)
    tip:ClearLines()
    for _, l in ipairs(lines) do tip:AddLine(l[1], 1, 1, 1, l[2]) end
    tip:Show()
end

-- visual rows of a font string (lines, wrapped within the tooltip's inner width)
local function rows(fs)
    local out = {}
    for l in (fs._text .. "\n"):gmatch("(.-)\n") do
        local w = lineW(plainT(l), fs._size)
        local cap = fs._w or tip._inner
        -- only bundle rows count: the sentence above them is meant to wrap
        local row = plainT(l):find("^%s*%-%s*%d+%s") ~= nil
        if not row then out[#out + 1] = { text = l, w = w }
        elseif fs._wrap and w > cap + 0.5 then out[#out + 1] = { text = l, wrapped = true, w = w }
        else out[#out + 1] = { text = l, w = w, over = (w > tip._inner + 0.5) } end
    end
    return out
end

---------------------------------------------------------------------------
-- items: some the game knows by name, some never seen (CrateGoods fallback)
local ITEMS = {
    { 11176, "Dream Dust", true }, { 11175, "Greater Nether Essence", false }, { 14343, "Small Brilliant Shard", false },
    { 14344, "Large Brilliant Shard", true }, { 7911, "Truesilver Ore", true }, { 10620, "Thorium Ore", false },
    { 11370, "Dark Iron Ore", false }, { 13463, "Dreamfoil", true }, { 13465, "Mountain Silversage", false },
    { 13466, "Plaguebloom", false }, { 13467, "Icecap", true },
}
local priceSets = {
    { name = "2c each (2c..)", f = function(i) return i == 1 and 1 or 2 end },
    { name = "mid (1s-90s)", f = function(i) return 100 * (i * 7) end },
    { name = "99g bundle", f = function(i, n) return math.floor(990000 / n) + (i % 3) end },
    { name = "huge per unit 99g99s99c", f = function(i, n) return 999999 end },
}
for _, it in ipairs(ITEMS) do
    if it[3] then alice.items[it[1]] = { name = it[2], link = "|cffffffff|Hitem:" .. it[1] .. "::|h[" .. it[2] .. "]|h|r", q = 1, cls = "Trade Goods" } end
end
local USE = "Use: Fill the crate with any bundle from the following list:"
local CRATES = {
    { 900001, "Waylaid Crate: Artisan Curiosities", { { 20, "Dream Dust" }, { 4, "Greater Nether Essence" }, { 6, "Small Brilliant Shard" }, { 2, "Large Brilliant Shard" } } },
    { 900002, "Waylaid Crate: Artisan Ore", { { 10, "Truesilver Ore" }, { 20, "Thorium Ore" }, { 20, "Dark Iron Ore" } } },
    { 900003, "Waylaid Crate: Flowering Artisan Herbs", { { 20, "Dreamfoil" }, { 20, "Mountain Silversage" }, { 20, "Plaguebloom" }, { 20, "Icecap" } } },
}
local idOf = {}
for _, it in ipairs(ITEMS) do idOf[it[2]] = it[1] end
local function crateLines(c)
    local t = { USE }
    for _, b in ipairs(c[3]) do t[#t + 1] = ("- %d %s"):format(b[1], b[2]) end
    return { { "Binds when picked up", false }, { "Unique", false }, { table.concat(t, "\n"), true }, { "Sell Price: 1c", false } }
end

local maxTipW = 0
for _, ps in ipairs(priceSets) do
    for i, it in ipairs(ITEMS) do
        db.prices[it[1]] = { p = ps.f(i, 20), t = env.GetServerTime() }
    end
    for _, c in ipairs(CRATES) do
        Server.errors = {}
        showItem(c[1], c[2], crateLines(c))
        local fs = env[NAME .. "TextLeft4"]
        local txt = fs._text
        local label = c[2]:match(": (.+)") .. " @ " .. ps.name
        check(#Server.errors == 0, label .. ": no Lua errors")
        local rs = rows(fs)
        local bad = {}
        for _, r in ipairs(rs) do
            if r.wrapped then bad[#bad + 1] = "WRAPS: " .. env.RUIN_API.Widgets.PlainMoney(r.text) .. (" (%.0f > %.0f)"):format(r.w, tip._inner) end
            if r.over then bad[#bad + 1] = "OVERFLOWS: " .. env.RUIN_API.Widgets.PlainMoney(r.text) .. (" (%.0f > %.0f)"):format(r.w, tip._inner) end
        end
        check(#bad == 0, label .. ": no row wraps or overflows (tip " .. tip._w .. "px)")
        for _, b in ipairs(bad) do print("       " .. b) end
        maxTipW = math.max(maxTipW, tip._w)
        for _, b in ipairs(c[3]) do
            local want = env.RUIN_API.Widgets.PlainMoney(env.RUIN_API.Widgets.Money(db.prices[idOf[b[2]]].p * b[1]))
            local got
            for l in (txt .. "\n"):gmatch("(.-)\n") do
                local nm, money = l:gsub("\194\160", " "):match("^%- %d+ (.-)  (.+)$")
                if nm == b[2] then got = env.RUIN_API.Widgets.PlainMoney(money) end
            end
            check(got == want, ("%s: %d %s priced %s (got %s)"):format(label, b[1], b[2], want, tostring(got)))
        end
        -- shown twice in place (a second post-call on the same lines, e.g. a refresh that doesn't rebuild)
        local before = fs._text
        hook(tip, nil); tip:Show()
        local _, n = fs._text:gsub("MoneyFrame", "")
        local _, n0 = before:gsub("MoneyFrame", "")
        check(n == n0, label .. ": a second post-call on the same lines doesn't price twice")
        local rs2 = rows(fs)
        local wrapped2 = false
        for _, r in ipairs(rs2) do if r.wrapped or r.over then wrapped2 = true end end
        check(not wrapped2, label .. ": after a second post-call the prices still stay on their lines (wrap="
            .. tostring(fs._wrap) .. ", min width=" .. tip._minW .. ")")
        -- fresh show of the same crate (normal path)
        tip:Hide()
        showItem(c[1], c[2], crateLines(c))
        local _, n2 = env[NAME .. "TextLeft4"]._text:gsub("MoneyFrame", "")
        check(n2 == n0, label .. ": shown again, priced once (" .. n2 .. " coins vs " .. n0 .. ")")
    end
end
print(("widest crate tooltip: %dpx"):format(maxTipW))

-- non-crate tooltips after a crate: normal width and wrapping
print("after a crate")
showItem(900003, CRATES[3][2], crateLines(CRATES[3]))
local crateW = tip._w
-- spell tooltip (no item post-call; only OnTooltipCleared)
local long = "Increases the damage done by your Fire spells by up to 20 and lets you breathe under water for longer than usual."
showSpell({ { "Fireball", false }, { "Rank 1", false }, { "30 Mana", false }, { long, true } })
local spellW = tip._w
showSpell({ { "Fireball", false }, { "Rank 1", false }, { "30 Mana", false }, { long, true } })
check(tip._minW == 0, "spell after a crate: no minimum width left (" .. tip._minW .. ")")
check(env[NAME .. "TextLeft4"]._userW == nil, "spell after a crate: line 4 has no fixed width left from CrateFit ("
    .. tostring(env[NAME .. "TextLeft4"]._userW) .. ")")
check(env[NAME .. "TextLeft4"]._wrap == true, "spell after a crate: its long line wraps")
local fresh = tip._w
print(("  crate %dpx, spell right after %dpx, spell again %dpx"):format(crateW, spellW, fresh))
check(spellW == fresh, "the spell tooltip right after a crate has its normal width")

-- crate shown with the tooltip hidden first: CrateFit on OnShow
tip:Hide()
showItem(900001, CRATES[1][2], crateLines(CRATES[1]))
showItem(5191, "Cruel Barb", { { "Binds when equipped", false }, { "Equip: " .. long, true } })
local normalW
do local w = tip._w; tip:Hide(); showItem(5191, "Cruel Barb", { { "Binds when equipped", false }, { "Equip: " .. long, true } }); normalW = tip._w
   check(w == normalW, ("item after a crate has its normal width (%d vs %d)"):format(w, normalW)) end
check(env[NAME .. "TextLeft3"]._wrap == true, "item after a crate: Equip line wraps")

-- the hidden case: CrateReset restores wrap=true even on a line the game made unwrapped
print("wrap state restore")
showItem(900002, CRATES[2][2], { { "Binds when picked up", false }, { table.concat({ USE, "- 10 Truesilver Ore" }, "\n"), true } })
local fs3 = env[NAME .. "TextLeft3"]
local beforeReset = fs3._wrap
local function fakeClear() for _, f in ipairs(tip._hooks.OnTooltipCleared or {}) do f(tip) end end
fakeClear()
print("  line 3 wrap after crate reset: " .. tostring(fs3._wrap) .. " (was " .. tostring(beforeReset) .. ")")

print(("\n%d passed, %d failed"):format(pass, fail))

print("diagnostics")
-- 1) second post-call on the same lines: do rows actually wrap?
for _, ps in ipairs({ priceSets[3] }) do
    for i, it in ipairs(ITEMS) do db.prices[it[1]] = { p = ps.f(i, 20), t = env.GetServerTime() } end
end
tip:Hide()
showItem(900002, CRATES[2][2], crateLines(CRATES[2]))
local w1 = tip._w
hook(tip, nil); tip:Show()
local fs = env[NAME .. "TextLeft4"]
print(("  first show %dpx, after second post-call %dpx, wrap=%s"):format(w1, tip._w, tostring(fs._wrap)))
for _, r in ipairs(rows(fs)) do print(("    %-6s %3.0fpx  %s"):format(r.wrapped and "WRAPS" or "", r.w, env.RUIN_API.Widgets.PlainMoney(r.text))) end
-- 2) CrateFit when the game laid the line out narrower than needed; is the fixed width left behind?
tip:Hide()
showItem(900001, CRATES[1][2], crateLines(CRATES[1]))
local f4 = env[NAME .. "TextLeft4"]
f4._w = 150; tip._shown = false; tip._w = 170
for _, f in ipairs(tip._hooks.OnShow or {}) do f(tip) end
print(("  CrateFit: line 4 width %s (user %s), tip %s"):format(tostring(f4._w), tostring(f4._userW), tostring(tip._w)))
tip:Hide()
showSpell({ { "Frost Nova", false }, { "Rank 1", false }, { "Short", false }, { "Hi", false } })
print(("  spell after CrateFit: line 4 fixed width left = %s, tip width %s (normal would be ~%d)"):format(tostring(f4._userW), tostring(tip._w), math.ceil(widest("Frost Nova", 12)) + PAD))
print("diagnostic: second post-call at the widest prices")
for i, it in ipairs(ITEMS) do db.prices[it[1]] = { p = priceSets[4].f(i, 20), t = env.GetServerTime() } end
for _, c in ipairs(CRATES) do
    tip:Hide(); showItem(c[1], c[2], crateLines(c)); local w1 = tip._w
    hook(tip, nil); tip:Show()
    local n = 0
    for _, r in ipairs(rows(env[NAME .. "TextLeft4"])) do if r.wrapped then n = n + 1; print("    WRAPS " .. env.RUIN_API.Widgets.PlainMoney(r.text) .. (" %.0f > %.0f"):format(r.w, tip._inner)) end end
    print(("  %s: %dpx -> %dpx, %d priced rows wrap"):format(c[2], w1, tip._w, n))
end

---------------------------------------------------------------------------
-- QA round 3 additions: heights, refresh without OnShow, what is measured
print("\nround 3 checks")
local p3, f3 = 0, 0
local function check3(c, label) if c then p3 = p3 + 1; print("  ok   " .. label) else f3 = f3 + 1; print("  FAIL " .. label) end end
local ROW = 14
-- give the font strings heights: auto (rows at the current width) unless set
local function nrows(fs, width)
    local n = 0
    for l in (fs._text .. "\n"):gmatch("(.-)\n") do
        local w = lineW(plainT(l), fs._size)
        n = n + ((fs._wrap and width and width > 0) and math.max(1, math.ceil(w / width - 1e-6)) or 1)
    end
    return n
end
for i = 1, 12 do
    local fs = env[NAME .. "TextLeft" .. i]
    if not fs then fs = newFS("L" .. i); env[NAME .. "TextLeft" .. i] = fs end
    function fs:GetStringHeight() return nrows(self, self._w) * ROW end
    function fs:GetHeight() return self._h or self:GetStringHeight() end
    function fs:SetHeight(h) self._h = (h and h > 0) and h or nil end
end
local function truncated(fs) return fs._h and fs:GetStringHeight() > fs._h + 0.5 end
for i, it in ipairs(ITEMS) do db.prices[it[1]] = { p = priceSets[3].f(i, 20), t = env.GetServerTime() } end

-- A) the game laid the crate line out narrower than PriceCrate asked (min width
-- not applied, e.g. layout ran first): CrateFit fixes the width and the height
local realMin = tip.SetMinimumWidth
tip:Hide()
tip.SetMinimumWidth = nil
showItem(900002, CRATES[2][2], crateLines(CRATES[2]))
tip.SetMinimumWidth = realMin
local L4 = env[NAME .. "TextLeft4"]
print(("  crate fitted: line 4 width %s, fixed height %s (rows %d)"):format(tostring(L4._w), tostring(L4._h), nrows(L4, L4._w)))
-- next tooltip: a long wrapped line lands on line 4
tip:Hide()
local long4 = "Equip: Increases the damage done by your Fire spells by up to 20 and lets you breathe under water for longer than usual, and more besides so it runs to several rows."
showItem(5191, "Cruel Barb", { { "Binds when equipped", false }, { "Unique", false }, { long4, true } })
print(("  next item: line 4 fixed height %s, needs %d (rows %d at %s)"):format(tostring(L4._h), L4:GetStringHeight(), nrows(L4, L4._w), tostring(L4._w)))
check3(not truncated(L4), "the line CrateFit shortened isn't left with a fixed height that cuts the next tooltip's text")

-- B) refreshed in place (bag / auction house rebuild without hiding): the fit
-- applied on first show is undone and not redone
for i = 1, 12 do local f = env[NAME .. "TextLeft" .. i]; if f then f._h = nil end end
for i, it in ipairs(ITEMS) do db.prices[it[1]] = { p = priceSets[4].f(i, 20), t = env.GetServerTime() } end
local SHORTUSE = { { "Binds when picked up", false }, { "Unique", false }, { "Use: Fill it:\n- 4 Greater Nether Essence\n- 6 Small Brilliant Shard", true } }
CRATES[2] = { 900002, CRATES[2][2], CRATES[2][3] }
local realLines = crateLines
crateLines = function() return SHORTUSE end
tip:Hide()
tip.SetMinimumWidth = nil
showItem(900002, CRATES[2][2], crateLines(CRATES[2]))
local wFirst = L4._userW
-- in place: clear + lines + post-call + Show, but no Hide (OnShow doesn't fire)
tip:ClearLines()
tip._item = { CRATES[2][2], "|cffffffff|Hitem:900002::|h[x]|h|r" }
tip:AddLine(CRATES[2][2]); for _, l in ipairs(crateLines(CRATES[2])) do tip:AddLine(l[1], 1, 1, 1, l[2]) end
hook(tip, nil); tip:Show()
Server:Advance(0.1)        -- the next frame, when Exchange fits a tooltip rebuilt in place
tip.SetMinimumWidth = realMin
crateLines = realLines
local wraps = 0
for _, r in ipairs(rows(L4)) do if r.wrapped and r.text:find("^%- ") then wraps = wraps + 1 end end
print(("  first show line width %s, after in-place refresh %s, priced rows wrapping %d"):format(tostring(wFirst), tostring(L4._userW), wraps))
check3(wraps == 0, "an in-place refresh (no OnShow) keeps the prices on their bundles when the minimum width isn't honoured")

-- C) only the bundle rows set the width: the Use: sentence keeps wrapping as usual
tip:Hide()
local longUse = "Use: Fill the crate with any one bundle from the following list and bring it to a Supply Officer of your faction for a reward:"
showItem(900002, CRATES[2][2], { { "Binds when picked up", false }, { longUse .. "\n- 10 Truesilver Ore\n- 20 Thorium Ore", true } })
local bundleW = 0
for l in (env[NAME .. "TextLeft3"]._text .. "\n"):gmatch("(.-)\n") do if l:find("^%- ") then bundleW = math.max(bundleW, lineW(plainT(l), 12)) end end
print(("  widest bundle row %.0fpx, Use: sentence %.0fpx, minimum width %s, tooltip %s"):format(bundleW, lineW(longUse, 12), tostring(tip._minW), tostring(tip._w)))
check3(tip._minW <= math.max(bundleW + 70, WRAP_DEFAULT + PAD), "the minimum width follows the bundle rows, not the unwrapped Use: sentence")

print(("\nround 3: %d passed, %d failed"):format(p3, f3))
