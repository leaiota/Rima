# Rima

简体中文: [README_zh.md](README_zh.md).

Rima is an embeddable AST interpreter for the core Lua 5.1 language, written in pure Lua 5.1. The runtime consists of a single `rima.lua` file with no third-party dependencies. It interprets source directly without calling host dynamic compilation APIs such as `load` or `loadstring`.

Rima supports core Lua 5.1 syntax, closures, multiple return values, tables, metamethods, host interoperability, and coroutines. It can run embedded rules, configurations, or scripts. The host exposes capabilities to scripts through an environment table.

## Quick start

Place `rima.lua` on the PUC Lua 5.1.5 module search path.

```lua
local Rima = require("rima")

local result = Rima.run([[
    local function hypotenuse(a, b)
        return math.sqrt(a * a + b * b)
    end
    return hypotenuse(...)
]], nil, {
    math = math,
}, 3, 4)

assert(result == 5)
```

Script reads and writes of globals go through `env` and follow its metamethods. Executions share globals when given the same `env`. Passing `nil` creates a new empty table for that execution. To give scripts access to standard library globals such as `string`, `coroutine`, or `io`, the host must supply those names through `env`. Lua values retain their native host behavior. For example, in the default environment, reading `string` yields `nil` while `("abc"):upper()` yields `"ABC"` through the host's string metatable.

Tables, functions, userdata, and threads retain their native types and reference identity when passed between scripts and the host. Multiple return values preserve intermediate and trailing `nil` values. The host can use script functions as callbacks.

## Parse once, execute multiple times

Use `parse` to obtain an AST, then pass it to `execute` with different environments or arguments.

```lua
local Rima = require("rima")
local ast = Rima.parse([[
    local total = ...
    return function(amount)
        total = total + amount
        return total * multiplier
    end
]], "@counter")

local first = Rima.execute(ast, { multiplier = 2 }, 3)
local second = Rima.execute(ast, { multiplier = 4 }, 9)

assert(first(1) == 8)
assert(second(1) == 40)
assert(first(1) == 10)
```

Each call to `execute` uses its own local variables. Returned closures retain the variables and environment reference captured during that execution. ASTs can be reused within the same Rima version. Manually constructed or modified ASTs, and ASTs restored from storage, may fail to execute correctly.

## Handling errors

The public API raises errors on failure. The host can wrap parsing or execution in `pcall`. Error objects raised by host functions propagate as-is.

```lua
local Rima = require("rima")
local failure = { message = "host operation failed" }
local ok, result = pcall(Rima.run, "hostFail()", "@example", {
    hostFail = function()
        error(failure, 0)
    end,
})

assert(not ok)
assert(result == failure)
```

Parse errors include the chunk name, line number, and column number. Runtime errors may carry non-string values or omit the script stack trace. To use `pcall` or `error` within a script, the host must supply them through `env`.

## Public API

| API | Description |
| --- | --- |
| `Rima.parse(source, chunkName)` | Parses source and returns a reusable AST |
| `Rima.execute(ast, env, ...)` | Executes an AST in the given environment |
| `Rima.run(source, chunkName, env, ...)` | Parses and immediately executes source |

When `chunkName` is `nil`, both `parse` and `run` use `"@rima"`. Both `run` and `execute` return the script's Lua return values. All arguments after `env` become the script's variadic arguments, including `nil` and tables.

`source` must be a string. `chunkName` must be a string or `nil`. `env` must be a table or `nil`.

## Host API

The environment that loads `rima.lua` must provide the following APIs. The `env` passed to `Rima.run` or `Rima.execute` supplies the globals that a script can access.

| Category | Required APIs |
| --- | --- |
| Basic functions | `error`, `select`, `setmetatable`, `tonumber`, `tostring`, `type`, `unpack` |
| string | `string.char`, `string.find`, `string.format`, `string.len`, `string.lower`, `string.sub` |
| table | `table.concat`, `table.insert` |
| math | `math.max`, `math.min` |

If the host lacks any of these APIs, provide equivalent functions in the environment that loads `rima.lua`.

## Compatibility and limitations

PUC Lua 5.1.5 is the only host with guaranteed compatibility. Rima rejects syntax introduced in Lua 5.2 and later, including `goto`, `//`, bitwise operators, and hexadecimal floating-point literals. Shebang lines and the implicit `arg` local from `LUA_COMPAT_VARARG` are unsupported.

The parser enforces these fixed limits.

| Resource | Limit | Scope |
| --- | --- | --- |
| Source size | 8 MiB | Per parse, measured in bytes |
| Active locals | 200 | Per function, including hidden loop control variables |
| Upvalues | 60 | Per function |
| Syntax depth | 200 | Per parse |

Rima's environment tables provide only limited isolation. With no execution budget, an infinite loop can run indefinitely. Script recursion is subject to the host call stack limit, and deep tail calls may consume stack space.

Arithmetic, indexing, assignment, calls, and metamethods follow the host's Lua 5.1 behavior. Numeric literals use `.` as the decimal separator. Runtime string-to-number conversion and character classification follow the host's current locale. Coroutines can yield and resume through ordinary call chains within Lua 5.1's yield boundaries.

Rima evaluates table constructor fields in source order and writes each one immediately. For example, the first element of `{ 10, [1] = 20 }` is `20` in Rima, which differs from PUC Lua 5.1.5. For tables with holes, `#` returns a boundary permitted by Lua 5.1. This boundary may differ from the one PUC Lua returns.

The behavior of `debug`, `getfenv`, `setfenv`, and `string.dump` on script functions may differ from their behavior on native Lua functions.

## Testing and development

From the repository root, run `luac -p rima.lua` to check the runtime syntax, then run `lua tests/run.lua` for the default test suite. The suite covers expected language behavior, differential tests, and bug regressions.

The suite runs scripts in `tests/programs/` in both native Lua and Rima and compares their return values. Each regression case lives in its own file in `tests/regressions/` and returns a test function that takes `Rima` and `compareProgram`. Register new tests by adding a line to the list at the top of `tests/run.lua`.

From the repository root, run `lua benchmarks/run.lua` to compare execution times for native Lua and Rima. Benchmark workloads live in `benchmarks/programs/` and are registered in the list at the top of `benchmarks/run.lua`.

## License

Copyright (C) 2026 Ex

Rima, including the runtime, tests, and documentation, is licensed under the [Mozilla Public License 2.0](LICENSE).
