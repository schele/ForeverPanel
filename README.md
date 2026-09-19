# WoWAddons

World of Warcraft addons, one folder each.

| Addon | What it is |
|---|---|
| [ForeverPanel](ForeverPanel/) | A full-width bar across the top of the screen showing XP, money, bag space and the time |
| [UrlCopy](UrlCopy/) | Makes URLs spoken in chat clickable, and opens the one you click in a box you can copy from |

## Layout

An addon is any top-level folder containing `<name>.toc`. Everything it needs
lives inside: its Lua, its `Modules/`, its own `tests/` and its own README. The
two scripts at the root find addons by that rule, so adding one means adding a
folder and nothing else.

## Tests

```powershell
.\run-tests.ps1                  # every addon
.\run-tests.ps1 ForeverPanel     # just one
```

Each suite runs with its own addon folder as the working directory, so a test
never needs to know where the repo sits or that other addons exist.

Requires Lua 5.4 (`winget install --id DEVCOM.Lua`). Set `$env:LUA_EXE` to point
at a different interpreter.

## Packaging

```powershell
.\package.ps1                             # every addon -> dist/
.\package.ps1 ForeverPanel                # just one
.\package.ps1 ForeverPanel -Install       # and copy it into the client
```

Each zip contains a single top-level folder named after the addon, so it
extracts straight into `Interface/AddOns`. The file list comes from the `.toc`
rather than a glob: anything added there ships, and anything listed but missing
fails the build instead of shipping broken.

`-Install` defaults to the Classic beta client. `-WowPath` picks another:

```powershell
.\package.ps1 ForeverPanel -Install -WowPath "C:\Program Files (x86)\World of Warcraft\_retail_"
```
