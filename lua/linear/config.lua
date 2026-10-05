local M = {}

---@class linear.Config
---@field prefix string|false Leader prefix for global keymaps, false to disable them
---@field cache_ttl integer Seconds an issue detail stays cached
---@field include_completed boolean Show completed/canceled issues in the picker
---@field max_issues integer Max assigned issues fetched
---@field demo boolean Start in demo mode (fictional data, no API calls)
---@field pin_branch_issue boolean Pin the current git branch's issue at the top of the issue pickers
---@field text_width integer|false Wrap descriptions and comments at this column, false to keep Linear's lines
---@field attachments { enabled: boolean, max_size_mb: integer } Download images embedded in issues
---@field breadcrumb boolean Show the trail of visited issues in the winbar
M.defaults = {
  demo = false,
  breadcrumb = true,
  pin_branch_issue = true,
  prefix = "<leader>i",
  cache_ttl = 60,
  include_completed = false,
  max_issues = 100,
  text_width = 80,
  attachments = {
    enabled = true,
    max_size_mb = 50,
  },
}

---@type linear.Config
M.options = vim.deepcopy(M.defaults)

---@param opts? table
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
