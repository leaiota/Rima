local count = ...

local thread = coroutine.create(function()
    for i = 1, count do
        coroutine.yield(i)
    end
end)

local total = 0
while coroutine.status(thread) ~= "dead" do
    local ok, value = coroutine.resume(thread)
    if not ok then
        error(value)
    end

    total = total + (value or 0)
end

return total
