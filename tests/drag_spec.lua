local helpers = require("helpers")

local BAR_WIDTH = 900

--- Log in with a bar of a known width, so cursor maths is predictable.
-- XP is given a real value so all three modules are visible; with the stub's
-- 6-units-per-character metrics that puts xp at centre 43 and money at 78 wide.
local function loggedIn(options)
    options = options or {}
    local ns, env = helpers.loadAddon()

    if not options.maxLevel then
        env.xp, env.xpMax = 500, 1000
    end

    helpers.login(ns, env)
    env.ForeverBar.width = BAR_WIDTH
    env.ForeverBar.left = 0
    return ns, env
end

--- Drag a module by holding it, moving the cursor to x, and letting go.
local function dragTo(ns, env, name, x)
    local module = ns.Bar:GetModule(name)
    module.frame.scripts.OnDragStart(module.frame)
    env.cursorX = x
    ns.Bar:UpdateDrag()
    module.frame.scripts.OnDragStop(module.frame)
    env.__runTimers()
    return module
end

local function orderOn(ns, side)
    local list = {}
    for _, name in ipairs({ "xp", "clock", "money" }) do
        local module = ns.Bar:GetModule(name)
        if module.side == side then
            table.insert(list, module)
        end
    end
    table.sort(list, function(a, b)
        return a.order < b.order
    end)

    local names = {}
    for index, module in ipairs(list) do
        names[index] = module.name
    end
    return table.concat(names, ",")
end

describe("SideForCursor", function()
    local ns = helpers.loadAddon()

    it("splits the bar into thirds", function()
        assertEqual("LEFT", ns.Bar.SideForCursor(10, 900))
        assertEqual("LEFT", ns.Bar.SideForCursor(299, 900))
        assertEqual("CENTER", ns.Bar.SideForCursor(300, 900))
        assertEqual("CENTER", ns.Bar.SideForCursor(599, 900))
        assertEqual("RIGHT", ns.Bar.SideForCursor(600, 900))
        assertEqual("RIGHT", ns.Bar.SideForCursor(890, 900))
    end)

    it("falls back to centre for a bar with no width", function()
        assertEqual("CENTER", ns.Bar.SideForCursor(10, 0))
        assertEqual("CENTER", ns.Bar.SideForCursor(10, nil))
    end)
end)

describe("DropIndex", function()
    local ns = helpers.loadAddon()
    local centers = { a = 100, b = 200, c = 300 }
    local names = { "a", "b", "c" }

    it("inserts before everything when left of the first module", function()
        assertEqual(1, ns.Bar.DropIndex(names, centers, 50))
    end)

    it("inserts between modules", function()
        assertEqual(2, ns.Bar.DropIndex(names, centers, 150))
        assertEqual(3, ns.Bar.DropIndex(names, centers, 250))
    end)

    it("appends when right of everything", function()
        assertEqual(4, ns.Bar.DropIndex(names, centers, 999))
    end)

    it("returns the first slot for an empty side", function()
        assertEqual(1, ns.Bar.DropIndex({}, centers, 400))
    end)
end)

describe("ComputeCenters", function()
    local ns = helpers.loadAddon()

    it("measures from the left edge whatever side a module is anchored to", function()
        local centers = ns.Bar.ComputeCenters({
            { name = "l", side = "LEFT", order = 1, width = 100 },
            { name = "c", side = "CENTER", order = 1, width = 100 },
            { name = "r", side = "RIGHT", order = 1, width = 100 },
        }, 900, { padding = 10, spacing = 16 })

        assertNear(60, centers.l, 0.001, "10 padding + half of 100")
        assertNear(450, centers.c, 0.001, "centred on a 900 wide bar")
        assertNear(840, centers.r, 0.001, "900 - 10 padding - half of 100")
    end)
end)

