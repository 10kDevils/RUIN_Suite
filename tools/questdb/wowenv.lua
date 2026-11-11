-- Just enough of the WoW client to load QuestieDB's baked Forever database
-- offline (texlua + compat): the TOC metadata store, C_EncodingUtil (Base64,
-- zlib, CBOR) and the few globals its files touch.
local QDB = assert(arg[1], "path to the QuestieDB folder")
local LibDeflate = dofile(arg[2])

-- the TOC metadata: "## X-Key: value"
local META = {}
for line in io.lines(QDB .. "/QuestieDB_Forever.toc") do
    local k, v = line:match("^## ([^:]+): ?(.*)$")
    if k then META[k] = v:gsub("\r$", "") end
end
C_AddOns = { GetAddOnMetadata = function(_, key) return META[key] end }
GetAddOnMetadata = C_AddOns.GetAddOnMetadata

-- Base64
local B64 = {}
local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
for i = 1, 64 do B64[chars:byte(i)] = i - 1 end
local function decodeBase64(s)
    s = s:gsub("[^%w%+/]", "")
    local out, bits, nbits = {}, 0, 0
    for i = 1, #s do
        bits = (bits << 6) | B64[s:byte(i)]
        nbits = nbits + 6
        if nbits >= 8 then
            nbits = nbits - 8
            out[#out + 1] = string.char((bits >> nbits) & 0xFF)
        end
    end
    return table.concat(out)
end

-- CBOR (RFC 8949): what the database uses
local function decodeCBOR(s)
    local pos = 1
    local function byte() local b = s:byte(pos); pos = pos + 1; return b end
    local function uint(info)
        if info < 24 then return info end
        if info == 24 then return byte() end
        if info == 25 then local v = string.unpack(">I2", s, pos); pos = pos + 2; return v end
        if info == 26 then local v = string.unpack(">I4", s, pos); pos = pos + 4; return v end
        if info == 27 then local v = string.unpack(">I8", s, pos); pos = pos + 8; return v end
        error("bad CBOR length " .. info)
    end
    local item
    function item()
        local ib = byte()
        local major, info = ib >> 5, ib & 31
        if major == 0 then return uint(info)
        elseif major == 1 then return -1 - uint(info)
        elseif major == 2 or major == 3 then
            local n = uint(info); local v = s:sub(pos, pos + n - 1); pos = pos + n; return v
        elseif major == 4 then
            local n, t = uint(info), {}
            for i = 1, n do t[i] = item() end
            return t
        elseif major == 5 then
            local n, t = uint(info), {}
            for _ = 1, n do local k = item(); t[k] = item() end
            return t
        elseif major == 6 then uint(info); return item()
        else
            if info == 20 then return false elseif info == 21 then return true
            elseif info == 22 or info == 23 then return nil
            elseif info == 25 then
                local h = string.unpack(">I2", s, pos); pos = pos + 2
                local sign, e, m = (h >> 15) == 1 and -1 or 1, (h >> 10) & 31, h & 1023
                if e == 0 then return sign * m * 2 ^ -24 end
                if e == 31 then return m == 0 and sign * math.huge or 0 / 0 end
                return sign * (1 + m / 1024) * 2 ^ (e - 15)
            elseif info == 26 then local v = string.unpack(">f", s, pos); pos = pos + 4; return v
            elseif info == 27 then local v = string.unpack(">d", s, pos); pos = pos + 8; return v end
            error("bad CBOR simple " .. info)
        end
    end
    return item()
end

C_EncodingUtil = {
    DecodeBase64 = decodeBase64,
    DecompressString = function(s, method)
        return LibDeflate:DecompressZlib(s) or LibDeflate:DecompressDeflate(s)
    end,
    DeserializeCBOR = decodeCBOR,
}
-- the rest of the client, as little as the files need
GetLocale = function() return "enUS" end
GetBuildInfo = function() return "1.60.1", "1", "Nov 1 2026", 16001 end
WOW_PROJECT_ID, WOW_PROJECT_CLASSIC, WOW_PROJECT_MAINLINE = 1, 2, 1
C_Timer = { After = function(_, f) end, NewTicker = function() return { Cancel = function() end } end }
CreateFrame = function() local f = {}; return setmetatable(f, { __index = function() return function() end end }) end
print = print
time = os.time
debugprofilestop = function() return os.clock() * 1000 end
strsplit = function(sep, s) local out = {}; for p in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = p end; return table.unpack(out) end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
wipe = function(t) for k in pairs(t) do t[k] = nil end; return t end
tinsert, tremove = table.insert, table.remove
hooksecurefunc = function() end

-- load the addon's files in TOC order, each with (addonName, namespace)
LibQuestieDB_NS = {}
for line in io.lines(QDB .. "/QuestieDB_Forever.toc") do
    line = line:gsub("\r$", "")
    if line ~= "" and not line:match("^#") then
        local path = QDB .. "/" .. line:gsub("\\", "/")
        local chunk, err = loadfile(path)
        if not chunk then error(err) end
        local ok, e = pcall(chunk, "QuestieDB", LibQuestieDB_NS)
        if not ok then io.stderr:write("load " .. line .. ": " .. tostring(e) .. "\n") end
    end
end
