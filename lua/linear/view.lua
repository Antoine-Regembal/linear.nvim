local api = require("linear.api")
local cache = require("linear.cache")
local model = require("linear.model")
local queries = require("linear.queries")
local uploads = require("linear.uploads")

local M = {}

---@type table<integer, table>
local current = {}

---@param id string
---@param cb fun(err: string|nil, issue: table|nil)
---@param opts? { refresh?: boolean }
function M.fetch(id, cb, opts)
  local cached = not (opts and opts.refresh) and cache.get(id)
  if cached then
    cb(nil, cached)
    return
  end
  api.request(queries.issue_detail, { id = id }, function(err, data)
    if err then
      cb(err, nil)
      return
    end
    if not data or not data.issue then
      cb(("issue %s not found"):format(id), nil)
      return
    end
    cache.set(data.issue.identifier, data.issue)
    cb(nil, data.issue)
  end)
end

local function set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
end

local function id_under_cursor()
  return model.find_id(vim.api.nvim_get_current_line())
end

---Upload or cached attachment linked on the cursor line.
---@return string|nil
local function attachment_under_cursor()
  local dir = uploads.dir()
  for target in vim.api.nvim_get_current_line():gmatch("%]%(([^%s%)]+)[^%)]*%)") do
    if uploads.is_upload(target) or vim.startswith(target, dir) then
      return target
    end
  end
end

local function open_attachment(target)
  if not uploads.is_upload(target) then
    vim.ui.open(target)
    return
  end
  vim.notify("Linear: downloading attachment…", vim.log.levels.INFO, { id = "linear_loading" })
  uploads.fetch(target, function(err, file)
    if not file then
      vim.notify("Linear: " .. err, vim.log.levels.ERROR, { id = "linear_loading" })
      return
    end
    vim.notify("Linear: attachment ready", vim.log.levels.INFO, { id = "linear_loading", timeout = 500 })
    vim.ui.open(file.path)
  end)
end

---Re-render an issue buffer, keeping the cursor of every window showing it.
local function rerender(buf, lines)
  local cursors = {}
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    cursors[win] = vim.api.nvim_win_get_cursor(win)
  end
  set_lines(buf, lines)
  for win, cursor in pairs(cursors) do
    cursor[1] = math.min(cursor[1], vim.api.nvim_buf_line_count(buf))
    pcall(vim.api.nvim_win_set_cursor, win, cursor)
  end
end

---Download the issue's images, then show them in place of their remote URLs.
local function load_attachments(buf, issue, files)
  local list = uploads.collect(issue)
  if #list == vim.tbl_count(files) then
    return
  end
  uploads.fetch_all(issue, function(all, errors)
    if #errors > 0 then
      vim.notify(("Linear: %d attachment(s) could not be loaded: %s"):format(#errors, errors[1]), vim.log.levels.WARN)
    end
    if vim.api.nvim_buf_is_valid(buf) and current[buf] == issue then
      rerender(buf, model.render(issue, all))
    end
  end)
end

local function map(buf, lhs, fn, desc)
  vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = "Linear: " .. desc })
end

local function setup_buffer(buf)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  vim.b[buf].linear_history = vim.b[buf].linear_history or {}

  local function follow()
    local id = id_under_cursor()
    if id and id ~= vim.b[buf].linear_issue then
      M.open(id, { push = true })
    end
  end
  map(buf, "<CR>", follow, "open issue under cursor")
  map(buf, "gd", follow, "open issue under cursor")
  map(buf, "<BS>", function()
    M.back()
  end, "previous issue")
  map(buf, "gp", function()
    local issue = current[buf]
    if issue and issue.parent then
      M.open(issue.parent.identifier, { push = true })
    else
      vim.notify("Linear: no parent issue")
    end
  end, "open parent")
  map(buf, "gr", function()
    local issue = current[buf]
    if issue then
      require("linear.picker").linked(issue)
    end
  end, "pick linked issue")
  map(buf, "gx", function()
    local attachment = attachment_under_cursor()
    if attachment then
      open_attachment(attachment)
      return
    end
    local id = id_under_cursor() or vim.b[buf].linear_issue
    local issue = current[buf]
    if issue and id ~= issue.identifier then
      issue = cache.get(id)
    end
    if issue then
      vim.ui.open(issue.url)
    else
      M.fetch(id, function(err, linked)
        if linked then
          vim.ui.open(linked.url)
        else
          vim.notify("Linear: " .. err, vim.log.levels.ERROR)
        end
      end)
    end
  end, "open attachment or issue in browser")
  map(buf, "yy", function()
    local id = id_under_cursor() or vim.b[buf].linear_issue
    vim.fn.setreg('"', id)
    pcall(vim.fn.setreg, "+", id)
    vim.notify("Linear: copied " .. id)
  end, "copy identifier")
  map(buf, "R", function()
    M.open(vim.b[buf].linear_issue, { refresh = true })
  end, "refresh")
  map(buf, "q", function()
    vim.api.nvim_buf_delete(buf, {})
  end, "close")
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    callback = function()
      current[buf] = nil
    end,
  })
end

---snacks.image sets itself up on the first file read (BufReadPre), and issue buffers are
---not files: set it up and attach it so embedded images show even when no file was opened.
---@param buf integer
local function attach_images(buf)
  pcall(function()
    if Snacks.image.config.enabled then
      Snacks.image.setup()
      Snacks.image.doc.attach(buf)
    end
  end)
end

local function get_buffer()
  local cur = vim.api.nvim_get_current_buf()
  if vim.b[cur].linear_issue ~= nil then
    return cur, false
  end
  local buf = vim.api.nvim_create_buf(false, true)
  setup_buffer(buf)
  if require("linear.config").options.attachments.enabled then
    attach_images(buf)
  end
  return buf, true
end

---@param id string
---@param opts? { push?: boolean, refresh?: boolean, pop?: boolean }
function M.open(id, opts)
  opts = opts or {}
  vim.notify("Linear: loading " .. id .. "…", vim.log.levels.INFO, { id = "linear_loading" })
  M.fetch(id, function(err, issue)
    if err then
      vim.notify("Linear: " .. err, vim.log.levels.ERROR, { id = "linear_loading" })
      return
    end
    local buf, created = get_buffer()
    local previous = vim.b[buf].linear_issue
    if opts.push and previous and previous ~= issue.identifier then
      local history = vim.b[buf].linear_history
      table.insert(history, previous)
      vim.b[buf].linear_history = history
    end
    vim.b[buf].linear_issue = issue.identifier
    current[buf] = issue
    pcall(vim.api.nvim_buf_set_name, buf, "linear://" .. issue.identifier)
    local attachments = require("linear.config").options.attachments.enabled
    local files = attachments and uploads.cached(issue) or {}
    set_lines(buf, model.render(issue, files))
    if attachments then
      load_attachments(buf, issue, files)
    end
    if created or vim.api.nvim_get_current_buf() ~= buf then
      vim.api.nvim_set_current_buf(buf)
    end
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.notify("Linear: " .. issue.identifier, vim.log.levels.INFO, { id = "linear_loading", timeout = 500 })
  end, { refresh = opts.refresh })
end

function M.back()
  local buf = vim.api.nvim_get_current_buf()
  local history = vim.b[buf].linear_history or {}
  local prev = table.remove(history)
  vim.b[buf].linear_history = history
  if prev then
    M.open(prev)
  else
    vim.notify("Linear: no previous issue")
  end
end

return M
