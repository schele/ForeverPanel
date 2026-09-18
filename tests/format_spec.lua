local helpers = require("helpers")

local ns = helpers.loadAddon()
local plain = helpers.plain

describe("FormatMoney", function()
    it("always shows all three denominations", function()
        assertEqual("0 0 0", plain(ns.FormatMoney(0, 12)))
    end)

    it("splits copper into gold, silver and copper", function()
        -- 123g 45s 67c
        assertEqual("123 45 67", plain(ns.FormatMoney(1234567, 12)))
    end)

    it("leaves single digits unpadded", function()
        assertEqual("0 0 5", plain(ns.FormatMoney(5, 12)))
        assertEqual("0 5 0", plain(ns.FormatMoney(500, 12)))
        assertEqual("0 1 90", plain(ns.FormatMoney(190, 12)))
    end)

    it("groups thousands in the gold amount", function()
        assertEqual("10,000 0 0", plain(ns.FormatMoney(10000 * 10000, 12)))
    end)

    it("includes the three coin icons at the requested size", function()
        local text = ns.FormatMoney(1, 14)
        assertMatch("UI%-GoldIcon:14:14", text)
        assertMatch("UI%-SilverIcon:14:14", text)
        assertMatch("UI%-CopperIcon:14:14", text)
    end)

    it("treats negative or missing amounts as zero", function()
        assertEqual("0 0 0", plain(ns.FormatMoney(-500, 12)))
        assertEqual("0 0 0", plain(ns.FormatMoney(nil, 12)))
    end)
end)

describe("FormatClock", function()
    it("pads to two digits in 24 hour mode", function()
        assertEqual("09:05", ns.FormatClock(9, 5, true))
        assertEqual("00:00", ns.FormatClock(0, 0, true))
        assertEqual("23:59", ns.FormatClock(23, 59, true))
    end)

    it("uses AM and PM in 12 hour mode", function()
        assertEqual("9:05 AM", ns.FormatClock(9, 5, false))
        assertEqual("1:30 PM", ns.FormatClock(13, 30, false))
    end)

    it("renders midnight and noon as 12", function()
        assertEqual("12:00 AM", ns.FormatClock(0, 0, false))
        assertEqual("12:30 PM", ns.FormatClock(12, 30, false))
    end)

    it("wraps out of range values instead of erroring", function()
        assertEqual("01:00", ns.FormatClock(25, 0, true))
    end)
end)

describe("FormatXP counting down", function()
    it("reports the remaining percentage with two decimals", function()
        assertEqual("50.00% left", ns.FormatXP(500, 1000, true))
        assertEqual("100.00% left", ns.FormatXP(0, 1000, true))
        assertEqual("0.00% left", ns.FormatXP(1000, 1000, true))
    end)

    it("rounds to two decimals", function()
        assertEqual("66.67% left", ns.FormatXP(1000, 3000, true))
    end)

    it("returns nil when there is no XP bar", function()
        assertNil(ns.FormatXP(0, 0, true), "max level should have no text")
        assertNil(ns.FormatXP(500, nil, true))
    end)

    it("clamps overflow instead of going negative", function()
        assertEqual("0.00% left", ns.FormatXP(1500, 1000, true))
    end)
end)

describe("FormatXP counting up", function()
    it("reports the earned percentage with two decimals", function()
        assertEqual("50.00% XP", ns.FormatXP(500, 1000, false))
        assertEqual("0.00% XP", ns.FormatXP(0, 1000, false))
        assertEqual("100.00% XP", ns.FormatXP(1000, 1000, false))
    end)

    it("rounds to two decimals", function()
        assertEqual("33.33% XP", ns.FormatXP(1000, 3000, false))
    end)

    it("is the complement of counting down", function()
        assertEqual("62.04% XP", ns.FormatXP(6204, 10000, false))
        assertEqual("37.96% left", ns.FormatXP(6204, 10000, true))
    end)

    it("returns nil when there is no XP bar", function()
        assertNil(ns.FormatXP(0, 0, false), "max level should have no text")
    end)

    it("clamps overflow instead of going past 100", function()
        assertEqual("100.00% XP", ns.FormatXP(1500, 1000, false))
    end)

    it("counts up by default", function()
        assertEqual("50.00% XP", ns.FormatXP(500, 1000))
    end)
end)
