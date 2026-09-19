local helpers = require("helpers")

-- The icon comes first, so stripping it leaves a leading space.
local function plain(text)
    return (helpers.plain(text):gsub("^%s+", ""))
end

local function loggedIn()
    local ns, env = helpers.loadAddon()
    helpers.login(ns, env)
    helpers.firstFrame(env)
    return ns, env
end

describe("FormatBagSpace", function()
    local ns = helpers.loadAddon()

    it("shows the free count after a bag icon", function()
        assertEqual("12", plain(ns.FormatBagSpace(12, 12)))
        assertMatch("INV_Misc_Bag", ns.FormatBagSpace(12, 12))
    end)

    it("renders the icon at the size asked for", function()
        assertMatch(":16:16:", ns.FormatBagSpace(1, 16))
    end)

    it("treats a negative or missing count as none free", function()
        assertEqual("0", plain(ns.FormatBagSpace(-3, 12)))
        assertEqual("0", plain(ns.FormatBagSpace(nil, 12)))
    end)
end)

describe("counting free slots", function()
    it("adds up every general purpose bag", function()
        local ns, env = loggedIn()

        -- 4 + 6 + 2 from the stub's bags.
        assertEqual(12, ns.FreeBagSlots())
    end)

    it("ignores a bag that only takes particular items", function()
        local ns, env = loggedIn()

        -- A quiver or herb bag: its free slots are no use for loot in general,
        -- so counting them would overstate the space available.
        env.bagSlots[3] = { free = 20, kind = 2 }

        assertEqual(12, ns.FreeBagSlots(), "the special bag is left out")
    end)

    it("leaves a special bag out of the total as well as the free count", function()
        local ns, env = loggedIn()

        -- A 16 slot herb bag. Neither number should notice it, or the block
        -- reads 11/36 when the usable space is 11/20.
        env.bagSlots[3] = { free = 16, total = 16, kind = 2 }

        assertEqual(12, ns.FreeBagSlots(), "free ignores it")
        assertEqual(40, ns.TotalBagSlots(), "and so does the total")
    end)

    it("copes with a client that has no container API", function()
        local ns, env = loggedIn()
        env.C_Container = nil

        assertEqual(0, ns.FreeBagSlots())
    end)
end)

describe("bag space settings", function()
    it("drops the total when it is turned off", function()
        local ns, env = loggedIn()

        -- Away from the default, or a block that ignores the setting entirely
        -- would pass this.
        ns.db.bags.showTotal = false
        ns.Bar:GetModule("bags"):Refresh()

        assertEqual("12", plain(ns.Bar:GetModule("bags").text:GetText()))
    end)

    it("hangs its settings under the module's own switch", function()
        local ns, env = loggedIn()

        local setting
        for _, candidate in ipairs(ns.settings) do
            if candidate.store == "bags" and candidate.key == "showTotal" then
                setting = candidate
            end
        end

        assertTrue(setting ~= nil, "on the settings panel")
        assertEqual("modules.bags", setting.parent, "indented under Show bag space")
    end)

    it("redraws the block as soon as the setting changes", function()
        local ns, env = loggedIn()

        local setting
        for _, candidate in ipairs(ns.settings) do
            if candidate.key == "showTotal" then
                setting = candidate
            end
        end

        ns.SetSettingValue(setting, false)
        assertEqual("12", plain(ns.Bar:GetModule("bags").text:GetText()), "redrawn without it")

        ns.SetSettingValue(setting, true)
        assertEqual("12/40", plain(ns.Bar:GetModule("bags").text:GetText()), "and back again")
    end)
end)

describe("the bar's left side", function()
    it("reads money, bags, then xp", function()
        local ns, env = loggedIn()

        local money = ns.Bar:GetModule("money").order
        local bags = ns.Bar:GetModule("bags").order
        local xp = ns.Bar:GetModule("xp").order

        assertTrue(money < bags, "bags sits right of money")
        assertTrue(bags < xp, "and left of the xp block")
    end)
end)

describe("the bags module", function()
    it("shows the free count on the bar", function()
        local ns, env = loggedIn()

        assertEqual("12/40", plain(ns.Bar:GetModule("bags").text:GetText()))
    end)

    it("follows a bag change", function()
        local ns, env = loggedIn()

        -- The bag filled up; it did not shrink, so the total is unchanged.
        env.bagSlots[1] = { free = 0, total = 16, kind = 0 }
        helpers.fire(env, "BAG_UPDATE_DELAYED")

        assertEqual("6/40", plain(ns.Bar:GetModule("bags").text:GetText()))
    end)

    it("opens the bags when clicked", function()
        local ns, env = loggedIn()

        local module = ns.Bar:GetModule("bags")
        module.frame.scripts.OnClick(module.frame, "LeftButton")

        assertTrue(env.__bagsOpened, "a click opens the bags")
    end)

    it("gets a visibility switch like every other module", function()
        local ns, env = loggedIn()

        local found
        for _, setting in ipairs(ns.settings) do
            if setting.store == "modules" and setting.key == "bags" then
                found = setting
            end
        end

        assertTrue(found ~= nil, "on the settings panel")
        assertEqual("Show bag space", found.name)
    end)
end)
