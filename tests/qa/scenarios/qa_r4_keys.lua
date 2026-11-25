-- QA round 4: OPT2-1 key flows (export/import, signature, recovery code), OPT2-6 throttle wait. Diff between builds.
local here = os.getenv("QA_TESTS") or "."
dofile(here .. "/harness.lua")
local function out(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end print(table.concat(t, " | ")) end
local MODULES = { "RUIN_Finder" }
Server.guilds["Ashen Order"] = { { name = "Alice Ash", rank = 0, guid = "Player-1-00000001" } }
Server.guilds["Briar Fang"] = { { name = "Cara Cole", rank = 0, guid = "Player-1-00000002" } }
local alice = Server:NewClient({ name = "Alice Ash", guid = "Player-1-00000001", guild = "Ashen Order", rank = 0, modules = MODULES })
local cara = Server:NewClient({ name = "Cara Cole", guid = "Player-1-00000002", guild = "Briar Fang", rank = 0, modules = MODULES })
Server:Advance(10)
Server:Slash(alice, "key create RUIN")
Server:Slash(alice, "key addguild Briar Fang, 1, Briar")
Server:Advance(5)
local AO, CO = alice.ns.Org, cara.ns.Org
out("admin", AO:IsAdmin(), AO:Signed(), AO:IsAdminCharacter())
-- export / import by string
local k = AO:Get()
local text = AO.Encode(k)
local dec = CO.Decode(text)
out("decode", type(dec), dec and dec.org, dec and dec.pk == k.pk)
local ok, err = pcall(function() return CO:Apply(dec, "import") end)
Server:Advance(5)
out("import", ok, CO:Get() and CO:Get().org, CO:Signed(), CO:IsAdmin())
-- tampered key: change a guild rank without re-signing
local bad = cara.env.RUIN_API and nil
local t2 = CO.Decode(text)
if t2 then
    t2.guilds = t2.guilds or {}
    t2.org = t2.org .. "x"
    local okb, res, why = pcall(function() return CO:Apply(t2, "import") end)
    out("tampered", okb, tostring(res), tostring(why), CO:Get() and CO:Get().org)
end
local t3 = CO.Decode(text)
if t3 and type(t3.sig) == "string" then
    t3.sig = t3.sig:sub(1, -5) .. (t3.sig:sub(-4) == "AAAA" and "BBBB" or "AAAA")
    local okb, res, why = pcall(function() return CO:Apply(t3, "import") end)
    out("bad sig", okb, tostring(res), tostring(why))
end
-- recovery code
local code = AO:RecoveryCode()
out("code", code ~= nil, code and #code)
out("code on non-admin", CO:RecoveryCode())
out("recover wrong", CO:Recover("RUIN-AAAA-BBBB-CCCC-DDDD-EEEE-FFFF-GGGG-HHHH-IIII-JJJJ-KKKK-LLLL-MMMM"))
out("recover right", CO:Recover(code))
Server:Advance(5)
out("cara admin after recover", CO:IsAdmin())
-- alice loses her seed, then recovers
alice.ns.db.adminSeeds[k.org] = nil
out("alice admin without seed", AO:IsAdmin())
out("alice recover", AO:Recover(code))
out("alice admin again", AO:IsAdmin())
out("datakey", AO:DataKeyHex() ~= nil, AO:DataKeyHex() == CO:DataKeyHex())
out("officer hash", (alice.ns.Org.OfficerHash and alice.ns.Org.OfficerHash()) or "n/a")

-- OPT2-6: others sending
local T = alice.ns.Throttle
local C = alice.env.C_ChatInfo
out("others idle", T.OthersSending(2))
for i = 1, 30 do T.Note("C_ChatInfo.SendAddonMessage") end
out("others burst (who from harness stack)", T.OthersSending(2), T.OthersSending(4))
Server:Advance(3)
out("others after 3s", T.OthersSending(2), T.OthersSending(4))
Server:Advance(2)
out("others after 5s", T.OthersSending(2), T.OthersSending(4))
for i = 1, 450 do T.Note("C_ChatInfo.SendAddonMessage"); if i % 50 == 0 then Server:Advance(0.5) end end
out("others wrap", T.OthersSending(1), T.OthersSending(2), T.OthersSending(4))
out("recent", #T.Recent())
out("errors", #Server.errors, table.concat(Server.errors, " // "))
