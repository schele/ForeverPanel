local addonName, ns = ...

ns.PREFIX = "|cff66ccffUrlCopy|r"

-- Defaults are contributed by each file at load time, so every piece of config
-- lives next to the code that reads it and this file never learns the others.
local defaults = {
    version = 1,
}

--- Merge a defaults table into a saved table without clobbering stored values.
-- Recursive, so config added in a later version gets filled in on upgrade
-- instead of the whole branch being left empty.
local function applyDefaults(target, source)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            applyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end

ns.applyDefaults = applyDefaults

--- Register additional defaults. Called at file load, before ADDON_LOADED.
function ns.AddDefaults(extra)
    applyDefaults(defaults, extra)
end

function ns.Print(message)
    print(string.format("%s %s", ns.PREFIX, message))
end

-- Settings registry. A file declares the config it owns, the same way it
-- contributes defaults and commands, and Settings.lua renders what it finds.
local settings = {}
ns.settings = settings

local SETTING_TYPES = { checkbox = true, slider = true }

--- Declare a configurable value.
-- store/key address it inside the database (ns.db[store][key]); onChange runs
-- after a change so the owner can react.
function ns.RegisterSetting(definition)
    assert(type(definition) == "table", "RegisterSetting expects a table")

    local store, key = definition.store, definition.key
    assert(type(store) == "string" and store ~= "", "setting requires a store")
    assert(type(key) == "string" and key ~= "", "setting requires a key")
    assert(type(definition.name) == "string", "setting requires a name")
    assert(
        SETTING_TYPES[definition.type],
        "unknown setting type: " .. tostring(definition.type)
    )

    -- A setting with no default reads nil and writes somewhere nothing else
    -- looks, which shows up as a control that silently does nothing.
    assert(
        defaults[store] ~= nil and defaults[store][key] ~= nil,
        string.format("no default registered for %s.%s", store, key)
    )

    table.insert(settings, definition)
    return definition
end

function ns.SettingValue(setting)
    local store = ns.db and ns.db[setting.store]
    return store and store[setting.key]
end

function ns.SetSettingValue(setting, value)
    local store = ns.db and ns.db[setting.store]
    if not store or store[setting.key] == value then
        return
    end

    store[setting.key] = value
    if setting.onChange then
        setting.onChange(value)
    end
end

local function ensureDatabase()
    if type(UrlCopyDB) ~= "table" then
        UrlCopyDB = {}
    end

    applyDefaults(UrlCopyDB, defaults)
    ns.db = UrlCopyDB
end

ns.ensureDatabase = ensureDatabase

-- Slash commands. Each file registers its own, so a feature owns its commands
-- and its help text.
local commands = {}
ns.commands = commands

local helpLines = {}
ns.helpLines = helpLines

function ns.RegisterCommand(name, help, handler)
    commands[name] = { help = help, handler = handler }
end

--- A line of help for an input that is not a named command.
function ns.RegisterHelpLine(line)
    table.insert(helpLines, line)
end

local function showHelp()
    ns.Print("Commands:")

    for _, line in ipairs(helpLines) do
        ns.Print(line)
    end

    local names = {}
    for name in pairs(commands) do
        table.insert(names, name)
    end
    table.sort(names)

    for _, name in ipairs(names) do
        ns.Print(string.format("/url %s - %s", name, commands[name].help))
    end
end

ns.ShowHelp = showHelp

-- "/url 3" is the one input that is not a named command. Chat.lua points it at
-- the copy box; until it has, and if that file ever fails to load, a number
-- falls through to the command list rather than to silence.
ns.NumberCommand = nil

local function runCommand(msg)
    local input = msg and msg:match("^%s*(.-)%s*$") or ""

    -- A bare "/url" lists the commands, the same as a bare "/fp" does. The two
    -- addons print their login lines one above the other, so a bare command
    -- that meant something different in each was a trap.
    if input == "" or input == "help" then
        showHelp()
        return
    end

    local name, rest = input:match("^(%S+)%s*(.-)$")
    name = name and name:lower() or ""

    local command = commands[name]
    if command then
        command.handler(rest)
        return
    end

    if name:match("^%d+$") and ns.NumberCommand then
        ns.NumberCommand(tonumber(name))
        return
    end

    ns.Print(string.format("Unknown command: %s", name))
    showHelp()
end

SLASH_URLCOPY1 = "/urlcopy"
SLASH_URLCOPY2 = "/url"
SlashCmdList.URLCOPY = runCommand

-- Work to do once the player is in the world and the database exists. Each
-- file adds its own, so this one never learns what the others are called.
local loginHandlers = {}

function ns.OnLogin(handler)
    table.insert(loginHandlers, handler)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        ensureDatabase()
    elseif event == "PLAYER_LOGIN" then
        ensureDatabase()

        for _, handler in ipairs(loginHandlers) do
            handler()
        end

        ns.Print("Loaded. Type /url for commands.")
    end
end)
