-- Builds the RUIN window outside the game with sample org data and writes a
-- layout dump (JSON) of every page and sub-page, for render.py to draw.
--   lua render/render.lua <outdir>
local here = arg[0]:match("^(.*)/") or "."
local OUT = arg[1] or (here .. "/out")
arg[1] = nil
package.path = here .. "/?.lua;" .. package.path
local F = dofile(here .. "/frames.lua")
dofile(here .. "/../harness.lua")

local MODULES = { "RUIN_Finder", "RUIN_Pathfinder", "RUIN_Codex", "RUIN_Exchange", "RUIN_Muster" }
Server.guilds["Ashen Order"] = {
    { name = "Alice Ash", rank = 0, rankName = "Guild Master", guid = "Player-1-00000001", level = 60, class = "WARLOCK",
      className = "Warlock", zone = "Stormwind City", note = "Raid lead", officerNote = "Org admin" },
    { name = "Grimlock", rank = 1, rankName = "Officer", guid = "Player-1-00000011", level = 58, class = "WARRIOR",
      className = "Warrior", zone = "Blackrock Mountain", note = "Main tank", officerNote = "Bank access" },
    { name = "Shade", rank = 3, rankName = "Member", guid = "Player-1-00000012", level = 52, class = "WARLOCK",
      className = "Warlock", zone = "Tanaris", note = "Alt of Umbra" },
    { name = "Bramblepaw", rank = 4, rankName = "Initiate", guid = "Player-1-00000013", level = 24, class = "DRUID",
      className = "Druid", zone = "Duskwood", online = false, lastOnline = { 0, 0, 2, 5 }, note = "Leveling", officerNote = "Trial ends Fri" },
}
Server.guilds["Briar Fang"] = {
    { name = "Cara Cole", rank = 0, guid = "Player-1-00000002" },
    { name = "Eve Ember", rank = 2, guid = "Player-1-00000004" },
}
-- RENDER_AS=eve draws the pages as a member (not an officer) sees them.
local AS = os.getenv("RENDER_AS") or "alice"
local alice = Server:NewClient({ name = "Alice Ash", guid = "Player-1-00000001", guild = "Ashen Order", rank = 0,
                                 modules = MODULES, ui = AS == "alice" and F or nil })
local cara = Server:NewClient({ name = "Cara Cole", guid = "Player-1-00000002", guild = "Briar Fang", rank = 0, modules = MODULES })
local eve = Server:NewClient({ name = "Eve Ember", guid = "Player-1-00000004", guild = "Briar Fang", rank = 2, modules = MODULES,
                               ui = AS == "eve" and F or nil })
Server:Advance(10)
Server:Slash(alice, "key create RUIN")
Server:Slash(alice, "key addguild Briar Fang, 1, Briar")
alice.ns.Org:SendFullKey("Cara Cole")
Server:Advance(3)
cara.env.RUIN_ConfirmDialog.onAccept()
Server:Advance(90)
alice.ns.Org:SetLinks({ { label = "Discord", url = "https://discord.gg/ruin" }, { label = "Website", url = "https://ruin.gg" },
                         { label = "Twitch", url = "https://twitch.tv/ruin" } })
Server:Advance(3)

-- Sample activity so pages have something in them
local function try(label, fn)
    local ok, err = pcall(fn)
    if not ok then print("sample " .. label .. ": " .. tostring(err)) end
