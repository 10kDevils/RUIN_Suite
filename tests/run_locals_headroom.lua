-- Lua (5.1 in game, too) allows 200 active locals in a file's main chunk. A file
-- near that limit stops compiling after a few more top-level locals, and then the
-- whole addon fails to load. Compile every addon file with extra top-level locals
-- appended, so the headroom can't silently shrink again. Runs inside run_features.lua.
local check = T.check
local EXTRA = 15

print("Every addon file has room for " .. EXTRA .. " more top-level locals")
do
    local core = os.getenv("RUIN_CORE_DIR") or (T.here .. "/../RUIN_Core")
    local root = core .. "/.."
    local extra = {}
    for i = 1, EXTRA do extra[i] = "local __headroom" .. i .. " = " .. i end
    extra = "\n" .. table.concat(extra, "\n") .. "\n"
    local files = 0
    for _, folder in ipairs({ "RUIN_Core", "RUIN_Finder", "RUIN_Pathfinder", "RUIN_Codex", "RUIN_Exchange", "RUIN_Muster" }) do
        local toc = io.open(root .. "/" .. folder .. "/" .. folder .. ".toc")
        if toc then
            for line in toc:lines() do
                local file = line:match("^%s*(.-)%s*$"):gsub("\\", "/")
                -- the bundled quest data is plain tables (and 3 MB): skip it
                if file:match("%.lua$") and not file:find("^QuestData/") then
                    local fh = io.open(root .. "/" .. folder .. "/" .. file)
                    if fh then
                        local src = fh:read("*a")
                        fh:close()
                        files = files + 1
                        local f, err = loadstring(src .. extra, "@" .. folder .. "/" .. file)
                        check(f ~= nil, folder .. "/" .. file .. " still compiles with " .. EXTRA .. " more locals" .. (f and "" or (" (" .. tostring(err) .. ")")))
                    end
                end
            end
            toc:close()
        end
    end
    check(files >= 6, "found the addon files (" .. files .. ")")
end
