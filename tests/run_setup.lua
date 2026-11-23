-- Core's first-run setup for guild leaders: start an org or join one. Runs inside run_features.lua.
local alice, check, errorsSoFar = T.alice, T.check, T.errorsSoFar

print("Core: setup guide for guild leaders")
do
    check(alice.ns.Setup and not alice.ns.Setup.Due(), "a leader who's already in an org isn't asked")
    -- a guild leader with RUIN and no key: the guide is due, and opens on its first page
    Server.guilds["Quiet Grove"] = { { name = "Ivy Ives", rank = 0, guid = "Player-1-00000031" } }
    local ivy = Server:NewClient({ name = "Ivy Ives", guid = "Player-1-00000031", guild = "Quiet Grove", rank = 0, modules = {} })
    Server:Advance(10)
    ivy.env.IsGuildLeader = function() return true end
    local S = ivy.ns.Setup
    check(S.Due(), "a guild leader without a key is offered the guide")
    S.Open()
    check(S.Page() == "choose", "it asks: start an org, or join one")
    -- joining with the org's phrase (the admin added the guild and set a phrase)
    local Org = alice.ns.Org
    Org:AddGuild("Quiet Grove", 1, "Grove")
    Org:ChooseNewKey("quiet groves sing at night")
    Server:Advance(120)
    S.Show("join")
    local ok = S.Actions.join("Quiet groves sing at night")
    Server:Advance(60)
    check(ok and ivy.ns.Org:Get() and ivy.ns.Org:Get().org == alice.ns.Org:Get().org, "Join with the phrase brings the key")
    S.Show("join")
    check(S.Page() == "done", "and the guide moves on to You're set")
    check(not S.Due(), "with a key, the guide isn't offered again")
    -- starting an org: create, add a guild, a bad name is explained
    Server.guilds["New Dawn"] = { { name = "Jon Jay", rank = 0, guid = "Player-1-00000032" } }
    local jon = Server:NewClient({ name = "Jon Jay", guid = "Player-1-00000032", guild = "New Dawn", rank = 0, modules = {} })
    Server:Advance(10)
    jon.env.IsGuildLeader = function() return true end
    local J = jon.ns.Setup
    J.Open()
    J.Show("create")
    check(J.Actions.create("Dawn League") and jon.ns.Org:IsAdmin() and J.Page() == "guilds", "Create the org makes you its admin and moves to Add guilds")
    check(J.Actions.addGuild("Second Dawn", 2, "Dawn2") and jon.ns.Org:GuildInfo("Second Dawn"), "Add puts a guild in with its officer rank")
    local okBad, err = J.Actions.addGuild("", 1, "")
    check(not okBad and J.Status():find(tostring(err), 1, true), "a refused step says why in the guide")
    J.Show("send")
    check(not J.Actions.send(""), "Send the key needs a name")
    -- /ruin setup opens it any time; Don't show again sticks
    jon.env.SlashCmdList.RUIN("setup")
    check(jon.env.RUIN_Setup and jon.env.RUIN_Setup:IsShown(), "/ruin setup opens it")
    jon.ns.db.setupDismissed = true
    jon.ns.Org:Forget()
    check(not J.Due(), "after Don't show again it isn't offered")
    errorsSoFar("setup guide")
end