end
try("muster", function()
    local mu = alice.env.RUIN_API:GetModule("Muster")
    local ev = mu:Create("Molten Core", os.date("%Y-%m-%d %H:%M", os.time() + 3 * 3600),
        { kind = "Raid", desc = "Bring fire resist", size = "40", need = { 5, 10, 25 }, weekly = true, rally = true })
    mu:Create("Scarlet run", os.date("%Y-%m-%d %H:%M", os.time() + 5 * 3600), { kind = "Dungeon", size = "5", need = { 1, 1, 3 } })
    mu:Create("Tarren Mill push", os.date("%Y-%m-%d %H:%M", os.time() + 26 * 3600), { kind = "PvP" })
    Server:Advance(3)
    cara.env.RUIN_API:GetModule("Muster"):SignUp(ev.id, "T")
    eve.env.RUIN_API:GetModule("Muster"):SignUp(ev.id, "H")
    Server:Advance(3)
    cara.env.RUIN_API:GetModule("Muster"):Reserve(ev.id, "|cffa335ee|Hitem:17076::|h[Bonereaver's Edge]|h|r")
    Server:Advance(3)
    mu:AutoRoster(ev.id)
    mu:PostBounty("Grim Lords", "Guild", "50 gold")
    Server:Advance(3)
    eve.env.SlashCmdList.RUINMUSTERINTEL("enemy 8 Horde heading north")
    Server:Advance(12)
    cara.env.SlashCmdList.RUINMUSTERINTEL("rare Mirelow")
    Server:Advance(12)
    cara.env.SlashCmdList.RUINMUSTERINTEL("timer songflower")
    Server:Advance(3)
end)
try("pathfinder", function()
    alice.env.RUIN_API:GetModule("Pathfinder"):PublishRoute("westfall_10_15")
    Server:Advance(20)
    -- quest logs shared across RUIN, and a stand-in Questie for the Quests page
    local function log(c, list) c.questLog = list; for _, q in ipairs(list) do c.questTitles[q.id] = q.title end end
    log(alice, { { title = "Westfall Stew", id = 38, complete = false }, { title = "The Killing Fields", id = 9, complete = true },
                 { title = "Goretusk Liver Pie", id = 22, complete = false } })
    log(eve, { { title = "Westfall Stew", id = 38, complete = true }, { title = "The Killing Fields", id = 9, complete = false } })
    log(cara, { { title = "Westfall Stew", id = 38, complete = false } })
    local quests = {
        [38] = { name = "Westfall Stew", level = 13, req = 9, starts = { 235 }, ends = { 235 }, text = "Bring stew ingredients to Salma Saldean." ,
                 obj = { { Type = "item", Id = 1, Text = "Stringy Vulture Meat: 0/6" }, { Type = "item", Id = 2, Text = "Murloc Eye: 0/6" } } },
        [9] = { name = "The Killing Fields", level = 15, req = 8, starts = { 233 }, ends = { 233 }, obj = { { Type = "monster", Id = 480, Text = "Harvest Watcher slain: 20/20" } } },
        [22] = { name = "Goretusk Liver Pie", level = 12, req = 9, starts = { 235 }, ends = { 235 }, obj = { { Type = "item", Id = 3, Text = "Goretusk Liver: 0/8" } } },
    }
    local npcs = { [235] = { name = "Salma Saldean", spawns = { [40] = { { 56.4, 30.5 } } } },
                   [233] = { name = "Farmer Saldean", spawns = { [40] = { { 56.0, 31.2 } } } },
                   [480] = { name = "Rusty Harvest Golem", spawns = { [40] = { { 50.0, 30.0 } } } } }
    local DB = { QuestPointers = {} }
    function DB.GetQuest(id) local q = quests[id]; if not q then return nil end
        return { name = q.name, level = q.level, requiredLevel = q.req, Starts = { NPC = q.starts }, Finisher = { NPC = q.ends }, ObjectiveData = q.obj or {} } end
    function DB:GetNPC(id) return npcs[id] end
    function DB:GetObject() return nil end
    function DB:GetItem() return nil end
    local Zone = {}
    function Zone:GetUiMapIdByAreaId(a) return a == 40 and 1436 or nil end
    function Zone:GetAreaIdByUiMapId(m) return m == 1436 and 40 or nil end
    for _, c in ipairs({ alice, eve }) do
        c.env.QuestieLoader = { ImportModule = function(_, n) return n == "QuestieDB" and DB or Zone end }
        c.mns.RUIN_Pathfinder.QB.Forget()
    end
    for _, c in ipairs({ alice, eve, cara }) do c.env.RUIN_API:GetModule("Pathfinder"):ShareQuests(true) end
    Server:Advance(10)
    for _, c in ipairs({ alice, eve }) do c.env.RUIN_API:GetModule("Pathfinder"):StartRoute("westfall_10_15") end
    Server:Advance(5)
end)
try("finder", function()
    local cdb = cara.env.RUIN_FinderCharDB
    cdb.needT, cdb.needH, cdb.needD = 0, 1, 0
    cara.env.SlashCmdList.RUINFINDER("group dungeon")
    local edb = eve.env.RUIN_FinderCharDB
    edb.tank, edb.healer, edb.dps = false, true, false
    eve.env.SlashCmdList.RUINFINDER("on dungeon")
    Server:Advance(5)
end)
Server:Advance(5)

