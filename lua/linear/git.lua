local M = {}

M.DEMO_BRANCH = "alex/acme-102-dark-mode"

---@return string|nil branch
function M.current_branch()
  if require("linear.demo").enabled then
    return M.DEMO_BRANCH
  end
  local ok, res = pcall(function()
    return vim.system({ "git", "branch", "--show-current" }, { text = true }):wait()
  end)
  if not ok or res.code ~= 0 then
    return nil
  end
  local branch = vim.trim(res.stdout or "")
  return branch ~= "" and branch or nil
end

---@return string|nil id, string|nil branch
function M.branch_issue_id()
  local branch = M.current_branch()
  return require("linear.model").find_id(branch, { loose = true }), branch
end

return M
