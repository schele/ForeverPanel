local stub = require("wow_stub")

local M = {}

M.FILES = {
    "ForeverPanel.lua",
    "Bar.lua",
    "Modules/Money.lua",
    "Modules/Clock.lua",
    "Modules/XP.lua",
    "Modules/Bags.lua",
    "Modules/UITweaks.lua",
    "Modules/ChatKeys.lua",
    "Modules/Settings.lua",
}

--- Load the addon's files into a stubbed environment, the way WoW would:
-- in .toc order, each chunk receiving (addonName, privateTable).
function M.loadAddon(files)
    local env = stub.newEnv()
    local ns = {}

    for _, path in ipairs(files or M.FILES) do
        local chunk = assert(loadfile(path, "t", env))
        chunk("ForeverPanel", ns)
    end

    return ns, env
end

--- Fire an event on every frame registered for it, then flush queued timers.
function M.fire(env, event, ...)
    local frames = {}
    for index, frame in ipairs(env.__frames) do
        frames[index] = frame
    end

    for _, frame in ipairs(frames) do
        if frame.registeredEvents[event] then
            frame:Fire(event, ...)
        end
    end

    env.__runTimers()
end

--- Run the real login sequence.
function M.login(ns, env)
    M.fire(env, "ADDON_LOADED", "ForeverPanel")
    M.fire(env, "PLAYER_LOGIN")
end

--- Draw the first frame, then run the timers that fall due on the next one.
-- Text set during login only becomes measurable once it has been rendered.
function M.firstFrame(env)
    env.__render()
    env.__runTimers()
    env.__runTimers()
end

--- Strip inline texture escapes so text is easy to compare.
function M.plain(text)
    return (tostring(text):gsub("|T.-|t", ""))
end

function M.command(env, text)
    env.SlashCmdList.FOREVERPANEL(text)
    env.__runTimers()
end

return M
