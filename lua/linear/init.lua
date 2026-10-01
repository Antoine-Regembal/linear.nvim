local config = require("linear.config")

local M = {}

function M.issues()
  require("linear.picker").my_issues()
end

function M.cycle()
  require("linear.picker").my_issues({ active_cycle = true })
end

---@param id? string
function M.open(id)
  local model = require("linear.model")
  if id and id ~= "" then
    require("linear.view").open(id:upper())
    return
  end
  local default = model.find_id(vim.api.nvim_get_current_line()) or ""
  vim.ui.input({ prompt = "Linear issue: ", default = default }, function(input)
    local found = input and model.find_id(input, { loose = true })
    if found then
      require("linear.view").open(found)
    end
  end)
end

function M.branch()
  local id, branch = require("linear.git").branch_issue_id()
  if not id then
    local msg = branch and ("no issue id in branch '" .. branch .. "'") or "not on a git branch"
    vim.notify("Linear: " .. msg, vim.log.levels.WARN)
    return
  end
  require("linear.view").open(id)
end

---@param arg? string "off" to leave demo mode
function M.demo(arg)
  local demo = require("linear.demo")
  if arg == "off" then
    demo.set(false)
    vim.notify("Linear: demo mode off")
    return
  end
  demo.set(true)
  vim.notify("Linear: demo mode on (fictional data, :Linear demo off to leave)")
  M.issues()
end

M.subcommands = {
  demo = M.demo,
  issues = M.issues,
  cycle = M.cycle,
  open = M.open,
  branch = M.branch,
  login = function()
    require("linear.auth").login()
  end,
  logout = function()
    require("linear.auth").logout()
  end,
  whoami = function()
    require("linear.auth").whoami()
  end,
}

M.keys = {
  { "i", M.issues, "My issues" },
  { "c", M.cycle, "Active cycle" },
  { "o", M.open, "Open issue by id" },
  { "b", M.branch, "Issue of current branch" },
  { "l", M.subcommands.login, "Login" },
  { "L", M.subcommands.logout, "Logout" },
}

local function set_keymaps(prefix)
  for _, k in ipairs(M.keys) do
    vim.keymap.set("n", prefix .. k[1], function()
      k[2]()
    end, { desc = "Linear: " .. k[3] })
  end
  local ok, wk = pcall(require, "which-key")
  if ok and wk.add then
    wk.add({ { prefix, group = "linear" } })
  end
end

---@param opts? table
function M.setup(opts)
  config.setup(opts)
  if config.options.demo then
    require("linear.demo").set(true)
  end
  if config.options.prefix then
    set_keymaps(config.options.prefix)
  end
end

return M
