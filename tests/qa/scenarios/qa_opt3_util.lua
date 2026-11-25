-- QA (optimization round 3): base and new Util.lua must answer the same.
-- texlua qa/run51.lua /tmp/ruin-qa/opt-3/tools/qa_opt3_util.lua <base RUIN_Core> <new RUIN_Core>
local function load(dir)
    local ns = {}
    assert(loadfile(dir .. "/Util.lua"))("RUIN_Core", ns)
    return ns
end
local A, B = load(arg[1]), load(arg[2])
local bad, n = 0, 0
local function same(what, x, y)
    n = n + 1
    if x ~= y then bad = bad + 1; if bad < 20 then print("DIFF", what, tostring(x), tostring(y)) end end
end
math.randomseed(7)
local names = { "Alice Ash", "Alice Ash-Forever", "alice  ash", "ÅSA Öl-Realm-X", "", "Bob", "  x y z  ", "-lead", 12 }
for r = 1, 3 do   -- three passes so memo hits are compared too
    for _, v in ipairs(names) do same("norm " .. tostring(v), A.NormalizeName(v), B.NormalizeName(v)) end
    for i = 1, 700 do  -- more than the memo cap, so it starts over
        local s = "N" .. i .. (i % 3 == 0 and "-Realm" or "") .. (i % 5 == 0 and " Sur" or "")
        same("norm " .. s, A.NormalizeName(s), B.NormalizeName(s))
    end
end
local vers = { "0.1.10", "0.1.9", "1.0", "1.0.0", "0.7.2", nil, "", "abc", 3, 0.5, "2.0.0.1", "v1.2" }
for r = 1, 2 do
    for i = 1, 13 do for j = 1, 13 do
        same("cmp " .. tostring(vers[i]) .. "/" .. tostring(vers[j]), A.CompareVersions(vers[i], vers[j]), B.CompareVersions(vers[i], vers[j]))
    end end
    for i = 1, 150 do local v = "0." .. i .. ".1"; same("cmp " .. v, A.CompareVersions(v, "0.50"), B.CompareVersions(v, "0.50")) end
end
-- deserializer: real payloads, every truncation, and random byte flips
local function dump(v, d)
    d = d or 0
    if type(v) ~= "table" then return type(v) .. ":" .. tostring(v) end
    local ks = {}
    for k in pairs(v) do ks[#ks + 1] = k end
    table.sort(ks, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for _, k in ipairs(ks) do out[#out + 1] = dump(k) .. "=" .. dump(v[k], d + 1) end
    return "{" .. table.concat(out, ",") .. "}"
end
local samples = {
    { g = "Player-1-0001", v = "0.9.1", l = { 1, 2, "x" }, t = true, f = false, n = -3.5, deep = { a = { b = { c = {} } } } },
    "plain", 42, true, { [1] = "a", [2] = { "b", { "c" } } },
}
for _, smp in ipairs(samples) do
    local s = A.Serialize(smp)
    same("ser", s, B.Serialize(smp))
    for cut = 0, #s do
        local p = s:sub(1, cut)
        local va, ea = A.Deserialize(p); local vb, eb = B.Deserialize(p)
        same("cut " .. cut, dump(va) .. "|" .. tostring(ea), dump(vb) .. "|" .. tostring(eb))
    end
    for k = 1, 3000 do
        local pos = math.random(1, #s)
        local ch = string.char(math.random(0, 255))
        local p = s:sub(1, pos - 1) .. ch .. s:sub(pos + 1)
        local va, ea = A.Deserialize(p); local vb, eb = B.Deserialize(p)
        same("flip", dump(va) .. "|" .. tostring(ea), dump(vb) .. "|" .. tostring(eb))
    end
end
for _, p in ipairs({ "", "}", "{", "{}", "{}}", "s0:", "s-1:", "n;", "nnan;", "ninf;", "N", "T", "F", "x", "{s1:aN}", "{Ns1:a}", ("{"):rep(25) .. ("}"):rep(25) }) do
    local va, ea = A.Deserialize(p); local vb, eb = B.Deserialize(p)
    same("edge " .. p, dump(va) .. "|" .. tostring(ea), dump(vb) .. "|" .. tostring(eb))
end
print(("%d compared, %d different"):format(n, bad))
os.exit(bad == 0 and 0 or 1)
