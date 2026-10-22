-- RUIN feature batch tests (0.2.x roadmap features)
local here = arg[0]:match("^(.*)/") or "."
dofile(here .. "/harness.lua")

local pass, fail = 0, 0
local function check(cond, label)
    if cond then pass = pass + 1; print("  ok   " .. label)
    else fail = fail + 1; print("  FAIL " .. label) end
end
local function chatHas(c, needle)
    for _, line in ipairs(c.chat) do if line:find(needle, 1, true) then return true end end
    return false
end
local function errorsSoFar(label)
    check(#Server.errors == 0, label .. ": no Lua errors")
    for _, e in ipairs(Server.errors) do print("       " .. e) end
    Server.errors = {}
end
local function openAllSubTabs(c, page)
    -- open a module page and click through each of its sub-tabs
    c.env.RUIN_API:OpenTab(page)
    for _, st in ipairs(c.subtabs) do
        for j = 1, #st.buttons do st:Select(j) end
        st:Select(1)
    end
end
_G.openAllSubTabs = openAllSubTabs

local MODULES = { "RUIN_Finder", "RUIN_Pathfinder", "RUIN_Codex", "RUIN_Exchange", "RUIN_Muster" }

Server.guilds["Ashen Order"] = { { name = "Alice Ash", rank = 0, guid = "Player-1-00000001" } }
Server.guilds["Briar Fang"] = {
    { name = "Cara Cole", rank = 0, guid = "Player-1-00000002" },
    { name = "Eve Ember", rank = 2, guid = "Player-1-00000004" },
}
local alice = Server:NewClient({ name = "Alice Ash", guid = "Player-1-00000001", guild = "Ashen Order", rank = 0, modules = MODULES })
local cara = Server:NewClient({ name = "Cara Cole", guid = "Player-1-00000002", guild = "Briar Fang", rank = 0, modules = MODULES })
local eve = Server:NewClient({ name = "Eve Ember", guid = "Player-1-00000004", guild = "Briar Fang", rank = 2, modules = MODULES })
Server:Advance(10)
Server:Slash(alice, "key create RUIN")
Server:Slash(alice, "key addguild Briar Fang, 1, Briar")
alice.ns.Org:SendFullKey("Cara Cole")
Server:Advance(3)
cara.env.RUIN_ConfirmDialog.onAccept()
Server:Advance(90)
check(alice.ns.Comms:IsJoined("ORG") and cara.ns.Comms:IsJoined("ORG") and eve.ns.Comms:IsJoined("ORG"), "three clients connected")
errorsSoFar("setup")

-- Tables shared with the per-module sections below
-- A stand-in for Questie's database, shaped like Questie's own API
-- (QuestieDB.GetQuest, QuestieDB:GetNPC, ZoneDB:GetUiMapIdByAreaId ...).
--   data = { quests = { [id] = { name, level, req, starts = { npc }, ends = { npc }, obj = { {Type, Id, Text} }, zone } },
--            npcs = { [id] = { name, spawns = { [areaId] = { { x, y } } } } }, area = { [areaId] = uiMapId }, done = { [id] = true } }
local function fakeQuestie(c, data)
    local DB = { QuestPointers = {} }
    function DB.GetQuest(id)
        local q = data.quests[id]
        if not q then return nil end
        return { name = q.name, level = q.level, requiredLevel = q.req, Starts = { NPC = q.starts }, Finisher = { NPC = q.ends },
                 ObjectiveData = q.obj or {}, objectivesText = { q.text }, zoneOrSort = q.zone }
    end
    function DB:GetNPC(id) return data.npcs[id] end
    function DB:GetObject() return nil end
    function DB:GetItem() return nil end
    function DB.QueryQuestSingle(id, field) if field == "zoneOrSort" then return data.quests[id] and data.quests[id].zone end end
    function DB.IsDoable() return true end
    for id in pairs(data.quests) do DB.QuestPointers[id] = true end
    local Zone = {}
    function Zone:GetUiMapIdByAreaId(a) return data.area[a] end
    function Zone:GetAreaIdByUiMapId(m) for a, mm in pairs(data.area) do if mm == m then return a end end end
    c.env.QuestieLoader = { ImportModule = function(_, name) return name == "QuestieDB" and DB or Zone end }
    c.env.Questie = { db = { char = { complete = data.done or {} } } }
    c.mns.RUIN_Pathfinder.QB.Forget()
end

T = { alice = alice, cara = cara, eve = eve, check = check, chatHas = chatHas, errorsSoFar = errorsSoFar,
      openAllSubTabs = openAllSubTabs, fakeQuestie = fakeQuestie }

---------------------------------------------------------------------------
print("Muster")
do
    local mu = alice.env.RUIN_API:GetModule("Muster")
    local at = os.date("%Y-%m-%d %H:%M", os.time() + 3 * 3600)
    local ev = mu:Create("Molten Core", at, { kind = "Raid", desc = "Bring fire resist", size = "10",
                                              need = { 2, 3, 5 }, weekly = true })
    Server:Advance(3)
    local cev = cara.env.RUIN_MusterDB.events[ev.id]
    check(cev and cev.desc == "Bring fire resist" and cev.need[2] == 3 and cev.weekly, "description, role limits and weekly reached Cara")
    cara.env.RUIN_API:GetModule("Muster"):SignUp(ev.id, "T")
    eve.env.RUIN_API:GetModule("Muster"):SignUp(ev.id, "H")
    Server:Advance(3)
    local slots = alice.env.RUIN_API:GetModule("Muster"):GetOpenSlots()
    check(#slots == 1 and slots[1].open.T == 1 and slots[1].open.H == 2 and slots[1].open.D == 5, "open slots counted for Finder")
    -- soft reserve
    cara.env.RUIN_API:GetModule("Muster"):Reserve(ev.id, "|cffa335ee|Hitem:17076::|h[Bonereaver's Edge]|h|r")
    eve.env.RUIN_API:GetModule("Muster"):Reserve(ev.id, "Bonereaver's Edge")
    Server:Advance(3)
    local s = alice.env.RUIN_MusterDB.events[ev.id].signups[cara.guid]
    check(s and s.sr and s.sr:find("Bonereaver"), "Cara's soft reserve reached Alice")
    check(s.role == "T", "reserving kept Cara's role")
    -- roster
    mu:AutoRoster(ev.id)
    local r = alice.env.RUIN_MusterDB.events[ev.id].roster
    check(r and r[cara.guid] == 1 and r[eve.guid] == 2, "auto-fill spread the tank and healer (" .. tostring(r and r[cara.guid]) .. "," .. tostring(r and r[eve.guid]) .. ")")
    mu:CycleGroup(ev.id, eve.guid)
    mu:PublishRoster(ev.id)
    Server:Advance(3)
    check(chatHas(eve, "you are in group 1") or chatHas(eve, "you are in the bench") or chatHas(eve, "you are in group"), "Eve told her group")
    check(cara.env.RUIN_MusterDB.events[ev.id].roster ~= nil, "roster reached Cara")
    -- page and sub-tabs (alice is an officer)
    openAllSubTabs(alice, "Muster")
    openAllSubTabs(eve, "Muster")
    -- weekly: once the event starts, next week is posted
    local before = 0
    for _ in pairs(cara.env.RUIN_MusterDB.events) do before = before + 1 end
    alice.env.RUIN_MusterDB.events[ev.id].at = alice.env.GetServerTime() - 10
    Server:Advance(35)
    local nextId = ev.id .. "w1"
    check(alice.env.RUIN_MusterDB.events[nextId] and cara.env.RUIN_MusterDB.events[nextId], "next week's event posted to RUIN")
    check(cara.env.RUIN_MusterDB.events[nextId].at - ev.at == 7 * 86400, "a week later")
    errorsSoFar("muster")
end

for _, extra in ipairs({ "/run_features_more.lua", "/run_features_brief.lua", "/run_macros.lua" }) do
    local path = here .. extra
    local fh = io.open(path, "r")
    if fh then fh:close(); dofile(path) end
end

print(("\n%d passed, %d failed, %d addon messages sent"):format(pass + (T.pass or 0), fail + (T.fail or 0), Server.sent))
os.exit((fail + (T.fail or 0)) == 0 and 0 or 1)
