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
cache.set(
  "ENG-1",
  fake("ENG-1", {
    parent = fake("ENG-0"),
    relations = { nodes = { { type = "blocks", relatedIssue = fake("ENG-2") } } },
  })
)
cache.set("ENG-0", fake("ENG-0"))
cache.set("ENG-2", fake("ENG-2"))

local view = require("linear.view")
view.open("ENG-1")
check(vim.b.linear_issue == "ENG-1" and vim.bo.filetype == "markdown", "issue buffer opened")
check(vim.api.nvim_buf_get_name(0):find("linear://ENG%-1") ~= nil, "buffer named linear://ENG-1")

vim.cmd("normal gp")
check(vim.b.linear_issue == "ENG-0", "gp opens the parent")

vim.cmd('execute "normal \\<BS>"')
check(vim.b.linear_issue == "ENG-1", "<BS> goes back")

vim.fn.search("^- ENG-2")
vim.cmd('execute "normal \\<CR>"')
check(vim.b.linear_issue == "ENG-2", "<CR> follows a blocks link")
check(not vim.bo.modifiable, "buffer is read-only")
check(#vim.api.nvim_tabpage_list_wins(0) == 1, "from a blank window, the issue opens in place")

local function wins()
  return #vim.api.nvim_tabpage_list_wins(0)
end

view.open("ENG-1")
check(view.breadcrumb(0) == "ENG-1", "opening an issue in place starts a new trail")
check(vim.wo.winbar:find("linear") ~= nil, "breadcrumb shown in the winbar")
vim.cmd("normal gp")
check(view.breadcrumb(0) == "ENG-1 › ENG-0  ·  1 hop", "following a link extends the trail")
check(wins() == 1, "following a link stays in the same window")
vim.cmd('execute "normal \\<BS>"')
check(view.breadcrumb(0) == "ENG-1", "<BS> shortens the trail")

vim.cmd("enew")
local file = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(file, "notes.txt")
vim.api.nvim_buf_set_lines(file, 0, -1, false, { "hello" })
check(vim.wo.winbar == "", "no breadcrumb on a file buffer")

view.open("ENG-0")
check(wins() == 2 and vim.fn.winlayout()[1] == "row", "from a file, the issue opens in a vertical split")
check(vim.b.linear_issue == "ENG-0", "the split shows the issue")
check(#vim.fn.win_findbuf(file) == 1, "the file stays visible")

vim.cmd("wincmd p")
view.open("ENG-0")
check(wins() == 2 and vim.b.linear_issue == "ENG-0", "an issue already shown is focused, not duplicated")

vim.cmd("only")
vim.api.nvim_set_current_buf(file)
check(vim.wo.winbar == "", "breadcrumb cleared when the window shows a file again")

vim.cmd("Linear open ENG-2")
check(wins() == 2 and vim.fn.winlayout()[1] == "row", ":Linear open from a file opens a vertical split")

vim.cmd("qa!")
