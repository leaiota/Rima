-- Runs Rima's test suite.
-- Usage: lua tests/run.lua

local PROGRAMS = {
    "tests/programs/closures.lua",
    "tests/programs/control_flow.lua",
    "tests/programs/coroutines.lua",
    "tests/programs/metatables.lua",
    "tests/programs/multiple_returns.lua",
    "tests/programs/tables.lua",
}

local REGRESSIONS = {
    "tests/regressions/ast_reuse.lua",
    "tests/regressions/parse_location.lua",
    "tests/regressions/table_field_call_newline.lua",
    "tests/regressions/assignment_order.lua",
    "tests/regressions/host_values.lua",
    "tests/regressions/active_function_lifetime.lua",
    "tests/regressions/unused_call_arguments.lua",
    "tests/regressions/method_receiver_lifetime.lua",
    "tests/regressions/callable_target_lifetime.lua",
    "tests/regressions/assignment_result_lifetime.lua",
}

local function packValues(...)
    return { n = select("#", ...), ... }
end

local function newEnvironment()
    return {
        assert = assert,
        boundary = function(value)
            local length = #value
            return (length == 0 and value[1] == nil) or (length > 0 and value[length] ~= nil and value[length + 1] == nil)
        end,
        coroutine = coroutine,
        select = select,
        setmetatable = setmetatable,
    }
end

local function describe(value)
    if type(value) == "number" then
        return string.format("%.17g", value)

    elseif type(value) == "string" then
        return string.format("%q", value)
    end

    return tostring(value)
end

local function compareProgram(Rima, source, path)
    local chunkName = "@" .. path
    local native = assert(loadstring(source, chunkName))
    setfenv(native, newEnvironment())

    local expected = packValues(native())
    local actual = packValues(Rima.run(source, chunkName, newEnvironment()))

    assert(
        actual.n == expected.n,
        string.format("%s returned %d values, expected %d", path, actual.n, expected.n)
    )

    for index = 1, expected.n do
        local received, wanted = actual[index], expected[index]
        local equal = rawequal(received, wanted)

        if type(received) == "number" and type(wanted) == "number" then
            equal = describe(received) == describe(wanted)
        end

        if not equal then
            error(string.format(
                "%s result %d: expected %s (%s), got %s (%s)",
                path, index, describe(wanted), type(wanted), describe(received), type(received)
            ), 0)
        end
    end
end

local function runProgram(path, Rima)
    local file = assert(io.open(path, "rb"))
    local source, message = file:read("*a")
    assert(file:close())
    assert(source, message)

    compareProgram(Rima, source, path)
end

local function runRegression(path, Rima)
    local regression = dofile(path)
    assert(type(regression) == "function", path .. " must return a test function")

    regression(Rima, function(source, name)
        compareProgram(Rima, source, name)
    end)
end

local function runTests(files, run, Rima)
    local passed = 0
    local failed = 0

    for _, path in ipairs(files) do
        io.write(path, " ... ")
        local ok, message = pcall(run, path, Rima)

        if ok then
            passed = passed + 1
            io.write("ok\n")
        else
            failed = failed + 1
            io.write("FAIL\n", tostring(message), "\n")
        end
    end

    return passed, failed
end

local function main()
    assert(
        _VERSION == "Lua 5.1" and jit == nil,
        "please use PUC Lua 5.1.5 for testing"
    )

    local Rima = dofile("rima.lua")

    local programPassed, programFailed = runTests(PROGRAMS, runProgram, Rima)
    local regressionPassed, regressionFailed = runTests(REGRESSIONS, runRegression, Rima)

    local passed = programPassed + regressionPassed
    local failed = programFailed + regressionFailed

    io.write(string.format("\n%d passed, %d failed\n", passed, failed))
    if failed ~= 0 then
        os.exit(1)
    end
end

main()
