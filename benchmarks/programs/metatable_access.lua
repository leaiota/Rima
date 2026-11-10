local count = ...

local storage = { value = 0 }
local proxy = setmetatable({}, {
    __index = storage,
    __newindex = storage,
})

for i = 1, count do
    proxy.value = proxy.value + i % 7
end

return proxy.value