try("crafters", function()
    for _, c in ipairs({ eve, cara }) do Server.fire(c, "TRADE_SKILL_SHOW") end
    Server:Advance(8)
end)
try("chat", function()
    local g = Server.guilds["Ashen Order"]
    Server:GuildSay("Ashen Order", g[2], "Molten Core tonight, invites at 7:45")
    Server:GuildSay("Briar Fang", Server.guilds["Briar Fang"][1], "Anyone want to run Scholomance after?")
    Server:Advance(3)
    Server:GuildSay("Ashen Order", g[1], "Bring fire resistance gear please")
    Server:Advance(3)
end)
try("org rosters and key phrase", function()
    alice.ns.Org:ChooseNewKey("dragons eat at dawn")
    Server:Advance(60)
    local bf = Server.guilds["Briar Fang"]
    local names = { [0] = "Chieftain", [1] = "Warden", [2] = "Hunter", [3] = "Cub" }
    for _, m in ipairs(bf) do m.zone = m.zone or "Darnassus"; m.rankName = m.rankName or names[m.rank] end
    bf[#bf + 1] = { name = "Moss Vale", rank = 3, rankName = "Member", guid = "Player-1-00000031", level = 41, class = "DRUID",
                    zone = "Feralas", note = "Herbalist", online = false, lastOnline = { 0, 0, 1, 4 } }
    for _, c in ipairs({ cara, eve }) do c.ns:ScanRoster() end
    for _, c in ipairs({ cara, eve }) do c.ns.OrgRoster:Send(true) end
    Server:Advance(40)
    cara.ns.Guild:SetEventRank(2)
    alice.ns.Guild:SetEventRank(2)
    Server:Advance(5)
end)
-- the guild master's rights in the game's guild window
for _, fn in ipairs({ "CanGuildPromote", "CanGuildDemote", "CanGuildRemove", "CanGuildInvite", "CanEditPublicNote",
                      "CanEditOfficerNote", "CanViewOfficerNote", "CanEditMOTD" }) do
    alice.env[fn] = function() return true end
end
alice.env.GuildControlGetNumRanks = function() return 5 end
alice.env.GuildControlGetRankName = function(i) return ({ "Guild Master", "Officer", "Veteran", "Member", "Initiate" })[i] end

-- Overlord Forever "installed" (its /ov command exists), so the Guild page shows that state.
for _, c in ipairs({ alice, eve }) do
    c.env.SLASH_OVERLORD1 = "/ov"
    c.env.SlashCmdList.OVERLORD = function() end
