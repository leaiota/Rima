-- Compares execution time for identical source between native and Rima.
-- Usage: lua benchmarks/run.lua [--iterations=N] [--rounds=N]

local WORKLOADS = {
    {
        name = "Arithmetic",
        scale = 1,
        path = "benchmarks/programs/arithmetic.lua",
    },
    {
        name = "Branches",
        scale = 1,
        path = "benchmarks/programs/branches.lua",
    },
    {
        name = "Function calls",
        scale = 1,
        path = "benchmarks/programs/function_calls.lua",
    },
    {
        name = "Closures",
        scale = 1,
        path = "benchmarks/programs/closures.lua",
    },
    {
        name = "Arrays build/read",
        scale = 0.5,
        path = "benchmarks/programs/array_build_read.lua",
    },
    {
        name = "Numeric hash access",
        scale = 0.2,
        path = "benchmarks/programs/numeric_hash_access.lua",
    },
    {
        name = "String method calls",
        scale = 1,
        path = "benchmarks/programs/string_method_calls.lua",
    },
    {
        name = "Table concat",
        scale = 0.1,
        path = "benchmarks/programs/table_concat.lua",
    },
    {
        name = "Metatable access",
        scale = 0.5,
        path = "benchmarks/programs/metatable_access.lua",
    },
    {
        name = "Varargs/multi-return",
        scale = 0.5,
        path = "benchmarks/programs/varargs_multi_return.lua",
    },
    {
        name = "Table iteration",
        scale = 1,
        path = "benchmarks/programs/table_iteration.lua",
    },
    {
        name = "Coroutines",
        scale = 0.02,
        path = "benchmarks/programs/coroutines.lua",
    },
}

local DEFAULT_ITERATIONS = 5000
local DEFAULT_ROUNDS = 5
local MIN_CALIBRATION_SECONDS = 0.01
local MAX_RIMA_SECONDS_PER_ROUND = 0.5
local MAX_NATIVE_BATCH_SIZE = 262144
local MAX_RIMA_BATCH_SIZE = 1024
local PREPARE_BATCH_SIZE = 100

local function usage()
    print("Usage: lua5.1 benchmarks/run.lua [--iterations=N] [--rounds=N]")
    print("")
    print("Options:")
    print("  --help          Show this help")
    print("  --iterations=N  Base loop iterations per execution (default: 5000)")
    print("  --rounds=N      Measured rounds per workload (default: 5)")
end

local function parseInteger(option, value, minimum)
    local number = tonumber(value)
    if not number or number % 1 ~= 0 or number < minimum then
        error(string.format("%s must be an integer greater than or equal to %d", option, minimum), 0)
    end
    return number
end

local function parseArguments(arguments)
    local options = {
        iterations = DEFAULT_ITERATIONS,
        rounds = DEFAULT_ROUNDS,
    }

    for _, value in ipairs(arguments) do
        local iterations = value:match("^%-%-iterations=(.*)$")
        local rounds = value:match("^%-%-rounds=(.*)$")

        if iterations then
            options.iterations = parseInteger("--iterations", iterations, 1)

        elseif rounds then
            options.rounds = parseInteger("--rounds", rounds, 1)

        elseif value == "--help" then
            options.help = true
        else
            error("Unknown option: " .. value, 0)
        end
    end

    return options
end

local function newEnvironment()
    return {
        setmetatable = setmetatable,
        error = error,
        tostring = tostring,
        pairs = pairs,
        select = select,
        table = table,
        math = math,
        coroutine = coroutine,
    }
end

local function compileNative(source, chunkName)
    local env = newEnvironment()
    local chunk
    local started = os.clock()

    for index = 1, PREPARE_BATCH_SIZE do
        local message
        chunk, message = loadstring(source, chunkName)
        if not chunk then
            error(message, 0)
        end
    end

    local elapsed = (os.clock() - started) / PREPARE_BATCH_SIZE
    setfenv(chunk, env)

    return chunk, elapsed
end

local function parseRima(Rima, source, chunkName)
    local env = newEnvironment()
    local ast
    local started = os.clock()

    for index = 1, PREPARE_BATCH_SIZE do
        ast = Rima.parse(source, chunkName)
    end

    local elapsed = (os.clock() - started) / PREPARE_BATCH_SIZE

    return function(...)
        return Rima.execute(ast, env, ...)
    end, elapsed
end

local function measure(worker, iterations, batchSize)
    collectgarbage("collect")

    local result
    local started = os.clock()

    for index = 1, batchSize do
        result = worker(iterations)
    end

    return (os.clock() - started) / batchSize, result
end

local function sampleExecutionTime(worker, iterations, maxBatchSize)
    local batchSize = 1

    while true do
        local seconds = measure(worker, iterations, batchSize)

        if seconds * batchSize >= MIN_CALIBRATION_SECONDS or batchSize >= maxBatchSize then
            return math.max(seconds, 0.000000001), batchSize
        end

        batchSize = math.min(batchSize * 2, maxBatchSize)
    end
end

local function calibrate(nativeWorker, rimaWorker, iterations)
    local _, nativeBatch = sampleExecutionTime(nativeWorker, iterations, MAX_NATIVE_BATCH_SIZE)
    local rimaSeconds = sampleExecutionTime(rimaWorker, iterations, MAX_RIMA_BATCH_SIZE)

    local rimaBatch = math.floor(MAX_RIMA_SECONDS_PER_ROUND / rimaSeconds)
    return nativeBatch, math.max(1, math.min(rimaBatch, MAX_RIMA_BATCH_SIZE))
end

