-- Minimal config used by assets/demo.tape: NVIM_APPNAME=linear-demo nvim -u assets/demo-init.lua
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "--branch=stable",
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

vim.g.mapleader = " "
vim.o.termguicolors = true
vim.o.laststatus = 3
vim.o.statusline = " "
vim.o.cmdheight = 1
vim.o.showmode = false
vim.o.number = false
vim.o.signcolumn = "no"
vim.o.fillchars = "eob: "

require("lazy").setup({
  {
    "folke/tokyonight.nvim",
    priority = 1000,
    config = function()
      vim.cmd.colorscheme("tokyonight-night")
    end,
  },
  { "folke/snacks.nvim", opts = { picker = { enabled = true } } },
  { dir = vim.fn.getcwd(), name = "linear.nvim", dependencies = { "folke/snacks.nvim" }, opts = { demo = true } },
}, { install = { colorscheme = { "tokyonight" } }, change_detection = { enabled = false } })

-- Recording overlays: a caption bar explaining each step, and the keys being pressed.

local steps = {
  { keys = nil, title = "linear.nvim: browse your Linear issues from Neovim", sub = "Demo mode, fictional data" },
  {
    keys = "<Space>ii",
    title = "Your issues by sprint, current branch's issue pinned on top",
    sub = "Branch alex/acme-102-dark-mode -> ACME-102 (git), then active cycle (C12*), next (C13>), no cycle",
  },
  {
    keys = "<Down>",
    title = "The preview shows the full issue",
    sub = "Description, comments and linked issues load as you move",
  },
  { keys = "<CR>", title = "Open the issue", sub = "Parent, blocked by, related, description and comments" },
  {
    keys = "gr",
    title = "Pick a linked issue",
    sub = "Parent, sub-issues, blocking, blocked by, related and duplicates",
  },
  {
    keys = "<CR>",
    title = "Follow the link: ACME-104 blocks ACME-102",
    sub = "Every issue identifier in the buffer can be opened with Enter",
  },
  { keys = "<BS>", title = "Go back to the previous issue", sub = "Navigation history, like tags" },
  { keys = "gp", title = "Jump to the parent issue", sub = "Its sub-issues are listed and can be opened too" },
}

local labels = {
  ["<Space>ii"] = "My issues",
  ["<Down>"] = "Next issue",
  ["<CR>"] = "Open",
  ["gr"] = "Linked issues",
  ["<BS>"] = "Back",
  ["gp"] = "Parent issue",
}

local pretty = { ["<Space>"] = "Space", ["<CR>"] = "Enter", ["<BS>"] = "Backspace", ["<Down>"] = "↓" }

local ns = vim.api.nvim_create_namespace("linear_demo")
vim.api.nvim_set_hl(0, "DemoCaption", { link = "NormalFloat" })
vim.api.nvim_set_hl(0, "DemoTitle", { link = "Title" })
vim.api.nvim_set_hl(0, "DemoSub", { link = "Comment" })
vim.api.nvim_set_hl(0, "DemoKey", { link = "Search" })
vim.api.nvim_set_hl(0, "DemoKeyLabel", { link = "Special" })

-- An empty split reserves the space, a float above the picker backdrop draws the caption
local main_win = vim.api.nvim_get_current_win()
vim.cmd("topleft 3split")
local caption_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(caption_win, vim.api.nvim_create_buf(false, true))
vim.wo[caption_win].winfixheight = true
vim.wo[caption_win].winhighlight = "Normal:DemoCaption"
vim.api.nvim_set_current_win(main_win)

local caption_buf = vim.api.nvim_create_buf(false, true)
local caption_float = vim.api.nvim_open_win(caption_buf, false, {
  relative = "editor",
  row = 0,
  col = 0,
  width = vim.o.columns,
  height = 3,
  style = "minimal",
  focusable = false,
  zindex = 300,
})
vim.wo[caption_float].winhighlight = "Normal:DemoCaption"
vim.api.nvim_create_autocmd("WinEnter", {
  callback = function()
    if vim.api.nvim_get_current_win() == caption_win and vim.api.nvim_win_is_valid(main_win) then
      vim.api.nvim_set_current_win(main_win)
    end
  end,
})

local step = 1

local function render_caption()
  local s = steps[step]
  local counter = ("%d/%d"):format(step, #steps)
  local lines = { "  " .. s.title .. "   " .. counter, "  " .. s.sub, "" }
  vim.api.nvim_buf_set_lines(caption_buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(caption_buf, ns, 0, -1)
  vim.api.nvim_buf_set_extmark(caption_buf, ns, 0, 0, { end_col = #s.title + 2, hl_group = "DemoTitle" })
  vim.api.nvim_buf_set_extmark(caption_buf, ns, 0, #s.title + 2, { end_col = #lines[1], hl_group = "DemoSub" })
  vim.api.nvim_buf_set_extmark(caption_buf, ns, 1, 0, { end_col = #lines[2], hl_group = "DemoSub" })
end
render_caption()

local key_buf = vim.api.nvim_create_buf(false, true)
local key_win

local function render_keys(seq, label)
  local shown = {}
  local rest = seq
  while #rest > 0 do
    local token = rest:match("^<[^>]+>") or rest:sub(1, 1)
    shown[#shown + 1] = pretty[token] or token
    rest = rest:sub(#token + 1)
  end
  local keys = " " .. table.concat(shown, " ") .. " "
  local text = label and (keys .. "  " .. label .. " ") or keys
  vim.api.nvim_buf_set_lines(key_buf, 0, -1, false, { text })
  vim.api.nvim_buf_clear_namespace(key_buf, ns, 0, -1)
  vim.api.nvim_buf_set_extmark(key_buf, ns, 0, 0, { end_col = #keys, hl_group = "DemoKey" })
  if label then
    vim.api.nvim_buf_set_extmark(key_buf, ns, 0, #keys, { end_col = #text, hl_group = "DemoKeyLabel" })
  end
  local width = vim.fn.strdisplaywidth(text)
  local config = {
    relative = "editor",
    row = vim.o.lines - 4,
    col = vim.o.columns - width - 3,
    width = width,
    height = 1,
    style = "minimal",
    border = "rounded",
    focusable = false,
    zindex = 300,
  }
  if key_win and vim.api.nvim_win_is_valid(key_win) then
    vim.api.nvim_win_set_config(key_win, config)
  else
    key_win = vim.api.nvim_open_win(key_buf, false, config)
  end
end

local seq, last = "", 0

vim.on_key(function(key, typed)
  local k = vim.fn.keytrans(typed ~= nil and typed ~= "" and typed or key)
  if k == "" or k:match("^<Cmd>") or k:match("^<.*Mouse") then
    return
  end
  local now = vim.uv.now()
  if now - last > 1000 then
    seq = ""
  end
  last = now
  seq = seq .. k
  vim.schedule(function()
    local label, matched
    for combo, l in pairs(labels) do
      if vim.endswith(seq, combo) and (not matched or #combo > #matched) then
        label, matched = l, combo
      end
    end
    local next_step = steps[step + 1]
    if next_step and vim.endswith(seq, next_step.keys) then
      step = step + 1
      render_caption()
    end
    render_keys(matched or seq, label)
  end)
end, ns)