end
local viewer = AS == "eve" and eve or alice
alice = viewer
-- Record every sub-tab row the pages build, so each sub-page can be opened.
local W = alice.ns.Widgets
local subtabs = {}
local orig = W.SubTabs
W.SubTabs = function(parent, names, onSelect)
    local obj = orig(parent, names, onSelect)
    subtabs[#subtabs + 1] = { obj = obj, parent = parent }
    return obj
end

os.execute("mkdir -p '" .. OUT .. "'")
local index = {}
local function write(name)
    Server:Advance(1)
    local f = assert(io.open(OUT .. "/" .. name .. ".json", "w"))
    f:write(F.json({ w = F.SCREEN_W, h = F.SCREEN_H, regions = F.Dump() }))
    f:close()
    index[#index + 1] = name
end

local function slug(s) return (s:lower():gsub("[^%w]+", "-"):gsub("%-+$", "")) end

local API = alice.env.RUIN_API
for _, label in ipairs(alice.ns.UI:TabLabels()) do
    local before = #subtabs
    API:OpenTab(label)
    Server:Advance(1)
    local mine = {}
    for i = before + 1, #subtabs do mine[#mine + 1] = subtabs[i] end
    if #mine == 0 then
        write(slug(label))
    else
        for _, st in ipairs(mine) do
            for i, name in ipairs(st.obj.names) do
                st.obj:Select(i)
                write(slug(label) .. "--" .. slug(name))
            end
            st.obj:Select(1)
        end
    end
end

-- A few views that need a click: forms and popovers.
local function click(text)
    for _, fr in ipairs(alice.frames) do
        if fr.GetText and fr:IsVisible() and (fr._type == "Button") and fr:GetText() == text and fr._scripts.OnClick then
            fr._scripts.OnClick(fr, "LeftButton")
            return true
        end
    end
    print("render: no visible button " .. text)
end
local function sub(label, name)
    for _, st in ipairs(subtabs) do
        for i, n in ipairs(st.obj.names) do
            if n == name and st.parent:IsVisible() then st.obj:Select(i); return end
        end
    end
end
if AS == "alice" then API:OpenTab("Muster"); sub("Muster", "Events"); click("New event"); write("muster--events-new"); click("Close") end
sub("Muster", "Sightings"); click("Alerts"); write("muster--sightings-alerts"); click("Alerts")
-- the day list open on the New event form
if AS == "alice" then API:OpenTab("Muster"); sub("Muster", "Events"); click("New event"); alice.mns.RUIN_Muster.MusterUI.when.day:Open(); write("muster--events-new-day"); click("Close") end
API:OpenTab("Codex"); sub("Codex", "Macros"); click("Commands"); write("codex--macros-commands"); click("Class macros")
alice.env.SlashCmdList.RUINCODEX("deadmines"); write("codex--journal-deadmines")

API:OpenTab("Codex"); sub("Codex", "Journal"); click("Raids"); write("codex--journal-raids"); click("Dungeons")
-- Options: a tab picked in Tab order, and Muster moved first.
API:OpenTab("Options"); sub("Settings", "Options"); click("Muster"); click("Move left"); click("Move left"); write("options--tab-order")
alice.ns.UI:ResetTabOrder()
-- a member picked on the roster, and the pop-out chat
API:OpenTab("Guild"); sub("Guild", "Roster")
for _, fr in ipairs(alice.frames) do if fr.e and fr.e.name == "Shade" and fr._scripts.OnMouseUp then fr._scripts.OnMouseUp(fr) end end
write("guild--roster-selected")
alice.ns.GuildUI.ToggleChatWindow(true); alice.ns.GuildUI.window:ClearAllPoints(); alice.ns.GuildUI.window:SetPoint("CENTER"); alice.ns.GuildUI.RefreshChat(); write("guild--chat-popout"); alice.ns.GuildUI.ToggleChatWindow(false)

-- Exchange's "Add your recipes" window at login
if AS == "alice" then
    alice.env.GetProfessions = function() return 1, nil, nil, nil, 2 end
    alice.env.GetProfessionInfo = function(i) if i == 1 then return "Tailoring", 0, 75, 150 end return "Cooking", 0, 40, 75 end
    API:OpenTab("Exchange"); sub("Exchange", "Search")
    local X = API:GetModule("Exchange")
    X.RefreshScanPrompt(true)
    write("exchange--add-recipes")
    alice.env.RUIN_ExchangeScan:Hide()
end

local f = assert(io.open(OUT .. "/index.txt", "w"))
f:write(table.concat(index, "\n"), "\n")
f:close()
for _, e in ipairs(Server.errors) do print("error: " .. e) end
for _, e in ipairs(F.errors) do print("error: " .. e) end
print(("wrote %d pages to %s"):format(#index, OUT))
