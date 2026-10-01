local M = {}

local SERVICE = "linear.nvim"
local ACCOUNT = "api-key"
local KEYS_URL = "https://linear.app/settings/account/security"

local function credentials_path()
  return vim.fs.joinpath(vim.fn.stdpath("data"), "linear.nvim", "credentials.json")
end

---@return "keychain"|"libsecret"|"file"
function M.backend()
  if vim.fn.has("mac") == 1 and vim.fn.executable("security") == 1 then
    return "keychain"
  end
  if vim.fn.executable("secret-tool") == 1 then
    return "libsecret"
  end
  return "file"
end

local function run(cmd, stdin)
  local res = vim.system(cmd, { text = true, stdin = stdin }):wait()
  return res.code == 0, vim.trim(res.stdout or "")
end

local function read_file()
  local fd = io.open(credentials_path(), "r")
  if not fd then
    return nil
  end
  local ok, data = pcall(vim.json.decode, fd:read("*a"))
  fd:close()
  return ok and type(data) == "table" and data.api_key or nil
end

local function write_file(key)
  local path = credentials_path()
  vim.fn.mkdir(vim.fs.dirname(path), "p", tonumber("700", 8))
  local fd = assert(vim.uv.fs_open(path, "w", tonumber("600", 8)))
  vim.uv.fs_write(fd, vim.json.encode({ api_key = key }))
  vim.uv.fs_close(fd)
  vim.uv.fs_chmod(path, tonumber("600", 8))
end

---@return string|nil key, string|nil source
function M.get_key()
  local env = vim.env.LINEAR_API_KEY
  if env and env ~= "" then
    return env, "env"
  end
  local backend = M.backend()
  if backend == "keychain" then
    local ok, out = run({ "security", "find-generic-password", "-s", SERVICE, "-a", ACCOUNT, "-w" })
    if ok and out ~= "" then
      return out, backend
    end
  elseif backend == "libsecret" then
    local ok, out = run({ "secret-tool", "lookup", "service", SERVICE, "account", ACCOUNT })
    if ok and out ~= "" then
      return out, backend
    end
  end
  local key = read_file()
  if key then
    return key, "file"
  end
  return nil, nil
end

---@param key string
---@return boolean ok, string backend
local function store(key)
  local backend = M.backend()
  if backend == "keychain" then
    -- security has no stdin mode for -w; the key is briefly visible in argv
    local ok = run({ "security", "add-generic-password", "-U", "-s", SERVICE, "-a", ACCOUNT, "-w", key })
    if ok then
      return true, backend
    end
  elseif backend == "libsecret" then
    local ok = run({ "secret-tool", "store", "--label=linear.nvim", "service", SERVICE, "account", ACCOUNT }, key)
    if ok then
      return true, backend
    end
  end
  write_file(key)
  return true, "file"
end

function M.delete()
  local backend = M.backend()
  if backend == "keychain" then
    run({ "security", "delete-generic-password", "-s", SERVICE, "-a", ACCOUNT })
  elseif backend == "libsecret" then
    run({ "secret-tool", "clear", "service", SERVICE, "account", ACCOUNT })
  end
  os.remove(credentials_path())
end

function M.login()
  if require("linear.demo").enabled then
    vim.notify("Linear: demo mode is on, run :Linear demo off first", vim.log.levels.WARN)
    return
  end
  local open_page = vim.fn.confirm("Open Linear's API key page in your browser?", "&Yes\n&No", 1)
  if open_page == 1 then
    vim.ui.open(KEYS_URL)
  end
  local key = vim.trim(vim.fn.inputsecret("Linear API key: "))
  if key == "" then
    vim.notify("Linear: login cancelled", vim.log.levels.WARN)
    return
  end
  require("linear.api").request(require("linear.queries").viewer, {}, function(err, data)
    if err then
      vim.notify("Linear: invalid key (" .. err .. ")", vim.log.levels.ERROR)
      return
    end
    local _, backend = store(key)
    vim.notify(("Linear: logged in as %s (stored in %s)"):format(data.viewer.name, backend))
  end, { key = key })
end

function M.logout()
  M.delete()
  local msg = "Linear: logged out"
  if vim.env.LINEAR_API_KEY then
    msg = msg .. " (LINEAR_API_KEY is still set in your environment)"
  end
  vim.notify(msg)
end

function M.whoami()
  require("linear.api").request(require("linear.queries").viewer, {}, function(err, data)
    if err then
      vim.notify("Linear: " .. err, vim.log.levels.ERROR)
      return
    end
    local _, source = M.get_key()
    if require("linear.demo").enabled then
      source = "demo mode, no API call"
    end
    vim.notify(("Linear: %s <%s> (key from %s)"):format(data.viewer.name, data.viewer.email, source))
  end)
end

M._credentials_path = credentials_path

return M
