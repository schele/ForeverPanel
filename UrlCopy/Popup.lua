local addonName, ns = ...

-- The copy box.
--
-- WoW has no clipboard API, and no addon can put anything on the clipboard.
-- The most any of them can do is present the text in a focused, fully selected
-- edit box so that Ctrl+C is a single keystroke. That is the whole of what
-- "copy" means here, and it is the ceiling for every addon of this kind.

local Popup = {}
ns.Popup = Popup

local DIALOG = "URLCOPY_LINK"

-- What the box is showing. The box resists being edited, and this is what it
-- is put back to.
local current = ""

-- Armed while we are writing the box's text ourselves, so the restore below
-- does not answer its own SetText and recurse.
local restoring = false

function Popup.Current()
    return current
end

--- The dialog's edit box, under either of the names clients give it.
local function boxOf(dialog)
    if dialog.editBox then
        return dialog.editBox
    end

    local name = dialog.GetName and dialog:GetName()
    return name and _G[name .. "EditBox"] or nil
end

local function present(box)
    if not box then
        return
    end

    restoring = true
    box:SetText(current)
    box:HighlightText()
    box:SetFocus()
    restoring = false
end

StaticPopupDialogs[DIALOG] = {
    text = "Ctrl+C to copy",
    button1 = OKAY or "Okay",
    hasEditBox = true,
    -- Wide enough for a link with a path on it; the box scrolls beyond that.
    editBoxWidth = 320,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    -- Out of the way of the dialogs the game puts up for itself.
    preferredIndex = 3,

    OnShow = function(self)
        present(boxOf(self))
    end,

    EditBoxOnTextChanged = function(self)
        if restoring or self:GetText() == current then
            return
        end

        -- Letting the player mangle the text before copying it serves nobody:
        -- this is a copy box wearing an edit box's clothes.
        present(self)
    end,

    EditBoxOnEnterPressed = function()
        StaticPopup_Hide(DIALOG)
    end,

    EditBoxOnEscapePressed = function()
        StaticPopup_Hide(DIALOG)
    end,
}

--- Put a URL in front of the player, selected and ready to copy.
function Popup.Show(url)
    if type(url) ~= "string" or url == "" then
        ns.Print("No link to copy yet. They are picked up as people say them.")
        return nil
    end

    current = url

    local dialog = StaticPopup_Show(DIALOG)
    if not dialog then
        -- Every popup slot taken, or the client refused it. Printing the URL
        -- at least puts it somewhere the player can read it.
        ns.Print(url)
        return nil
    end

    local box = boxOf(dialog)
    if not box then
        -- The dialog was shown but we could not find its edit box: the client
        -- did something unexpected. Printing the URL at least gets it to the
        -- player, since that is the thing they actually wanted.
        ns.Print("Could not locate the copy box. Here is the link instead: " .. url)
        return nil
    end

    -- Belt and braces: a client that shows the dialog without firing OnShow
    -- would otherwise leave an empty box on screen.
    present(box)
    return dialog
end
