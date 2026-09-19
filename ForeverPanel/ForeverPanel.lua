local addonName, ns = ...

ns.PREFIX = "|cff66ccffForeverPanel|r"

-- Defaults are contributed by each file at load time (Bar.lua and the modules
-- add their own), so every piece of config lives next to the code that uses it.
local defaults = {
    version = 1,
    launches = 0,
    notes = {},
}

--- Merge a defaults table into a saved table without clobbering stored values.
-- Recursive so nested config (bar settings, per-module settings) gets filled in
-- on upgrade instead of being reset to an empty table.
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

-- Settings registry. A module declares the config it owns, the same way it
-- contributes defaults and slash commands, and Settings.lua renders whatever
-- has been declared. Adding a module therefore needs no edit to Settings.lua.
local settings = {}
ns.settings = settings

-- What Settings.lua knows how to render.
local SETTING_TYPES = { checkbox = true, slider = true, keytable = true }

--- Declare a configurable value.
-- store/key address it inside the database (ns.db[store][key]); type is
-- "checkbox" or "slider"; onChange runs after a change so the owner can react.
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

    -- A setting with no default would read nil and write somewhere nothing
    -- else looks at, which shows up as a control that silently does nothing.
    assert(
        defaults[store] ~= nil and defaults[store][key] ~= nil,
        string.format("no default registered for %s.%s", store, key)
    )

    table.insert(settings, definition)
    return definition
end

--- Current value of a setting, straight from the database.
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

function ns.Print(message)
    print(string.format("%s %s", ns.PREFIX, message))
end

local function ensureDatabase()
    -- Carry data over from the addon's previous name.
    if type(ForeverPanelDB) ~= "table" and type(ForeverDB) == "table" then
        ForeverPanelDB = ForeverDB
    end

    if type(ForeverPanelDB) ~= "table" then
        ForeverPanelDB = {}
    end

    applyDefaults(ForeverPanelDB, defaults)
    ns.db = ForeverPanelDB
end

ns.ensureDatabase = ensureDatabase

-- Slash command registry. Modules register their own subcommands so each
-- feature owns its commands and its help text.
local commands = {}
ns.commands = commands

function ns.RegisterCommand(name, help, handler)
    commands[name] = { help = help, handler = handler }
end

local function showHelp()
    ns.Print("Commands:")

    local names = {}
    for name in pairs(commands) do
        table.insert(names, name)
    end
    table.sort(names)

    for _, name in ipairs(names) do
        ns.Print(string.format("/fp %s - %s", name, commands[name].help))
    end
end

ns.ShowHelp = showHelp

local function addNote(text)
    if text == nil or text == "" then
        ns.Print("Usage: /fp note <text>")
        return
    end

    table.insert(ns.db.notes, {
        at = date("%Y-%m-%d %H:%M:%S"),
        text = text,
    })

    if #ns.db.notes > 100 then
        table.remove(ns.db.notes, 1)
    end

    ns.Print("Saved note forever.")
end

ns.RegisterCommand("status", "Show launches and saved notes count", function()
    ns.Print(string.format("Launches: %d | Notes stored: %d", ns.db.launches, #ns.db.notes))
end)

ns.RegisterCommand("note", "Save a note", addNote)

ns.RegisterCommand("last", "Show your most recent note", function()
    local last = ns.db.notes[#ns.db.notes]
    if not last then
        ns.Print("No notes yet. Try: /fp note Your message")
        return
    end

    ns.Print(string.format("Last note [%s]: %s", last.at, last.text))
end)

ns.RegisterCommand("clear", "Remove all notes", function()
    ns.db.notes = {}
    ns.Print("All notes cleared.")
end)

local function runCommand(msg)
    local input = msg and msg:match("^%s*(.-)%s*$") or ""

    if input == "" or input == "help" then
        showHelp()
        return
    end

    local name, rest = input:match("^(%S+)%s*(.-)$")
    name = name and name:lower() or ""

    local command = commands[name]
    if command then
        command.handler(rest)
    else
        ns.Print(string.format("Unknown command: %s", name))
        showHelp()
    end
end

SLASH_FOREVERPANEL1 = "/foreverpanel"
SLASH_FOREVERPANEL2 = "/fp"
SlashCmdList.FOREVERPANEL = runCommand

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        ensureDatabase()
    elseif event == "PLAYER_LOGIN" then
        ensureDatabase()
        ns.db.launches = ns.db.launches + 1
        ns.Bar:Initialize()
        ns.Print("Loaded. Type /fp for commands.")
    end
end)