describe("dragging a module", function()
    it("moves a module to another side", function()
        local ns, env = loggedIn()

        assertEqual("RIGHT", ns.Bar:GetModule("money").side)
        dragTo(ns, env, "money", 20)

        assertEqual("LEFT", ns.Bar:GetModule("money").side)
        assertEqual("money,xp", orderOn(ns, "LEFT"), "dropped left of xp")
    end)

    it("reorders within a side", function()
        local ns, env = loggedIn()

        dragTo(ns, env, "money", 20)
        assertEqual("money,xp", orderOn(ns, "LEFT"))

        -- Now drop money to the right of xp, still on the left third.
        dragTo(ns, env, "money", 290)
        assertEqual("xp,money", orderOn(ns, "LEFT"))
    end)

    it("dims the module while it is held and restores it on drop", function()
        local ns, env = loggedIn()
        local module = ns.Bar:GetModule("money")

        module.frame.scripts.OnDragStart(module.frame)
        assertTrue(module.frame:GetAlpha() < 1, "the held module is dimmed")
        assertTrue(ns.Bar:IsDragging())

        module.frame.scripts.OnDragStop(module.frame)
        assertEqual(1, module.frame:GetAlpha())
        assertFalse(ns.Bar:IsDragging())
    end)

    it("does nothing while the bar is locked", function()
        local ns, env = loggedIn()
        helpers.command(env, "bar lock")
        assertTrue(ns.db.bar.locked)

        dragTo(ns, env, "money", 20)

        assertEqual("RIGHT", ns.Bar:GetModule("money").side, "money stayed put")
        assertFalse(ns.Bar:IsDragging())
    end)

    it("keeps the layout consistent after a move", function()
        local ns, env = loggedIn()
        dragTo(ns, env, "money", 20)

        assertEqual("LEFT", ns.Bar:GetModule("money").frame:GetPoint(1))
        assertEqual("LEFT", ns.Bar:GetModule("xp").frame:GetPoint(1))
    end)

    it("drops onto a side whose only module is hidden", function()
        -- At max level the xp module is hidden, so the left side looks empty.
        local ns, env = loggedIn({ maxLevel = true })
        assertFalse(ns.Bar:GetModule("xp").shown, "xp is hidden at max level")

        dragTo(ns, env, "clock", 20)

        assertEqual("LEFT", ns.Bar:GetModule("clock").side)
        assertEqual("clock,xp", orderOn(ns, "LEFT"), "lands in front, not behind the hidden module")
        assertEqual("LEFT", ns.Bar:GetModule("clock").frame:GetPoint(1))
    end)
end)

describe("saved module order", function()
    it("writes the new order to saved variables", function()
        local ns, env = loggedIn()
        dragTo(ns, env, "money", 20)

        local saved = ns.db.bar.layout
        assertEqual("LEFT", saved.money.side)
        assertTrue(type(saved.money.order) == "number")
        assertTrue(saved.money.order < saved.xp.order, "money sorts before xp")
    end)

    it("restores the order on the next login", function()
        local first, firstEnv = loggedIn()
        dragTo(first, firstEnv, "money", 20)
        local stored = firstEnv.ForeverPanelDB

        local second, secondEnv = helpers.loadAddon()
        secondEnv.ForeverPanelDB = stored
        helpers.login(second, secondEnv)

        assertEqual("LEFT", second.Bar:GetModule("money").side)
        assertEqual("money,xp", orderOn(second, "LEFT"))
    end)

    it("puts everything back with bar reset", function()
        local ns, env = loggedIn()
        dragTo(ns, env, "money", 20)
        assertEqual("LEFT", ns.Bar:GetModule("money").side)

        helpers.command(env, "bar reset")

        assertEqual("RIGHT", ns.Bar:GetModule("money").side)
        assertEqual("LEFT", ns.Bar:GetModule("xp").side)
        assertEqual("CENTER", ns.Bar:GetModule("clock").side)
        assertEqual(0, next(ns.db.bar.layout) and 1 or 0, "saved layout cleared")
    end)

    it("ignores a saved entry with a nonsense side", function()
        local ns, env = helpers.loadAddon()
        env.ForeverPanelDB = { bar = { layout = { money = { side = "TOP", order = 5 } } } }
        helpers.login(ns, env)

        assertEqual("RIGHT", ns.Bar:GetModule("money").side, "fell back to the default")
    end)
end)
