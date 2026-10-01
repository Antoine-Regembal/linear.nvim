local M = {}

local store = {}

---@param key string
---@return any
function M.get(key)
  local entry = store[key]
  if entry and os.time() - entry.at < require("linear.config").options.cache_ttl then
    return entry.value
  end
  store[key] = nil
end

---@param key string
---@param value any
function M.set(key, value)
  store[key] = { value = value, at = os.time() }
end

function M.clear()
  store = {}
end

return M
