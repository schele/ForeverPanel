local helpers = require("helpers")

local ns = helpers.loadAddon()
local computeLayout = ns.Bar.ComputeLayout

local OPTIONS = { padding = 10, spacing = 16 }

describe("ComputeLayout", function()
    it("flows the left side rightwards from the left edge", function()
        local positions = computeLayout({
            { name = "a", side = "LEFT", order = 1, width = 50 },
            { name = "b", side = "LEFT", order = 2, width = 30 },
        }, OPTIONS)

        assertEqual("LEFT", positions.a.anchor)
        assertEqual(10, positions.a.offset)
        assertEqual(10 + 50 + 16, positions.b.offset)
    end)

    it("flows the right side leftwards from the right edge", function()
        local positions = computeLayout({
            { name = "a", side = "RIGHT", order = 1, width = 50 },
            { name = "b", side = "RIGHT", order = 2, width = 30 },
        }, OPTIONS)

        assertEqual("RIGHT", positions.a.anchor)
        assertEqual(-10, positions.a.offset)
        assertEqual(-(10 + 50 + 16), positions.b.offset)
    end)

    it("centres a single centre module on the bar", function()
        local positions = computeLayout({
            { name = "only", side = "CENTER", order = 1, width = 80 },
        }, OPTIONS)

        assertEqual("CENTER", positions.only.anchor)
        assertNear(0, positions.only.offset)
    end)

    it("centres a centre group as a whole", function()
        local positions = computeLayout({
            { name = "a", side = "CENTER", order = 1, width = 40 },
            { name = "b", side = "CENTER", order = 2, width = 40 },
        }, OPTIONS)

        -- Total width 40 + 16 + 40 = 96, so the group spans -48 .. 48 and each
        -- module's centre sits 28 either side of the bar centre.
        assertNear(-28, positions.a.offset)
        assertNear(28, positions.b.offset)
    end)

    it("orders by order, then by name for ties", function()
        local positions = computeLayout({
            { name = "zebra", side = "LEFT", order = 5, width = 10 },
            { name = "alpha", side = "LEFT", order = 5, width = 10 },
        }, OPTIONS)

        assertEqual(10, positions.alpha.offset)
        assertEqual(10 + 10 + 16, positions.zebra.offset)
    end)

    it("drops hidden modules and reclaims their spacing", function()
        local positions = computeLayout({
            { name = "a", side = "LEFT", order = 1, width = 50 },
            { name = "gone", side = "LEFT", order = 2, width = 999, shown = false },
            { name = "b", side = "LEFT", order = 3, width = 30 },
        }, OPTIONS)

        assertNil(positions.gone, "hidden modules get no position")
        assertEqual(10 + 50 + 16, positions.b.offset, "b closes the gap")
    end)

    it("keeps the three sides independent", function()
        local positions = computeLayout({
            { name = "l", side = "LEFT", order = 1, width = 20 },
            { name = "c", side = "CENTER", order = 1, width = 20 },
            { name = "r", side = "RIGHT", order = 1, width = 20 },
        }, OPTIONS)

        assertEqual(10, positions.l.offset)
        assertNear(0, positions.c.offset)
        assertEqual(-10, positions.r.offset)
    end)
end)
