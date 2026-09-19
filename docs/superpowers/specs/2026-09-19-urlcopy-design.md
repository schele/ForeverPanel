# UrlCopy design

Date: 2026-09-19
Status: approved, ready for an implementation plan

## What it is

A World of Warcraft addon that makes URLs spoken in chat clickable, and puts
the one you click into a box you can copy out of.

WoW's chat frame cannot be selected with the mouse, so a URL someone types is
readable but unreachable: the only way to get it into a browser is to retype it
by hand. UrlCopy closes that gap.

## The ceiling, stated up front

**WoW has no clipboard API.** No addon can copy anything for you. The most any
of them can do is present the text in a focused, pre-selected edit box so that
Ctrl+C is a single keystroke. That is what "copy" means throughout this
document, and it is the ceiling for the whole category.

## Constraints

- Targets `## Interface: 11509, 16001` - Classic Era 1.15.x and the 1.60.x
  Classic beta, matching ForeverPanel.
- This client discards SavedVariables between sessions. Anything stored must
  behave sensibly when it comes back empty, and nothing important may depend on
  having been stored.
- The repo's layout rule: an addon is a top-level folder holding `<name>.toc`,
  and everything it needs lives inside it - Lua, tests, README. `run-tests.ps1`
  and `package.ps1` find addons by that rule and need no edit.
- `package.ps1` takes its file list from the `.toc`, so every Lua file must be
  listed there or it will not ship.

## Architecture

```
UrlCopy/
  UrlCopy.toc
  UrlCopy.lua      namespace, defaults, database, setting registry, slash commands
  Detect.lua       finding URLs in a string - pure functions, no WoW API
  Chat.lua         message filter, link rewriting, SetItemRef hook, history
  Popup.lua        the copy box
  Settings.lua     the panel
  README.md
  tests/           runner, stub, helpers, specs
```

Flat: UrlCopy has no module concept, so it needs no `Modules/` folder.

The split that matters is `Detect.lua` against `Chat.lua`. Detection is string
matching with no dependency on the game at all, which makes the subtle half of
the addon testable without constructing a single frame. `Chat.lua` knows when
and where to apply it; `Detect.lua` knows what a URL looks like. Neither knows
the other's business.

### Responsibilities and interfaces

**`UrlCopy.lua`** - the namespace every other file receives through `...`.
Carries, in the shape ForeverPanel established:

- `ns.PREFIX`, `ns.Print(message)`
- `ns.applyDefaults(target, source)`, `ns.AddDefaults(extra)`
- `ns.RegisterSetting(definition)`, `ns.SettingValue`, `ns.SetSettingValue`
- `ns.RegisterCommand(name, help, handler)` and the `/urlcopy` `/url` dispatch
- `ns.ensureDatabase()` and the `ADDON_LOADED` / `PLAYER_LOGIN` frame

`RegisterSetting` asserts that a default exists for the store and key it
addresses, the same as ForeverPanel: a setting with no default renders a
control that silently does nothing.

**`Detect.lua`** - `ns.Detect`:

- `Detect.Find(message)` returns an array of `{ text, from, to }`, in order of
  appearance, non-overlapping, and never inside one of the skipped regions
  described below. Returns an empty table when there is nothing.
- `Detect.Shorten(url)` returns the host alone, with no surrounding brackets -
  the caller supplies those, so the bracketing is the same whether a link is
  shortened or not. Pure; the caller decides whether to use it.
- The TLD allowlist lives here as a local set.

**`Chat.lua`** - `ns.Chat` and `ns.History`:

- `Chat.EVENTS` - the chat events the filter is registered for.
- `Chat.Rewrite(message, spans)` returns the rewritten message, or `nil` when
  nothing changed. It takes the spans rather than finding them, so the filter
  scans each message once and feeds both the history and the rewrite from that
  one pass. Called directly by the tests.
- `Chat.Filter(self, event, message, ...)` - the registered filter.
- `Chat.Install()` - registers the filter and hooks `SetItemRef`, once, at
  `PLAYER_LOGIN`.
- `History.Add(url)`, `History.Get(index)`, `History.All()`, `History.Clear()`,
  `History.Trim(size)`.

`ns.History` is a distinct table with its own functions, living in `Chat.lua`
because it is small and has one caller. If `Chat.lua` grows past comfortable
reading, history is the seam to cut along.

**`Popup.lua`** - `ns.Popup.Show(url)`. Owns the `StaticPopupDialogs` entry.

**`Settings.lua`** - renders whatever `ns.RegisterSetting` has collected, and
registers the category. A slimmed version of ForeverPanel's: checkbox and
slider only, one column, no key table.

## Detection

Four rules, applied left to right across the message, first match wins at any
position:

