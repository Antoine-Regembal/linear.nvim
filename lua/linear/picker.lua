local api = require("linear.api")
local cache = require("linear.cache")
local config = require("linear.config")
local model = require("linear.model")
local queries = require("linear.queries")

local M = {}

local STATE_HL = {
  started = "DiagnosticWarn",
  unstarted = "DiagnosticInfo",
  triage = "DiagnosticHint",
  backlog = "Comment",
  completed = "DiagnosticOk",
  canceled = "Comment",
}

local function short_cycle(cycle)
  if not cycle then
    return "-"
  end
  local tag = cycle.isActive and "*" or (cycle.isNext and ">" or "")
  return ("C%d%s"):format(cycle.number, tag)
end

local function summary_preview(issue)
  return {
    ("# %s  %s"):format(issue.identifier, issue.title),
    "",
    ("- **Status**: %s"):format(issue.state and issue.state.name or "?"),
    ("- **Priority**: %s"):format(issue.priorityLabel or "?"),
    ("- **Cycle**: %s"):format(model.cycle_label(issue.cycle)),
    ("- **Team**: %s"):format(issue.team and issue.team.name or "?"),
  }
end

local PREVIEW_DEBOUNCE_MS = 150

local function still_current(ctx)
  if ctx.picker.closed then
    return false
  end
  local current = ctx.picker:current()
  return current ~= nil and current.issue.identifier == ctx.item.issue.identifier
end

local function render_preview(ctx, lines)
  ctx.preview:reset()
  ctx.preview:set_lines(lines)
  ctx.preview:highlight({ ft = "markdown" })
end

---Summary right away, full issue (description, comments, links) once fetched.
---@param ctx table snacks.picker.preview.ctx
function M.preview(ctx)
  local issue = ctx.item.issue
  local cached = cache.get(issue.identifier)
  if cached then
    render_preview(ctx, model.render(cached))
    return
  end
  render_preview(ctx, summary_preview(issue))
  ctx.preview:spinner(true)
  vim.defer_fn(function()
    if not still_current(ctx) then
      return
    end
    require("linear.view").fetch(issue.identifier, function(err, full)
      if not still_current(ctx) then
        return
      end
      ctx.preview:spinner(false)
      if err then
        ctx.preview:notify(err, "error", { item = false })
        return
      end
      render_preview(ctx, model.render(full))
    end)
  end, PREVIEW_DEBOUNCE_MS)
end

---@param issues table[]
---@param title string
---@param opts? { push?: boolean, pinned?: string } push: record history; pinned: id of the branch issue
local function show(issues, title, opts)
  local open = function(issue)
    require("linear.view").open(issue.identifier, { push = opts and opts.push })
  end
  local ok, Snacks = pcall(require, "snacks")
  if not ok or not Snacks.picker then
    vim.ui.select(issues, {
      prompt = title,
      format_item = function(i)
        local col = opts and opts.pinned == i.identifier and "git" or short_cycle(i.cycle)
        return ("%-5s %-10s [%s] %s"):format(col, i.identifier, i.state.name, i.title)
      end,
    }, function(choice)
      if choice then
        open(choice)
      end
    end)
    return
  end
  local items = {}
  for idx, issue in ipairs(issues) do
    table.insert(items, {
      idx = idx,
      text = table.concat({ issue.identifier, issue.title, issue.state.name, model.cycle_label(issue.cycle) }, " "),
      issue = issue,
      from_branch = opts and opts.pinned == issue.identifier or nil,
    })
  end
  Snacks.picker.pick({
    title = title,
    items = items,
    preview = M.preview,
    format = function(item)
      local i = item.issue
      return {
        item.from_branch and { "git   ", "DiagnosticOk" } or { ("%-5s "):format(short_cycle(i.cycle)), "Special" },
        { ("%-11s "):format(i.identifier), "Identifier" },
        { ("%-14s "):format("[" .. i.state.name .. "]"), STATE_HL[i.state.type] or "Normal" },
        { ("%-3s "):format(i.priority and i.priority > 0 and ("P" .. i.priority) or ""), "Number" },
        { i.title },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        open(item.issue)
      end
    end,
  })
end

---Pin the current branch's issue on top, fetching it when it is not in `issues`.
---@param issues table[]
---@param cb fun(issues: table[], pinned: string|nil)
local function with_branch_issue(issues, cb)
  if not config.options.pin_branch_issue then
    cb(issues, nil)
    return
  end
  local id = require("linear.git").branch_issue_id()
  if not id then
    cb(issues, nil)
    return
  end
  for _, i in ipairs(issues) do
    if i.identifier == id then
      cb(model.pin_issue(issues, i), id)
      return
    end
  end
  require("linear.view").fetch(id, function(err, issue)
    if err or not issue then
      cb(issues, nil)
      return
    end
    cb(model.pin_issue(issues, issue), id)
  end)
end

M._with_branch_issue = with_branch_issue

---@param opts? { active_cycle?: boolean }
function M.my_issues(opts)
  opts = opts or {}
  local filter = {}
  if not config.options.include_completed then
    filter.state = { type = { nin = { "completed", "canceled" } } }
  end
  if opts.active_cycle then
    filter.cycle = { isActive = { eq = true } }
  end
  vim.notify("Linear: fetching issues…", vim.log.levels.INFO, { id = "linear_loading" })
  api.request(queries.my_issues, { first = config.options.max_issues, filter = filter }, function(err, data)
    if err then
      vim.notify("Linear: " .. err, vim.log.levels.ERROR, { id = "linear_loading" })
      return
    end
    local issues = model.sort_issues(model.nodes(data.viewer.assignedIssues))
    local title = opts.active_cycle and "Linear · active cycle" or "Linear · my issues"
    with_branch_issue(issues, function(list, pinned)
      vim.notify(("Linear: %d issues"):format(#list), vim.log.levels.INFO, { id = "linear_loading", timeout = 500 })
      if #list == 0 then
        return
      end
      show(list, title, { pinned = pinned })
    end)
  end)
end

---@param issue table
function M.linked(issue)
  local linked = model.linked_issues(issue)
  if #linked == 0 then
    vim.notify("Linear: no linked issues")
    return
  end
  show(linked, "Linear · linked to " .. issue.identifier, { push = true })
end

return M