local function medianExecutionTime(values)
    table.sort(values)

    local middle = math.floor(#values / 2)
    local seconds = values[middle + 1]

    if #values % 2 == 0 then
        seconds = (values[middle] + seconds) / 2
    end

    if seconds > 0 then
        return seconds
    end
end

local function assertSameResult(name, expected, actual)
    if expected ~= actual then
        error(string.format(
            "%s produced different results: native=%s, rima=%s",
            name, tostring(expected), tostring(actual)
        ), 0)
    end
end

local function benchmarkWorkload(Rima, workload, options)
    local iterations = math.max(1, math.floor(options.iterations * workload.scale))
    local file = assert(io.open(workload.path, "rb"))
    local source, message = file:read("*a")
    assert(file:close())
    assert(source, message)

    local chunkName = "@" .. workload.path
    local nativeWorker, nativeCompileSeconds = compileNative(source, chunkName)
    local rimaWorker, rimaParseSeconds = parseRima(Rima, source, chunkName)

    local expected = nativeWorker(iterations)
    assertSameResult(workload.name, expected, rimaWorker(iterations))

    local warmupIterations = math.min(iterations, 1000)
    nativeWorker(warmupIterations)
    rimaWorker(warmupIterations)

    local nativeBatch, rimaBatch = calibrate(nativeWorker, rimaWorker, iterations)
    local nativeTimes = {}
    local rimaTimes = {}

    for round = 1, options.rounds do
        local nativeSeconds, nativeResult
        local rimaSeconds, rimaResult

        if round % 2 == 1 then
            nativeSeconds, nativeResult = measure(nativeWorker, iterations, nativeBatch)
            rimaSeconds, rimaResult = measure(rimaWorker, iterations, rimaBatch)
        else
            rimaSeconds, rimaResult = measure(rimaWorker, iterations, rimaBatch)
            nativeSeconds, nativeResult = measure(nativeWorker, iterations, nativeBatch)
        end

        assertSameResult(workload.name, expected, nativeResult)
        assertSameResult(workload.name, expected, rimaResult)

        nativeTimes[#nativeTimes + 1] = nativeSeconds
        rimaTimes[#rimaTimes + 1] = rimaSeconds
    end

    return {
        name = workload.name,
        iterations = iterations,
        nativeBatch = nativeBatch,
        rimaBatch = rimaBatch,
        nativeSeconds = medianExecutionTime(nativeTimes),
        rimaSeconds = medianExecutionTime(rimaTimes),
        nativeCompileSeconds = nativeCompileSeconds,
        rimaParseSeconds = rimaParseSeconds,
        result = expected,
    }
end

local function formatMilliseconds(seconds)
    if not seconds then
        return "N/A"
    end
    return string.format("%.3f", seconds * 1000)
end

local function formatSlowdown(nativeSeconds, rimaSeconds)
    if nativeSeconds and rimaSeconds then
        return string.format("%.2fx", rimaSeconds / nativeSeconds)
    end
    return "N/A"
end

local function addExecutionTime(total, seconds)
    if total and seconds then
        return total + seconds
    end
end

local function main(arguments)
    local options = parseArguments(arguments)
    if options.help then
        usage()
        return
    end

    assert(
        _VERSION == "Lua 5.1" and jit == nil,
        "use PUC Lua 5.1.5 for benchmarking"
    )

    local Rima = dofile("rima.lua")

    local labelFormat = "%-22s %12s  %14s  %12s  %11s %10s %11s"
    local rowFormat = "%-22s %12d  %14d  %12d  %11s %10s %11s"
    local header = string.format(
        labelFormat,
        "Workload",
        "Iterations",
        "Native batch",
        "Rima batch",
        "Native ms",
        "Rima ms",
        "Slowdown"
    )
    local separator = string.rep("-", #header)

    print(string.format(
        "Rima benchmark (lua=%s, iterations=%d, rounds=%d)",
        _VERSION, options.iterations, options.rounds
    ))
    print(separator)
    print(header)

    local totalNativeSeconds = 0
    local totalRimaSeconds = 0
    local totalNativeCompileSeconds = 0
    local totalRimaParseSeconds = 0
    local checksum = 0

    for _, workload in ipairs(WORKLOADS) do
        local result = benchmarkWorkload(Rima, workload, options)

        totalNativeSeconds = addExecutionTime(totalNativeSeconds, result.nativeSeconds)
        totalRimaSeconds = addExecutionTime(totalRimaSeconds, result.rimaSeconds)

        totalNativeCompileSeconds = totalNativeCompileSeconds + result.nativeCompileSeconds
        totalRimaParseSeconds = totalRimaParseSeconds + result.rimaParseSeconds

        checksum = (checksum + result.result) % 1000000007

        print(string.format(
            rowFormat,
            result.name,
            result.iterations,
            result.nativeBatch,
            result.rimaBatch,
            formatMilliseconds(result.nativeSeconds),
            formatMilliseconds(result.rimaSeconds),
            formatSlowdown(result.nativeSeconds, result.rimaSeconds)
        ))
    end

    print(separator)
    print(string.format(
        labelFormat,
        "Combined",
        "-",
        "-",
        "-",
        formatMilliseconds(totalNativeSeconds),
        formatMilliseconds(totalRimaSeconds),
        formatSlowdown(totalNativeSeconds, totalRimaSeconds)
    ))

    print("")
    print(string.format(
        "Preparation totals: native compile %s ms, Rima parse %s ms",
        formatMilliseconds(totalNativeCompileSeconds),
        formatMilliseconds(totalRimaParseSeconds)
    ))

    print("Checksum: " .. checksum)
end

main(arg or {})
