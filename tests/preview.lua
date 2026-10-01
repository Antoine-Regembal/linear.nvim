-- Run with: nvim --headless --clean -l tests/preview.lua
vim.opt.rtp:prepend(vim.fn.getcwd())

local cache = require("linear.cache")
local picker = require("linear.picker")
local view = require("linear.view")

local function check(cond, msg)
  if not cond then
    print("FAIL " .. msg)
    os.exit(1)
  end
  print("ok   " .. msg)
end

local function fake_ctx(issue)
  local item = { issue = issue }
  local ctx = { item = item, lines = nil, errors = {} }
  ctx.preview = {
    reset = function() end,
    highlight = function() end,
    spinner = function() end,
    set_lines = function(_, lines)
      ctx.lines = table.concat(lines, "\n")
    end,
    notify = function(_, msg)
      table.insert(ctx.errors, msg)
    end,
  }
  ctx.current = item
  ctx.picker = {
    closed = false,
    current = function()
      return ctx.current
    end,
  }
  return ctx
end

local summary = { identifier = "ENG-1", title = "Title", state = { name = "Todo", type = "unstarted" } }
local full = vim.tbl_extend("force", summary, {
  description = "The full description",
  comments = { nodes = { { body = "A comment", createdAt = "2026-01-01T00:00:00Z", user = { name = "Alice" } } } },
})

-- cached: full render immediately
cache.set("ENG-1", full)
local ctx = fake_ctx(summary)
picker.preview(ctx)
check(
  ctx.lines:find("The full description") and ctx.lines:find("A comment"),
  "cached issue renders in full immediately"
)

-- not cached: summary first, full issue after the fetch
cache.clear()
local fetched = 0
view.fetch = function(id, cb)
  fetched = fetched + 1
  vim.schedule(function()
    cb(nil, full)
  end)
end
ctx = fake_ctx(summary)
picker.preview(ctx)
check(ctx.lines:find("# ENG%-1") and not ctx.lines:find("The full description"), "summary shown while loading")
vim.wait(1000, function()
  return ctx.lines:find("The full description") ~= nil
end)
check(ctx.lines:find("The full description") ~= nil, "full issue shown once fetched")

-- cursor moved away before the debounce: no request, no overwrite
fetched = 0
ctx = fake_ctx(summary)
picker.preview(ctx)
ctx.current = { issue = { identifier = "ENG-9" } }
vim.wait(400)
check(fetched == 0, "no request when the cursor moved before the debounce")
check(not ctx.lines:find("The full description"), "stale preview not applied")

-- fetch error goes to the preview
view.fetch = function(_, cb)
  vim.schedule(function()
    cb("boom", nil)
  end)
end
ctx = fake_ctx(summary)
picker.preview(ctx)
vim.wait(1000, function()
  return #ctx.errors > 0
end)
check(ctx.errors[1] == "boom", "fetch error shown in the preview")

vim.cmd("qa!")
