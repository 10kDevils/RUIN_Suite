-- RUIN Codex 0.3.5 tests: class macros (starter library, safety checks, Add).
-- Runs after run_features_brief.lua and shares T.
local alice, check, chatHas, errorsSoFar = T.alice, T.check, T.chatHas, T.errorsSoFar

-- A small stand-in for the game's macro list: account macros 1..120, character macros 121..,
-- both kept sorted by name like the real thing.
local function macroGame(c, opts)
    opts = opts or {}
    local env = c.env
    local g = { acc = {}, chr = {}, cursor = nil, combat = false }
    env.MAX_ACCOUNT_MACROS, env.MAX_CHARACTER_MACROS = opts.maxAcc or 120, opts.maxChar or 30
    local function byName(a, b) return a.name < b.name end
    env.GetNumMacros = function() return #g.acc, #g.chr end
    env.GetMacroInfo = function(i)
        local t
        if i <= env.MAX_ACCOUNT_MACROS then t = g.acc[i] else t = g.chr[i - env.MAX_ACCOUNT_MACROS] end
        if t then return t.name, t.icon, t.body end
    end
    env.CreateMacro = function(name, icon, body, perChar)
        local list = perChar and g.chr or g.acc
        local t = { name = name, icon = icon, body = body }
        list[#list + 1] = t
        table.sort(list, byName)
        for i, v in ipairs(list) do
            if v == t then return perChar and (env.MAX_ACCOUNT_MACROS + i) or i end
        end
    end
    env.PickupMacro = function(i) g.cursor = i end
    env.InCombatLockdown = function() return g.combat end
    return g
end

local mod = alice.mns.RUIN_Codex
local Mac = mod.Macros
local seed = mod.MacroSeed

print("Class macros: the starter library")
do
    check(Mac ~= nil and #seed == 113, "113 starter macros (" .. #seed .. ")")
    local ids, perClass, bad = {}, {}, {}
    for _, rec in ipairs(seed) do
        if ids[rec.id] then bad[#bad + 1] = "duplicate id " .. rec.id end
        ids[rec.id] = true
        perClass[rec.c] = (perClass[rec.c] or 0) + 1
        local res = Mac.Check(rec)
        if not res.ok then bad[#bad + 1] = rec.id .. ": " .. res.errors[1] end
        local text, missing = Mac.Resolve(rec.body)
        if #text > 255 then bad[#bad + 1] = rec.id .. ": " .. #text .. " characters once items are filled in" end
        if #rec.n > 16 then bad[#bad + 1] = rec.id .. ": name too long" end
        if not rec.note or rec.note == "" then bad[#bad + 1] = rec.id .. ": no note" end
    end
    for _, b in ipairs(bad) do print("       " .. b) end
    check(#bad == 0, "every macro: name <= 16, text <= 255 (also with items filled in), no blocked commands, a note")
    local ok = perClass.ALL == 5
    for _, c in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
        if perClass[c] ~= 12 then ok = false end
    end
    check(ok, "12 per class and 5 shared")
    local specOk = true
    for _, rec in ipairs(seed) do
        if rec.s then
            local found = false
            for _, s in ipairs(alice.mns.RUIN_Codex.SpecOrder[rec.c] or {}) do if s == rec.s then found = true end end
            if not found then specOk = false; print("       unknown spec " .. rec.id .. " " .. rec.s) end
        end
    end
    check(specOk, "every spec named in the library is a real spec of its class")
    errorsSoFar("library")
end

print("Class macros: safety checks")
do
    local function chk(body, name) return Mac.Check({ n = name or "Test", body = body, tag = "Combat" }) end
    check(not chk("/run print('hi')").ok and not chk("/script x=1").ok and not chk("#showtooltip\n/cast Fireball\n/RUN foo()").ok,
        "/run and /script are refused, in any case, on any line")
    check(not chk("/console cameraDistance 5").ok and not chk("/logout").ok and not chk("/quit").ok and not chk("/reload").ok,
        "/console, /logout, /quit, /reload are refused")
    check(chk("/s hello").ok and chk("/s hello").chat and chk("/1 buying").chat and chk("/w Bob hi").chat and chk("/g hey").chat,
        "chat commands are allowed but flagged")
    check(not chk("/cast Fireball").chat, "a cast is not flagged")
    check(not chk("/cast |cffff0000Fire|r").ok and not chk("/cast |Hitem:1|h[x]|h").ok, "formatting codes are refused")
    check(not chk(string.rep("a", 256)).ok and chk(string.rep("a", 255)).ok, "255 characters pass, 256 do not")
    check(not chk("/cast Fireball", "A name of seventeen").ok and chk("/cast Fireball", "Sixteen chars...").ok, "names over 16 characters are refused")
    check(not chk("").ok and not chk("/cast x\0/run y").ok, "empty text and control characters are refused")
    check(not Mac.Check({ n = "Test", body = "/cast x", tag = "Nonsense" }).ok, "unknown tags are refused")
    errorsSoFar("safety")
end

print("Class macros: placeholders")
do
    alice.bag = { { itemName = "Greater Healing Potion" }, { hyperlink = "|cff1eff00|Hitem:1::|h[Major Mana Potion]|h|r" },
                  { itemName = "Heavy Linen Bandage" }, { itemName = "Linen Bandage" }, { itemName = "Conjured Spring Water" } }
    local text, missing = Mac.Resolve("/use {potion:heal}\n/use {potion:mana}\n/use {bandage}\n/use {drink}")
    check(text == "/use Greater Healing Potion\n/use Major Mana Potion\n/use Heavy Linen Bandage\n/use Conjured Spring Water" and #missing == 0,
        "the best item in the bags is chosen (" .. text:gsub("\n", " | ") .. ")")
    local text2, missing2 = Mac.Resolve("/use {food}\n/use {healthstone}\n/cast {unknown}")
    check(text2:find("Tough Hunk of Bread") and text2:find("Healthstone") and text2:find("{unknown}", 1, true) and #missing2 == 2,
        "with nothing in the bags a common name is used and reported; unknown placeholders are left alone")
    alice.bag = {}
    errorsSoFar("placeholders")
end

print("Class macros: filters")
do
    local war = Mac.For("WARRIOR")
    local classOnly, shared = 0, 0
    for _, r in ipairs(war) do if r.c == "WARRIOR" then classOnly = classOnly + 1 else shared = shared + 1 end end
    check(classOnly == 12 and shared == 5 and war[#war].c == "ALL", "a class shows its 12 and the 5 shared ones, shared last")
    local prot = Mac.For("WARRIOR", "Protection")
    local hasSunder, hasOverpower = false, false
    for _, r in ipairs(prot) do
        if r.n == "Sunder" then hasSunder = true end
        if r.n == "Overpower" then hasOverpower = true end
    end
    check(hasSunder and not hasOverpower, "the spec filter keeps spec-less macros and the chosen spec's, drops other specs'")
    local util = Mac.For("MAGE", "All specs", "Utility")
    local allUtil = #util > 0
    for _, r in ipairs(util) do if r.tag ~= "Utility" then allUtil = false end end
    check(allUtil, "the tag filter only shows that tag")
    check(#Mac.For("SHARED") == 5, "Shared shows just the shared macros")
    local found = Mac.For("ROGUE", "All specs", "All tags", "kidney")
    check(#found == 1 and found[1].n == "Kidney Mo", "search finds by name")
    errorsSoFar("filters")
end

print("Class macros: adding")
do
    local g = macroGame(alice)
    local id = "warrior-pummel-bash"
    local status, msg = Mac.Add(id, false)
    check(status == "created" and #g.acc == 1 and g.acc[1].name == "Pummel/Bash", "Add creates the macro (" .. tostring(status) .. ")")
    check(g.acc[1].body:find("Shield Bash", 1, true) and g.cursor == 1, "with the library's text, and puts it on the cursor")
    local d = alice.env.RUIN_CodexDB
    check(d.installed[id] and d.installed[id].name == "Pummel/Bash" and d.installed[id].hash, "it is remembered as added by RUIN")
    check(Mac.IsInstalled(id) and Mac.Status(Mac.Get(id)) == "installed", "and shows as Installed")
    g.cursor = nil
    status = Mac.Add(id, false)
    check(status == "pickup" and #g.acc == 1 and g.cursor == 1, "adding it again just picks up your copy")

    -- a second one: indexes move because the game keeps macros sorted
    Mac.Add("warrior-charge-intercept", false)
    check(#g.acc == 2 and g.acc[1].name == "Charge/Intercept", "the game sorts macros by name")
    g.cursor = nil
    Mac.Add(id, false)
    check(g.cursor == 2, "pickup follows the macro to its new number")

    -- character macros use the upper numbers
    status = Mac.Add("warrior-execute", true)
    check(status == "created" and #g.chr == 1 and g.cursor == 121, "per-character macros go in the character list (number 121 and up)")

    -- the player deletes it: it is no longer installed, and can be added again
    table.remove(g.acc, 2)
    check(not Mac.IsInstalled(id) and alice.env.RUIN_CodexDB.installed[id] == nil, "a macro the player deleted is forgotten")
    check(Mac.Add(id, false) == "created", "and can be added again")
    errorsSoFar("adding")
end

print("Class macros: names, text and slots")
do
    alice.env.RUIN_CodexDB.installed = {}
    local g = macroGame(alice)
    -- same name, different text: ask, then add as a copy; never overwrite
    g.acc[1] = { name = "Execute", icon = 1, body = "/cast Something Else" }
    local status, _, what = Mac.Add("warrior-execute", false)
    check(status == "confirm" and what == "copy" and g.acc[1].body == "/cast Something Else", "a different macro with the same name is not touched; Add asks")
    status = Mac.Add("warrior-execute", false, { copy = true })
    check(status == "created" and #g.acc == 2, "after the yes it is added as a copy")
    local copyName
    for _, m in ipairs(g.acc) do if m.name ~= "Execute" then copyName = m.name end end
    check(copyName == "Execute 2", "named 'Execute 2' (" .. tostring(copyName) .. ")")

    -- same name and same text: adopted, nothing duplicated
    local g2 = macroGame(alice)
    local rec = Mac.Get("warrior-sunder")
    g2.acc[1] = { name = rec.n, icon = 1, body = rec.body }
    status = Mac.Add("warrior-sunder", false)
    check(status == "pickup" and #g2.acc == 1 and Mac.IsInstalled("warrior-sunder"), "an identical macro you already have is adopted, not duplicated")

    -- long names that need a suffix stay within 16 characters
    local g3 = macroGame(alice)
    g3.acc[1] = { name = "Charge/Intercept", icon = 1, body = "different" }
    Mac.Add("warrior-charge-intercept", false, { copy = true })
    local longest = 0
    for _, m in ipairs(g3.acc) do longest = math.max(longest, #m.name) end
    check(#g3.acc == 2 and longest <= 16, "a suffixed copy of a 16-character name still fits (" .. longest .. ")")

    -- missing spells and chat: ask first
    local g4 = macroGame(alice)
    alice.env.GetSpellInfo = function(name) if name ~= "Charge" then return name end end
    local st, msg, what4 = Mac.Add("warrior-charge-intercept", false)
    check(st == "confirm" and what4 == "spells" and msg:find("Charge", 1, true) and #g4.acc == 0, "a spell you have not learned: Add asks first")
    check(Mac.Status(Mac.Get("warrior-charge-intercept")) == "needs", "and the list says it needs a spell")
    check(Mac.Add("warrior-charge-intercept", false, { spells = true }) == "created", "after the yes it is added")
    alice.env.GetSpellInfo = nil

    local g5 = macroGame(alice)
    table.insert(seed, { id = "test-chat", c = "WARRIOR", tag = "Combat", n = "Shout", body = "/yell For RUIN!", note = "test", rev = 1 })
    local st5, _, what5 = Mac.Add("test-chat", false)
    check(st5 == "confirm" and what5 == "chat" and #g5.acc == 0, "a macro that sends chat asks first")
    check(Mac.Add("test-chat", false, { chat = true }) == "created", "and is added after the yes")

    -- blocked commands are never added, even if one got into the library
    table.insert(seed, { id = "test-run", c = "WARRIOR", tag = "Combat", n = "Bad", body = "/run print(1)", note = "test", rev = 1 })
    local st6, msg6 = Mac.Add("test-run", false, { chat = true, spells = true, items = true, copy = true })
    check(st6 == "refused" and msg6:find("/run", 1, true) and Mac.Get("test-run") and not Mac.IsInstalled("test-run"), "a /run macro is refused, whatever was confirmed")
    -- text that grows past 255 once items are named is refused
    table.insert(seed, { id = "test-long", c = "WARRIOR", tag = "Combat", n = "Long", body = string.rep("x", 236) .. "\n/use {potion:heal}", note = "test", rev = 1 })
    local st7 = Mac.Add("test-long", false, { items = true })
    check(st7 == "refused", "text that is too long once items are filled in is refused")
    for i = #seed, 1, -1 do if seed[i].id:find("^test%-") then table.remove(seed, i) end end

    -- full lists
    local g8 = macroGame(alice, { maxAcc = 2, maxChar = 1 })
    Mac.Add("warrior-execute", false)
    Mac.Add("warrior-sunder", false)
    local st8, msg8 = Mac.Add("warrior-taunt", false)
    check(st8 == "refused" and msg8:find("full", 1, true) and msg8:find("2 of 2", 1, true) and #g8.acc == 2, "a full account list stops the add and says so")
    Mac.Add("warrior-taunt", true)
    local st9 = Mac.Add("warrior-overpower", true)
    check(st9 == "refused" and #g8.chr == 1, "and so does a full character list")
    local a, ma, ch, mc = Mac.Slots()
    check(a == 2 and ma == 2 and ch == 1 and mc == 1, "slot counts for the footer")
    errorsSoFar("names, text and slots")
end

print("Class macros: combat and old clients")
do
    local g = macroGame(alice)
    g.combat = true
    local status = Mac.Add("warrior-execute", false)
    check(status == "queued" and #g.acc == 0 and Mac.Pending(), "in combat nothing is added; it is queued")
    g.combat = false
    Server.fire(alice, "PLAYER_REGEN_ENABLED")
    check(#g.acc == 1 and g.acc[1].name == "Execute" and not Mac.Pending(), "when combat ends the queued macro is added")
    check(chatHas(alice, "Added"), "and the player is told")

    local saveCreate = alice.env.CreateMacro
    alice.env.CreateMacro = nil
    local st = Mac.Add("warrior-sunder", false)
    check(st == "copied", "a client without macro creation gets the text in a copy box instead")
    alice.env.CreateMacro = saveCreate
    errorsSoFar("combat and old clients")
end

print("Class macros: the page")
do
    macroGame(alice)
    alice.env.SlashCmdList.RUINCODEX("macros")
    check(alice.mns.RUIN_Codex ~= nil and alice.env.RUIN_API:OpenTab("Codex"), "/codex macros opens Codex")
    T.openAllSubTabs(alice, "Codex")
    Mac.Show("mage-ice-block")
    alice.env.SlashCmdList.RUINCODEX("macros")
    Mac.Refresh()
    T.openAllSubTabs(alice, "Codex")
    check(Mac.Show("mage-ice-block") and not Mac.Show("nonsense"), "the page can jump to a macro")
    errorsSoFar("macro page")
    -- the other Codex pages still work after the new tab went in
    alice.env.SlashCmdList.RUINCODEX("commands")
    alice.env.SlashCmdList.RUINCODEX("journal")
    alice.env.SlashCmdList.RUINCODEX("Deadmines")
    errorsSoFar("codex pages")
end

print("Macro command reference (Codex 0.3.10)")
do
    local g = macroGame(alice)
    local cmds = mod.MacroCommands
    local bad = {}
    local ids = {}
    for _, rec in ipairs(cmds) do
        local r = Mac.Check(rec)
        if not r.ok or not rec.note or not rec.cmd or ids[rec.id] then bad[#bad + 1] = rec.n .. ": " .. tostring(r.errors[1]) end
        ids[rec.id] = true
    end
    check(#cmds >= 40 and #bad == 0, ("%d commands, each a valid macro with a note (%s)"):format(#cmds, table.concat(bad, "; ")))
    local groups = {}
    for _, rec in ipairs(cmds) do groups[rec.group] = (groups[rec.group] or 0) + 1 end
    local everyGroup = true
    for i, gname in ipairs(mod.MacroCommandGroups) do if i > 1 and not groups[gname] then everyGroup = false end end
    check(everyGroup, "every group has commands")
    check(#Mac.Commands("Pet") == groups.Pet and #Mac.Commands("All", "castsequence") >= 1, "filter by group and search")
    check(#Mac.For("MAGE", "All specs", "All tags", "") == #Mac.For("MAGE", "All specs", "All tags", ""), "class macros list unchanged")
    local cs = Mac.Get("cmd-sequence")
    check(cs and cs.cmd:find("castsequence"), "commands are found by id")
    local status = Mac.Add("cmd-smart-tab", false)
    check(status == "created" and g.acc[1].body == "/targetenemy [noharm][dead]", "a command example can be added as a macro")
    Mac.SetMode("commands")
    alice.env.RUIN_API:OpenTab("Codex")
    T.openAllSubTabs(alice, "Codex")
    Mac.SetMode("macros")
    errorsSoFar("macro commands")
end
