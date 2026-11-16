-- The Blizzard window style: the app built from the game's templates opens
-- every page and sub-page without an error. Runs last; shares T.
local check, errorsSoFar = T.check, T.errorsSoFar

print("Blizzard window style: native templates")
do
    table.insert(Server.guilds["Ashen Order"], { name = "Bram Birch", rank = 3, guid = "Player-1-00000077" })
    local MODULES = { "RUIN_Finder", "RUIN_Pathfinder", "RUIN_Codex", "RUIN_Exchange", "RUIN_Muster" }
    local bram = Server:NewClient({ name = "Bram Birch", guid = "Player-1-00000077", guild = "Ashen Order", rank = 3, modules = MODULES })
    local env = bram.env
    local templates = {}
    local bramMain
    local cf = env.CreateFrame
    env.CreateFrame = function(kind, name, parent, template)
        local f = cf(kind, name, parent, template)
        if template then templates[template] = (templates[template] or 0) + 1 end
        if template == "PortraitFrameTemplate" then
            f.NineSlice, f.CloseButton = {}, cf("Button")
            f.SetTitle = function(self, t) self.title = t end
            f.SetPortraitToAsset = function(self, a) self.portraitArt = a end
            bramMain = f
        end
        return f
    end
    local selected = {}
    env.PanelTemplates_SelectTab = function(tab) selected[tab] = true end
    env.PanelTemplates_DeselectTab = function(tab) selected[tab] = nil end
    env.PanelTemplates_TabResize = function(tab, pad) tab:SetWidth(80 + (pad or 0)) end
    bram.ns.Widgets.ApplyAppStyle("blizzard")
    Server:Advance(10)
    for _, page in ipairs({ "Guild", "Finder", "Muster", "Pathfinder", "Codex", "Exchange", "Settings" }) do
        openAllSubTabs(bram, page)
    end
    check((templates.PortraitFrameTemplate or 0) == 1, "the window is the game's portrait window")
    check(bramMain and bramMain.title == "RUIN Settings" and type(bramMain.portraitArt) == "string",
        "its title and portrait follow the open module (" .. tostring(bramMain and bramMain.title) .. ")")
    check((templates.UIPanelButtonTemplate or 0) > 10 and (templates.UICheckButtonTemplate or 0) > 5
        and (templates.InputBoxTemplate or 0) > 2, "buttons, check boxes and input boxes are the game's")
    check((templates.PanelTopTabButtonTemplate or 0) > 10, "tabs are the game's top tabs")
    check((templates.InsetFrameTemplate or 0) > 3, "panels are the game's insets")
    errorsSoFar("blizzard window style")
end
