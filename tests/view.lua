-- Run with: nvim --headless --clean -l tests/view.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.cmd("runtime plugin/linear.lua")
require("linear").setup({})

local function check(cond, msg)
  if not cond then
    print("FAIL " .. msg)
    os.exit(1)
  end
  print("ok   " .. msg)
end

check(vim.fn.exists(":Linear") == 2, ":Linear command exists")
check(vim.fn.maparg("<leader>ii", "n") ~= "", "<leader>ii mapped")

local cache = require("linear.cache")
local function fake(id, extra)
  return vim.tbl_extend("force", {
    identifier = id,
    title = "T " .. id,
    url = "https://linear.app/x/issue/" .. id,
    state = { name = "Todo", type = "unstarted" },
  }, extra or {})
end
cache.set("ENG-1", fake("ENG-1", {
  parent = fake("ENG-0"),
  relations = { nodes = { { type = "blocks", relatedIssue = fake("ENG-2") } } },
}))
cache.set("ENG-0", fake("ENG-0"))
cache.set("ENG-2", fake("ENG-2"))

local view = require("linear.view")
view.open("ENG-1")
check(vim.b.linear_issue == "ENG-1" and vim.bo.filetype == "markdown", "issue buffer opened")
check(vim.api.nvim_buf_get_name(0):find("linear://ENG%-1") ~= nil, "buffer named linear://ENG-1")

vim.cmd("normal gp")
check(vim.b.linear_issue == "ENG-0", "gp opens the parent")

vim.cmd("execute \"normal \\<BS>\"")
check(vim.b.linear_issue == "ENG-1", "<BS> goes back")

vim.fn.search("^- ENG-2")
vim.cmd("execute \"normal \\<CR>\"")
check(vim.b.linear_issue == "ENG-2", "<CR> follows a blocks link")
check(not vim.bo.modifiable, "buffer is read-only")

vim.cmd("qa!")
