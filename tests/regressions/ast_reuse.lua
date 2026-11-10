return function(Rima)
    local ast = Rima.parse([[
local value = ...
return function(delta)
    value = value + delta
    return value, label
end
]], "@ast-reuse")

    local firstEnv = { label = "first" }
    local first = Rima.execute(ast, firstEnv, 10)
    local second = Rima.execute(ast, { label = "second" }, 20)
    assert(first ~= second, "reusing an AST must create separate closures")

    local value, label = first(1)
    assert(value == 11 and label == "first", "first execution must use its own state")
    value, label = second(2)
    assert(value == 22 and label == "second", "second execution must use its own state")

    firstEnv.label = "updated"
    value, label = first(3)
    assert(value == 14 and label == "updated", "the closure must retain its state and live environment")

    assert(Rima.run("remembered = 1; return remembered") == 1, "default environment must accept writes")

    local remembered, globals, hostType = Rima.run("return remembered, _G, type")
    assert(remembered == nil, "each run must receive a fresh default environment")
    assert(globals == nil and hostType == nil, "the default environment must not expose host globals")
end