| Rule | Example | Notes |
|---|---|---|
| Scheme | `https://example.com/a/b?c=d` | `http`, `https`, `ftp` |
| `www.` prefix | `www.example.co.uk/path` | No scheme needed |
| IPv4 | `62.109.4.12`, `62.109.4.12:3724` | Optional port, for server addresses |
| Bare domain | `example.com/path`, `discord.gg/abc` | TLD must be on the allowlist |

All four accept an optional `:port`. Every match has trailing punctuation
stripped - full stop, comma, semicolon, colon, exclamation mark, question mark,
closing bracket, quote - so "see example.com." links the domain and not the
sentence's full stop.

### The TLD allowlist

The bare-domain rule is the only one that can fire on text nobody meant as a
URL, and the allowlist is what keeps it honest.

Included: `com net org edu gov mil info biz io gg tv dev app co ly gl xyz
online site shop live news wiki se nu dk fi uk de fr nl pl eu ca au ru br jp
cz es pt ch`

Deliberately excluded, though all are real TLDs: `no it is me at in be by to so
us am as do re`. Each of them collides with ordinary English or Swedish in
chat - "wait.no", "call.me", "look.at" - and turning a sentence into a link is
a worse failure than missing an exotic domain. Anyone writing one of those
properly, with `https://` or `www.`, is still caught by the first two rules.

`ly` and `gl` are in despite the same risk, because `bit.ly` and `goo.gl` are
common enough in practice to be worth it.

### Regions the scanner skips

`Detect.Find` never returns a span that starts inside:

- An existing hyperlink, from `|H` through its closing `|h`. Item links,
  achievement links and other addons' links can contain URL-shaped text;
  matching inside one produces a nested link and corrupts the chat frame's
  parsing.
- A colour or texture escape - `|cffrrggbb`, `|r`, `|T...|t`.

### URLs containing a pipe are refused

`|` is WoW's escape character. A URL containing one is dropped rather than
linked: wrapping it would let a crafted message close our link early and inject
its own markup into the player's chat frame.

## Chat integration

`Chat.Install()` runs once at `PLAYER_LOGIN`:

1. `ChatFrame_AddMessageEventFilter(event, Chat.Filter)` for each of
   `Chat.EVENTS`: `CHAT_MSG_SAY`, `YELL`, `EMOTE`, `GUILD`, `OFFICER`,
   `PARTY`, `PARTY_LEADER`, `RAID`, `RAID_LEADER`, `RAID_WARNING`,
   `INSTANCE_CHAT`, `INSTANCE_CHAT_LEADER`, `WHISPER`, `WHISPER_INFORM`,
   `BN_WHISPER`, `BN_WHISPER_INFORM`, `CHANNEL`, `SYSTEM`.
2. `hooksecurefunc("SetItemRef", ...)`.

The filter, per message:

1. `Detect.Find(message)`.
2. Every URL found goes to `History.Add`, **whether or not the message gets
   rewritten**. This is what makes `/url` a genuine fallback: with the
   rewriting toggled off, chat is untouched but the history still fills.
3. If `chat.rewrite` is off, return nothing - the message passes through
   unchanged.
4. Otherwise return the filter's "changed" result: `false` followed by the
   rewritten message and the remaining arguments unaltered. The rewritten
   message has each span replaced with
   `|Hurlcopy:<url>|h|cff66ccff[<display>]|r|h`, where `<display>` is the URL,
   or `Detect.Shorten(url)` when `chat.shorten` is on and the URL is longer
   than 40 characters.

`ff66ccff` is the colour ForeverPanel uses for its own prefix - the same hand
across both addons, and clearly distinct from item-link colours.

The URL is carried inside the link itself rather than as an index into the
history, so a link that has scrolled up still works after the history has
evicted it, and the click path holds no state.

The `SetItemRef` hook acts only on links matching `urlcopy:` followed by the
URL, and returns immediately for anything else, so no other link type changes
behaviour. It runs after the client's own handler, which ignores link types it
does not know.

## The copy box

A `StaticPopupDialogs["URLCOPY_LINK"]` entry with `hasEditBox = true`, a
widened `editBoxWidth`, one `Okay` button, `hideOnEscape`, `whileDead`, and no
timeout.

- On show: the edit box gets the URL, focus, and `HighlightText()` - everything
  selected, so Ctrl+C takes the lot.
- Enter or Escape closes it.
- Typing in the box restores the URL and re-selects it. It is a copy box
  wearing an edit box's clothes; letting the player mangle the text before
  copying it serves nobody.
- Clicking a second link while it is open replaces the text.

## History

In memory for the session only, never saved. Persisting a list of URLs would be
clutter, and this client discards SavedVariables regardless.

- Newest first.
- A URL already present moves to the front instead of being added twice.
- Capped at `history.size`. Changing the slider calls `History.Trim` at once,
  so the list matches the number on screen.

## Settings

Stored in `UrlCopyDB`:

