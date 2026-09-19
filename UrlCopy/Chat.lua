local addonName, ns = ...

-- Chat integration: finding the URLs in a message, rewriting them as links,
-- catching the click, and remembering what has been seen.

ns.AddDefaults({
    chat = {
        -- On by default. Clickable links are the whole point, and on a client
        -- that forgets its SavedVariables, off by default is off every login.
        rewrite = true,
        shorten = false,
    },
    history = {
        size = 10,
    },
})

local Chat = {}
ns.Chat = Chat

local History = {}
ns.History = History

local DEFAULT_SIZE = 10

-- Newest first, and only for this session. Persisting a list of URLs would be
-- clutter, and this client discards SavedVariables anyway.
local seen = {}

--- Drop the oldest until at most `size` remain.
function History.Trim(size)
    size = math.max(tonumber(size) or DEFAULT_SIZE, 0)

    while #seen > size do
        table.remove(seen)
    end
end

function History.Add(url)
    if type(url) ~= "string" or url == "" then
        return
    end

    for index, existing in ipairs(seen) do
        if existing == url then
            table.remove(seen, index)
            break
        end
    end

    table.insert(seen, 1, url)
    History.Trim(ns.db and ns.db.history and ns.db.history.size)
end

function History.Get(index)
    return seen[index]
end

--- A copy, so a caller listing the history cannot edit it by accident.
function History.All()
    local copy = {}
    for index, url in ipairs(seen) do
        copy[index] = url
    end
    return copy
end

function History.Clear()
    seen = {}
end

-- ForeverPanel's blue: the same hand across both addons, and nothing like the
-- colours the game uses for item quality, so a link of ours never reads as one
-- of the game's.
local LINK_COLOR = "ff66ccff"
Chat.LINK_COLOR = LINK_COLOR

-- Past this many characters a link starts pushing the rest of the line off the
-- chat frame, which is the point at which showing the host alone earns its way.
local SHORTEN_OVER = 40

--- The link text for a URL: our own hyperlink type, coloured and bracketed.
function Chat.Link(url)
    local display = url
    if ns.db and ns.db.chat.shorten and #url > SHORTEN_OVER then
        display = ns.Detect.Shorten(url)
    end

    return string.format("|Hurlcopy:%s|h|c%s[%s]|r|h", url, LINK_COLOR, display)
end

--- Replace each span with its link.
-- Takes the spans rather than finding them, so the filter scans a message once
-- and feeds both the history and this from the one pass.
function Chat.Rewrite(message, spans)
    if not spans or #spans == 0 then
        return nil
    end

    local pieces = {}
    local cursor = 1

    for _, span in ipairs(spans) do
        pieces[#pieces + 1] = message:sub(cursor, span.from - 1)
        pieces[#pieces + 1] = Chat.Link(span.text)
        cursor = span.to + 1
    end

    pieces[#pieces + 1] = message:sub(cursor)
    return table.concat(pieces)
end

--- The chat filter. Returns nothing to leave a message alone, or false and a
-- replacement to change it, which is the contract ChatFrame.lua expects.
function Chat.Filter(_, _, message, ...)
    if type(message) ~= "string" then
        return false
    end

    local spans = ns.Detect.Find(message)
    if #spans == 0 then
        return false
    end

    -- Recorded whether or not chat is rewritten. That is what makes the switch
    -- safe to turn off: /url still has everything, so nothing is lost by it.
    for _, span in ipairs(spans) do
        ns.History.Add(span.text)
    end

    if not (ns.db and ns.db.chat.rewrite) then
        return false
    end

    return false, Chat.Rewrite(message, spans), ...
end

Chat.EVENTS = {
    "CHAT_MSG_SAY",
    "CHAT_MSG_YELL",
    "CHAT_MSG_EMOTE",
    "CHAT_MSG_GUILD",
    "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_WHISPER",
    "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER",
    "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_CHANNEL",
    "CHAT_MSG_SYSTEM",
}

local installed = false

--- Hook into chat. Idempotent: registering the same filter twice would run it
-- twice and wrap our own links in links.
function Chat.Install()
    if installed then
        return
    end
    installed = true

    if not ChatFrame_AddMessageEventFilter then
        ns.Print("This client has no chat filters. /url still works.")
        return
    end

    for _, event in ipairs(Chat.EVENTS) do
        ChatFrame_AddMessageEventFilter(event, Chat.Filter)
    end

    -- Hooked rather than replaced, so every other link type reaches the
    -- client's own handler untouched. It ignores a type it does not know,
    -- which is what leaves room for ours.
    if hooksecurefunc and SetItemRef then
        hooksecurefunc("SetItemRef", function(link)
            local url = type(link) == "string" and link:match("^urlcopy:(.+)$")
            if url then
                ns.Popup.Show(url)
            end
        end)
    end
end

ns.OnLogin(Chat.Install)

-- The one input that is not a named command. It belongs here rather than in
-- UrlCopy.lua because this is the file that knows what a link is.
ns.RegisterHelpLine("/url <n> - Copy the nth link from /url list, newest first")

ns.NumberCommand = function(index)
    local url = History.Get(index)
    if not url then
        ns.Print(string.format("No link %d. Try /url list.", index))
        return
    end

    ns.Popup.Show(url)
end

ns.RegisterCommand("list", "List the links being remembered", function()
    local all = History.All()
    if #all == 0 then
        ns.Print("No links seen yet. They are picked up as people say them.")
        return
    end

    for index, url in ipairs(all) do
        -- Clickable even with rewriting switched off: this is a direct answer
        -- to a command, and with the switch off it is the only way left to
        -- reach a link by clicking.
        ns.Print(string.format("%d. %s", index, Chat.Link(url)))
    end
end)

ns.RegisterCommand("clear", "Forget the remembered links", function()
    History.Clear()
    ns.Print("Forgotten.")
end)

ns.RegisterCommand("on", "Make URLs in chat clickable", function()
    ns.db.chat.rewrite = true
    ns.Print("Links in chat are clickable.")
end)

ns.RegisterCommand("off", "Leave chat alone", function()
    ns.db.chat.rewrite = false
    ns.Print("Chat left alone. /url still works.")
end)

-- Declared next to the code that reads them. Settings.lua renders whatever has
-- been declared, so adding one here needs no edit there.
ns.RegisterSetting({
    store = "chat",
    key = "rewrite",
    type = "checkbox",
    name = "Make URLs in chat clickable",
    tooltip = "Off leaves chat exactly as it arrives. /url still works, because links are remembered either way.",
})

ns.RegisterSetting({
    store = "chat",
    key = "shorten",
    type = "checkbox",
    name = "Shorten long links",
    tooltip = "Show just the site's name in chat for a long link. The box still gets the whole thing.",
})

ns.RegisterSetting({
    store = "history",
    key = "size",
    type = "slider",
    name = "Links to remember",
    min = 5,
    max = 25,
    step = 1,
    onChange = function(value)
        History.Trim(value)
    end,
})
