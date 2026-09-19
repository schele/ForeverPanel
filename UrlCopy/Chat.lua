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
    size = tonumber(size) or DEFAULT_SIZE

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