```lua
{
    version = 1,
    chat    = { rewrite = true, shorten = false },
    history = { size = 10 },
}
```

The panel, in declaration order:

| Control | Store | Default | Does |
|---|---|---|---|
| Make URLs in chat clickable | `chat.rewrite` | on | Master toggle. Off means chat is untouched; `/url` still works |
| URLs to remember | `history.size` | 10 | Slider, 5-25. Shrinking it trims the history immediately |
| Shorten long links | `chat.shorten` | off | Show only the host in chat for URLs over 40 characters. The box still gets the whole URL |

`chat.rewrite` defaults on: the addon's entire point is clickable links, and a
feature that is off by default is off at every login on a client that forgets
its SavedVariables.

No link-colour picker. `ColorPickerFrame`'s API changed shape in 10.2.5 and
again after, and guessing wrong there registers nothing and fails silently -
the most fragile thing the addon could contain, for the least return. The
colour is a named constant at the top of `Chat.lua`.

`Settings.lua` carries over ForeverPanel's handling of the game menu: opening
the options panel from a slash command and then closing it leaves the player in
the game menu rather than back in the world, and the fix is already known.

## Commands

`/urlcopy`, short form `/url`:

| Command | Does |
|---|---|
| `/url` | Open the box on the most recent URL |
| `/url list` | Print the remembered URLs, numbered, each one clickable |
| `/url <n>` | Open the box on the nth URL from that list |
| `/url on` / `/url off` | The rewriting toggle, mirroring the checkbox |
| `/url clear` | Forget the remembered URLs |
| `/url settings` | Open the panel |
| `/url help` | The command list |

Bare `/url` opens the most recent URL rather than printing help, which is the
one place this departs from ForeverPanel's convention. The common case deserves
the shortest gesture, and `/url help` is still there.

`/url list` prints its own clickable links even when `chat.rewrite` is off -
that output is a direct answer to a command, and with rewriting off it is the
only way to reach a URL by clicking.

Each command is registered next to the code that owns it, as in ForeverPanel:
`list`, `clear`, `on`, `off` and the numeric form in `Chat.lua`, `settings` in
`Settings.lua`.

## Testing

Lua 5.4, run outside the game against a stubbed API, driven by the repo's
`run-tests.ps1`. `tests/runner.lua` and `tests/helpers.lua` are taken from
ForeverPanel unchanged in shape; `tests/wow_stub.lua` is a trimmed copy with
additions for this addon:

- `ChatFrame_AddMessageEventFilter`, recording filters per event, plus a helper
  to push a message through them and read the result.
- A global `SetItemRef`, and a `hooksecurefunc` that accepts the two-argument
  form `hooksecurefunc(name, post)` as well as the three-argument one
  ForeverPanel's stub already supports.
- `StaticPopupDialogs` and `StaticPopup_Show`, recording the dialog shown and
  exposing its edit box so tests can read what would have been copied.

Specs:

| File | Covers |
|---|---|
| `detect_spec.lua` | All four rules; optional ports; trailing punctuation; several URLs in one line; spans inside existing hyperlinks and colour escapes; pipe-bearing URLs refused; every excluded TLD staying unlinked; `Shorten` |
| `chat_spec.lua` | Filter rewrites a message; rewriting off leaves it untouched but still records; the link's payload round-trips through `SetItemRef`; other link types ignored; shortened display still copies the full URL |
| `history_spec.lua` | Newest first; a repeat moves rather than duplicates; the cap holds; `/url list` and `/url <n>`; `/url clear` |
| `settings_spec.lua` | Defaults applied; a stored value beats a default; the toggle changes filter behaviour; shrinking the slider trims the history |

`detect_spec.lua` carries the weight, because detection is where this addon is
either right or quietly wrong. Frame behaviour and the real chat frame can only
be confirmed in the client; the tests cover the logic around them.

The stub is a copy rather than a shared file. That is what the repo's "every
addon is self-contained" rule asks for, and sharing it would mean changing
`run-tests.ps1` and the layout rule for both addons. Worth extracting when a
third addon wants it, not before.

## Out of scope

- Copying whole chat lines or scrollback. Ruled out during brainstorming.
- URLs anywhere but chat - quest text, guild information, tooltips.
- Opening a URL in a browser. No client API can, and nothing claiming to should
  be trusted.
- Replacing `ChatFrame:AddMessage` to catch addon and system output that has no
  `CHAT_MSG_*` event. It is a shared resource, two addons doing it is how chat
  breaks, and the extra coverage is not worth that.
- Persisting the history.
- A link-colour picker, for the reason given above.

## Install and packaging

Nothing to add: the repo's scripts find the addon by its `.toc`.

```powershell
.\run-tests.ps1 UrlCopy
.\package.ps1 UrlCopy -Install
```

The root `README.md` gains a row in its addon table.
