# Rima

Rima 是一个用纯 Lua 5.1 编写、面向嵌入场景的 Lua 5.1 核心语言 AST 解释器。运行时只有一个 `rima.lua` 文件，无第三方依赖，不使用 `load`、`loadstring` 等宿主动态编译接口执行源码。

它支持 Lua 5.1 核心语法、闭包、多返回值、table、元方法、宿主互操作和 coroutine，适合嵌入规则、配置或脚本。宿主通过环境表提供脚本可访问的能力。

## 快速开始

将 `rima.lua` 放在 PUC Lua 5.1.5 的模块搜索路径中：

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

脚本的全局读写只作用于 `env`，并遵循它的元方法。传入同一个 `env` 的执行共享全局变量；`env` 为 `nil` 时会使用新的空 table。脚本通过 `string`、`coroutine`、`io` 等全局名访问标准库时，宿主需通过 `env` 提供这些名称。Lua 值仍遵循宿主的原生行为。例如，使用默认环境时，读取 `string` 得到 `nil`，`("abc"):upper()` 则通过宿主的字符串元表得到 `"ABC"`。

跨边界传递的 table、function、userdata 和 thread 保持原生类型与引用身份，多返回值保留中间和末尾的 `nil`。脚本函数可以作为宿主回调使用。

## 解析一次，多次执行

用 `parse` 得到 AST，再用 `execute` 传入不同环境或参数：

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

每次 `execute` 使用独立的局部变量，返回的闭包保留本次捕获的变量和环境引用。AST 只供当前版本复用，不保证手工构造、修改或持久化恢复后仍可正确执行。

## 捕获错误

公开 API 通过抛出错误报告失败。宿主可以用 `pcall` 包住解析或执行；宿主函数抛出的错误对象原样传播：

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

源码解析错误包含 chunk 名、行号和列号。运行错误不一定是字符串，也不保证附带脚本调用栈。脚本内部需要 `pcall` 或 `error` 时，须通过 `env` 注入。

## 公开 API

| API | 作用 |
| --- | --- |
| `Rima.parse(source, chunkName)` | 解析源码，返回可复用的 AST |
| `Rima.execute(ast, env, ...)` | 在指定的环境中执行 AST |
| `Rima.run(source, chunkName, env, ...)` | 解析并立即执行源码 |

`parse` 和 `run` 的 `chunkName` 为 `nil` 时均使用 `"@rima"`。`run` 和 `execute` 返回脚本产生的 Lua 多返回值。`env` 后的所有参数都是脚本的可变参数，包括 `nil` 和 table。

`source` 必须是字符串，`chunkName` 必须是字符串或 `nil`，`env` 必须是 table 或 `nil`。

## 宿主 API

装载 `rima.lua` 的环境需要提供以下 API。传给 `Rima.run` 或 `Rima.execute` 的 `env` 用于提供脚本可访问的全局变量。

| 类别 | 依赖的 API |
| --- | --- |
| 基础函数 | `error`、`select`、`setmetatable`、`tonumber`、`tostring`、`type`、`unpack` |
| string | `string.char`、`string.find`、`string.format`、`string.len`、`string.lower`、`string.sub` |
| table | `table.concat`、`table.insert` |
| math | `math.max`、`math.min` |

如果宿主缺少某项 API，请自行实现等价函数，并在装载 `rima.lua` 的环境中提供。

## 兼容性与限制

目前仅保证兼容 PUC Lua 5.1.5。Rima 不接受 `goto`、`//`、位运算符、十六进制浮点数等 Lua 5.2 及以上语法，不处理 shebang，也不提供 `LUA_COMPAT_VARARG` 的隐式 `arg` local。

解析阶段的固定上限：

| 资源 | 上限 | 计数范围 |
| --- | --- | --- |
| 源码大小 | 8 MiB | 单次解析，按字节 |
| 活跃 local | 200 | 每个函数，包含循环隐藏控制变量 |
| upvalue | 60 | 每个函数 |
| 语法深度 | 200 | 单次解析 |

Rima 不是完整安全沙箱，没有执行预算，不能保证终止无限循环。脚本递归受宿主调用栈限制，不保证深度尾调用优化。

算术、索引、赋值、调用和元方法使用宿主 Lua 5.1 行为。数字字面量使用 `.` 作为小数点；运行时字符串转数字与字符分类遵循宿主当前 locale。coroutine 可在普通调用链中挂起和恢复，仍受 Lua 5.1 的 yield 边界限制。

table 按源码字段顺序求值并立即写入。例如 `{ 10, [1] = 20 }` 的第一个元素为 `20`，与 PUC Lua 5.1.5 的结果不同。带空洞 table 的 `#` 返回 Lua 5.1 允许的合法边界，不保证与 PUC Lua 的结果相同。

`debug`、`getfenv`、`setfenv` 和 `string.dump` 对脚本函数的反射结果不保证等同于原生 Lua 函数。

## 测试与开发

在仓库根目录运行 `luac -p rima.lua` 检查运行时语法，再运行 `lua tests/run.lua` 执行默认测试，覆盖固定语义、差分和缺陷回归。

`tests/programs/` 中的脚本由原生 Lua 和 Rima 分别执行并比较返回值。回归用例各自放在 `tests/regressions/`，每个文件返回一个接收 `Rima` 和 `compareProgram` 的测试函数。新增测试时，在 `tests/run.lua` 开头的清单里加一行登记即可。

在仓库根目录运行 `lua benchmarks/run.lua` 比较原生 Lua 与 Rima 的执行耗时。负载源码放在 `benchmarks/programs/`，由基准入口顶部的清单登记。

## 许可证

Copyright (C) 2026 Ex

Rima（包括运行时、测试和文档）依据 [Mozilla Public License 2.0](LICENSE) 授权。
