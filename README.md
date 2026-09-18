# ForeverPanel (World of Warcraft AddOn)

A full-width bar across the top of the screen showing at-a-glance information.

Out of the box:

| Side | Module | Shows |
|---|---|---|
| Left | `xp` | `xx.xx% left` until the next level, hidden at max level or with XP turned off |
| Centre | `clock` | Local time, click to toggle 12/24 hour |
| Right | `money` | Gold, silver and copper with the in-game coin icons |

The bar reserves its own strip of screen: it insets `UIParent` from the top, so
top-anchored Blizzard frames move down with it instead of being covered.

Modules are rearranged by dragging them along the bar. The bar reorders live
while you hold one, so it is its own drag preview, and the layout is saved
between sessions. Which third of the bar you drop in picks the side, so a
module can move from the right group to the centre or left. `/fp bar lock`
stops accidental drags and `/fp bar reset` puts everything back.

## Install

1. Copy this folder into your client's `Interface/AddOns` as `ForeverPanel`,
   so the result is `.../Interface/AddOns/ForeverPanel/ForeverPanel.toc`.
2. Restart the client and enable ForeverPanel from the AddOns list.

Built against Classic Era 1.15.x (`11509`) and the 1.60.x Classic beta
(`16001`). For retail, change `## Interface` in the .toc to the current retail
interface version.

## Commands

`/foreverpanel` or the short `/fp`:

- `/fp` - Show help
- `/fp bar` - Show or hide the bar
- `/fp bar height <16-48>` - Set the bar height
- `/fp bar push` - Toggle reserving space (off = overlay the UI instead)
- `/fp bar lock` - Stop modules being dragged
- `/fp bar reset` - Restore the default module order
- `/fp clock` - Toggle 12/24 hour time
- `/fp clock blizzard` - Show or hide Blizzard's own clock
- `/fp status` - Show launch and note counts
- `/fp note <text>` - Save a persistent note
- `/fp last` - Show most recent note
- `/fp clear` - Remove all notes

## Adding a module

`Bar.lua` owns the frame, layout and event plumbing. A module just describes
itself, so adding one means a new file in `Modules/` and a line in the .toc —
no edits to `Bar.lua`.

```lua
local addonName, ns = ...

ns.Bar:RegisterModule({
    name     = "durability",
    side     = "LEFT",              -- LEFT | CENTER | RIGHT
    order    = 20,                  -- ascending within a side
    events   = { "UPDATE_INVENTORY_DURABILITY" },
    interval = nil,                 -- optional polling, in seconds

    OnCreate = function(module)
        module.text = module.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        module.text:SetPoint("LEFT")
    end,

    OnUpdate = function(module)
        module.text:SetText("100%")
        module:SetWidth(module.text:GetStringWidth())
    end,

    OnClick = function(module, button) end,   -- optional
})
```

The bar gives every module a container `Button` at `module.frame`, plus:

- `module:SetWidth(width)` - report your content width so the bar can lay out
- `module:SetShown(shown)` - hide yourself; the bar closes the gap
- `module:Refresh()` - re-run `OnUpdate`
- `module:MarkDirty()` - request a re-layout

Layout rules: `LEFT` flows left-to-right from the left edge, `RIGHT` flows
right-to-left from the right edge, and `CENTER` is laid out as one group
centred on the bar. Hidden modules take their spacing with them.

`side` and `order` here are only the defaults. Once a module has been dragged,
the position saved in `ForeverPanelDB.bar.layout` wins, until `/fp bar reset`.

## Tests

The formatting, layout and registry logic is covered by unit tests that run
outside the game against a stubbed WoW API (`tests/wow_stub.lua`).

```powershell
.\run-tests.ps1
```

Requires Lua 5.4 (`winget install --id DEVCOM.Lua`). Set `$env:LUA_EXE` to
point at a different interpreter. To run it by hand:

```
lua tests/runner.lua tests/format_spec.lua tests/layout_spec.lua tests/addon_spec.lua
```

Frame behaviour and the `UIParent` inset can only really be confirmed in the
game client; the tests cover the logic around them.
