-- Tiny spec runner. Usage, from the repo root:
--   lua tests/runner.lua tests/money_spec.lua tests/clock_spec.lua ...

package.path = "./tests/?.lua;" .. package.path

local passed, failed = 0, 0
local failures = {}
local stack = {}

function describe(name, fn)
    stack[#stack + 1] = name
    fn()
    stack[#stack] = nil
end

function it(name, fn)
    stack[#stack + 1] = name
    local label = table.concat(stack, " > ")
    local ok, err = pcall(fn)
    stack[#stack] = nil

    if ok then
        passed = passed + 1
        print("  ok    " .. label)
    else
        failed = failed + 1
        failures[#failures + 1] = string.format("%s\n        %s", label, tostring(err))
        print("  FAIL  " .. label)
    end
end

local function fail(message)
    error(message, 3)
end

function assertEqual(expected, actual, message)
    if expected ~= actual then
        fail(string.format(
            "%sexpected [%s], got [%s]",
            message and (message .. ": ") or "",
            tostring(expected),
            tostring(actual)
        ))
    end
end

function assertTrue(value, message)
    if not value then
        fail(message or "expected a truthy value")
    end
end

function assertFalse(value, message)
    if value then
        fail(message or string.format("expected a falsy value, got [%s]", tostring(value)))
    end
end

function assertNil(value, message)
    if value ~= nil then
        fail(message or string.format("expected nil, got [%s]", tostring(value)))
    end
end

function assertNear(expected, actual, tolerance, message)
    tolerance = tolerance or 0.001
    if type(actual) ~= "number" or math.abs(expected - actual) > tolerance then
        fail(string.format(
            "%sexpected [%s] +/- %s, got [%s]",
            message and (message .. ": ") or "",
            tostring(expected),
            tostring(tolerance),
            tostring(actual)
        ))
    end
end

function assertMatch(pattern, actual, message)
    if not tostring(actual):find(pattern) then
        fail(string.format(
            "%sexpected [%s] to match [%s]",
            message and (message .. ": ") or "",
            tostring(actual),
            tostring(pattern)
        ))
    end
end

function assertErrors(fn, message)
    if pcall(fn) then
        fail(message or "expected an error, but the call succeeded")
    end
end

local specs = { ... }
if #specs == 0 then
    io.stderr:write("no spec files given\n")
    os.exit(2)
end

for _, path in ipairs(specs) do
    print(path)
    local chunk, err = loadfile(path)
    if not chunk then
        failed = failed + 1
        failures[#failures + 1] = string.format("%s\n        %s", path, tostring(err))
        print("  FAIL  could not load spec")
    else
        local ok, runErr = pcall(chunk)
        if not ok then
            failed = failed + 1
            failures[#failures + 1] = string.format("%s\n        %s", path, tostring(runErr))
            print("  FAIL  spec raised while loading")
        end
    end
end

print("")
if #failures > 0 then
    print("Failures:")
    for _, failure in ipairs(failures) do
        print("  " .. failure)
    end
    print("")
end

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
