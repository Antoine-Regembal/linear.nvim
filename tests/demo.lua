-- Run with: nvim --headless --clean -l tests/demo.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.env.LINEAR_API_KEY = nil
vim.cmd("runtime plugin/linear.lua")
require("linear").setup({ demo = true })

local demo = require("linear.demo")
local model = require("linear.model")
local queries = require("linear.queries")

local function check(cond, msg)
  if not cond then
    print("FAIL " .. msg)
    os.exit(1)
  end
  print("ok   " .. msg)
end

local _, data = demo.respond(queries.my_issues, { filter = { state = { type = { nin = { "completed", "canceled" } } } } })
local issues = model.sort_issues(data.viewer.assignedIssues.nodes)
check(#issues == 9, "completed issues are filtered out")
check(issues[1].cycle and issues[1].cycle.isActive, "active cycle comes first")

_, data = demo.respond(queries.my_issues, { filter = { cycle = { isActive = { eq = true } } } })
for _, i in ipairs(data.viewer.assignedIssues.nodes) do
  assert(i.cycle and i.cycle.isActive, "only active cycle")
end
check(true, "active cycle filter")

_, data = demo.respond(queries.issue_detail, { id = "ACME-102" })
local groups = model.group_links(data.issue)
check(data.issue.parent.identifier == "ACME-101", "parent resolved")
check(groups.blocked_by[1].identifier == "ACME-104", "blocked by resolved")
check(groups.related[1].identifier == "ACME-108", "related resolved")

_, data = demo.respond(queries.issue_detail, { id = "ACME-101" })
check(#data.issue.children.nodes == 3, "sub-issues resolved")

_, data = demo.respond(queries.issue_detail, { id = "ACME-105" })
check(model.group_links(data.issue).duplicated_by[1].identifier == "ACME-106", "duplicates resolved")

-- end to end through the real request path, no network
local view = require("linear.view")
view.open("ACME-102")
vim.wait(2000, function()
  return vim.b.linear_issue == "ACME-102"
end)
check(vim.b.linear_issue == "ACME-102", "issue opens through api.request in demo mode")
vim.fn.search("^- ACME-104")
vim.cmd("execute \"normal \\<CR>\"")
vim.wait(2000, function()
  return vim.b.linear_issue == "ACME-104"
end)
check(vim.b.linear_issue == "ACME-104", "follow blocked-by link")
vim.cmd("execute \"normal \\<BS>\"")
vim.wait(2000, function()
  return vim.b.linear_issue == "ACME-102"
end)
check(vim.b.linear_issue == "ACME-102", "back")
vim.cmd("normal gp")
vim.wait(2000, function()
  return vim.b.linear_issue == "ACME-101"
end)
check(vim.b.linear_issue == "ACME-101", "parent")

-- picking from the linked-issues picker (gr) records history, so <BS> comes back
view.open("ACME-102")
vim.wait(2000, function()
  return vim.b.linear_issue == "ACME-102"
end)
vim.ui.select = function(items, _, on_choice)
  for _, item in ipairs(items) do
    if item.identifier == "ACME-104" then
      on_choice(item)
    end
  end
end
vim.cmd("normal gr")
vim.wait(2000, function()
  return vim.b.linear_issue == "ACME-104"
end)
check(vim.b.linear_issue == "ACME-104", "gr opens the picked issue")
vim.cmd("execute \"normal \\<BS>\"")
vim.wait(2000, function()
  return vim.b.linear_issue == "ACME-102"
end)
check(vim.b.linear_issue == "ACME-102", "<BS> returns after a gr pick")

-- current branch issue pinned on top of the issue pickers
local git = require("linear.git")
local picker = require("linear.picker")
local config = require("linear.config")
check(git.branch_issue_id() == "ACME-102", "demo branch resolves to ACME-102")

local function pinned_result(list)
  local result
  picker._with_branch_issue(list, function(l, pinned)
    result = { list = l, pinned = pinned }
  end)
  vim.wait(2000, function()
    return result ~= nil
  end)
  return result
end

local _, all = demo.respond(queries.my_issues, { filter = {} })
local base = model.sort_issues(all.viewer.assignedIssues.nodes)
local r = pinned_result(base)
check(r.pinned == "ACME-102" and r.list[1].identifier == "ACME-102", "branch issue moved to the top")
check(#r.list == #base, "no duplicate when the issue is already listed")

local without = vim.tbl_filter(function(i)
  return i.identifier ~= "ACME-102"
end, base)
r = pinned_result(without)
check(r.list[1].identifier == "ACME-102" and #r.list == #without + 1, "missing branch issue is fetched and pinned")

git.branch_issue_id = function()
  return "NOPE-1", "nope-1-branch"
end
r = pinned_result(without)
check(r.pinned == nil and #r.list == #without, "unknown branch issue leaves the list unchanged")

config.options.pin_branch_issue = false
r = pinned_result(base)
check(r.pinned == nil and r.list[1].identifier == base[1].identifier, "pin_branch_issue = false disables pinning")

vim.cmd("qa!")
