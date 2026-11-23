-- Lua 5.1 compatibility layer so the RUIN test harness runs on a Lua 5.3 interpreter (e.g. texlua).
-- Usage: texlua qa/lua51.lua <script.lua> [args...]   (see tests/qa/run_qa.sh)
if _VERSION == "Lua 5.1" then return end
unpack = unpack or table.unpack
loadstring = loadstring or load
table.getn = table.getn or function(t) return #t end
math.pow = math.pow or function(a, b) return a ^ b end
math.mod = math.mod or math.fmod
math.log10 = math.log10 or function(x) return math.log(x, 10) end
string.gfind = string.gfind or string.gmatch
table.maxn = table.maxn or function(t) local m = 0 for k in pairs(t) do if type(k) == "number" and k > m then m = k end end return m end
local function envIndex(f)
    local i = 1
    while true do
        local n = debug.getupvalue(f, i)
        if not n then return nil end
        if n == "_ENV" then return i end
        i = i + 1
    end
end
function setfenv(f, env)
    if type(f) == "number" then f = debug.getinfo(f + 1, "f").func end
    local i = envIndex(f)
    if i then debug.upvaluejoin(f, i, function() return env end, 1) end
    return f
end
function getfenv(f)
    if f == nil or f == 0 then return _G end
    if type(f) == "number" then f = debug.getinfo(f + 1, "f").func end
    local i = envIndex(f)
    if i then local _, v = debug.getupvalue(f, i) return v end
    return _G
end
-- 5.3 prints 3.0 for float results and 3 for ints; keep tostring/concat of whole floats Lua-5.1-like.
local rawtostring = tostring
function tostring(v)
    if math.type(v) == "float" and v == math.floor(v) and v > -1e15 and v < 1e15 then return string.format("%d", v) end
    return rawtostring(v)
end
local rawformat = string.format
string.format = function(f, ...)
    local a = { ... }
    local n = select("#", ...)
    -- %d with a whole float is fine in 5.3; non-integral floats error in 5.3 but truncate in 5.1
    local i = 0
    for spec in f:gmatch("%%[%-%+ #0]*%d*%.?%d*([%a%%])") do
        if spec ~= "%" then
            i = i + 1
            if (spec == "d" or spec == "i" or spec == "x" or spec == "X" or spec == "c" or spec == "o") and math.type(a[i]) == "float" then
                a[i] = a[i] >= 0 and math.floor(a[i]) or math.ceil(a[i])
            end
        end
    end
    return rawformat(f, table.unpack(a, 1, n))
end
