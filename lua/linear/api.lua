local M = {}

M.endpoint = "https://api.linear.app/graphql"

---@param body string
---@return string|nil err, table|nil data
function M.parse_response(body)
  if body == nil or body == "" then
    return "empty response from Linear", nil
  end
  local ok, decoded = pcall(vim.json.decode, body, { luanil = { object = true, array = true } })
  if not ok or type(decoded) ~= "table" then
    return "unexpected response from Linear", nil
  end
  if decoded.errors and #decoded.errors > 0 then
    local first = decoded.errors[1]
    local code = first.extensions and first.extensions.code
    if code == "RATELIMITED" then
      return "rate limited by Linear, retry in a minute", nil
    end
    if code == "AUTHENTICATION_ERROR" then
      return "authentication failed, run :Linear login", nil
    end
    return first.message or "unknown GraphQL error", nil
  end
  return nil, decoded.data
end

---@param query string
---@param variables table
---@param cb fun(err: string|nil, data: table|nil)
---@param opts? { key?: string }
function M.request(query, variables, cb, opts)
  local demo = require("linear.demo")
  if demo.enabled then
    demo.request(query, variables, cb)
    return
  end
  local key = opts and opts.key or require("linear.auth").get_key()
  if not key then
    vim.schedule(function()
      cb("not logged in, run :Linear login", nil)
    end)
    return
  end
  local body = vim.json.encode({ query = query, variables = next(variables) and variables or vim.empty_dict() })
  -- headers go through stdin so the key never shows up in the process list
  vim.system({
    "curl",
    "--silent",
    "--show-error",
    "--max-time",
    "20",
    "-H",
    "@-",
    "-H",
    "Content-Type: application/json",
    "--data-binary",
    body,
    M.endpoint,
  }, { text = true, stdin = "Authorization: " .. key .. "\n" }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        cb("network error: " .. vim.trim(res.stderr or ""), nil)
        return
      end
      cb(M.parse_response(res.stdout))
    end)
  end)
end

return M
