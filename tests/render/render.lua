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
    { name = "Alice Ash", rank = 0, guid = "Player-1-00000001", level = 60, class = "WARLOCK" },
    { name = "Grimlock", rank = 3, guid = "Player-1-00000011", level = 58, class = "WARRIOR" },
    { name = "Shade", rank = 3, guid = "Player-1-00000012", level = 52, class = "WARLOCK" },
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
if AS == "alice" then API:OpenTab("Codex"); sub("Codex", "Best-in-slot"); click("Edit list"); write("codex--best-in-slot-edit"); click("Done") end

local f = assert(io.open(OUT .. "/index.txt", "w"))
f:write(table.concat(index, "\n"), "\n")
f:close()
for _, e in ipairs(Server.errors) do print("error: " .. e) end
for _, e in ipairs(F.errors) do print("error: " .. e) end
print(("wrote %d pages to %s"):format(#index, OUT))
