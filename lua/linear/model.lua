local M = {}

M.ID_PATTERN = "%f[%w]%u[%u%d]*%-%d+%f[^%w]"

local STATE_ORDER = { started = 1, unstarted = 2, triage = 3, backlog = 4, completed = 5, canceled = 6 }

---@param conn any GraphQL connection ({ nodes = {...} }) or plain list
---@return table[]
function M.nodes(conn)
  if type(conn) ~= "table" then
    return {}
  end
  return conn.nodes or conn
end

---@param cycle table|nil
---@return integer
local function cycle_rank(cycle)
  if not cycle then
    return 4
  end
  if cycle.isActive then
    return 1
  end
  if cycle.isNext then
    return 2
  end
  return 3
end

---@param cycle table|nil
---@return string
function M.cycle_label(cycle)
  if not cycle then
    return "No cycle"
  end
  local name = cycle.name and cycle.name ~= "" and cycle.name or ("Cycle " .. cycle.number)
  if cycle.isActive then
    return name .. " (active)"
  elseif cycle.isNext then
    return name .. " (next)"
  end
  return name
end

---Active cycle first, then next, then older ones (most recent first), then no cycle;
---inside a cycle, by workflow state then priority (1 = urgent, 0 = none last).
---@param issues table[]
---@return table[]
function M.sort_issues(issues)
  local sorted = vim.list_extend({}, issues)
  local function prio(i)
    return (i.priority == nil or i.priority == 0) and 5 or i.priority
  end
  table.sort(sorted, function(a, b)
    local ra, rb = cycle_rank(a.cycle), cycle_rank(b.cycle)
    if ra ~= rb then
      return ra < rb
    end
    local na, nb = a.cycle and a.cycle.number or 0, b.cycle and b.cycle.number or 0
    if na ~= nb then
      return na > nb
    end
    local sa = STATE_ORDER[a.state and a.state.type] or 9
    local sb = STATE_ORDER[b.state and b.state.type] or 9
    if sa ~= sb then
      return sa < sb
    end
    if prio(a) ~= prio(b) then
      return prio(a) < prio(b)
    end
    return a.identifier < b.identifier
  end)
  return sorted
end

---@param issue table
---@return table<string, table[]>
function M.group_links(issue)
  local groups = { blocks = {}, blocked_by = {}, related = {}, duplicate_of = {}, duplicated_by = {} }
  for _, r in ipairs(M.nodes(issue.relations)) do
    if r.type == "blocks" then
      table.insert(groups.blocks, r.relatedIssue)
    elseif r.type == "duplicate" then
      table.insert(groups.duplicate_of, r.relatedIssue)
    elseif r.type == "related" or r.type == "similar" then
      table.insert(groups.related, r.relatedIssue)
    end
  end
  for _, r in ipairs(M.nodes(issue.inverseRelations)) do
    if r.type == "blocks" then
      table.insert(groups.blocked_by, r.issue)
    elseif r.type == "duplicate" then
      table.insert(groups.duplicated_by, r.issue)
    elseif r.type == "related" or r.type == "similar" then
      table.insert(groups.related, r.issue)
    end
  end
  return groups
end

local function link_line(i)
  return ("- %s  [%s]  %s"):format(i.identifier, i.state and i.state.name or "?", i.title)
end

local function split(text)
  return vim.split((text or ""):gsub("\r", ""), "\n", { plain = true })
end

---@param issue table issue_detail payload
---@param files? table<string, linear.Upload> local files of embedded uploads, by URL
---@return string[]
function M.render(issue, files)
  local uploads = require("linear.uploads")
  files = files or {}
  local lines = { ("# %s  %s"):format(issue.identifier, issue.title), "" }
  local labels = vim.tbl_map(function(l)
    return l.name
  end, M.nodes(issue.labels))
  local meta = {
    { "Status", issue.state and issue.state.name },
    { "Priority", issue.priorityLabel },
    { "Cycle", issue.cycle and M.cycle_label(issue.cycle) },
    { "Assignee", issue.assignee and issue.assignee.name or "Unassigned" },
    { "Team", issue.team and issue.team.name },
    { "Project", issue.project and issue.project.name },
    { "Labels", #labels > 0 and table.concat(labels, ", ") or nil },
    { "Branch", issue.branchName },
    { "URL", issue.url },
  }
  for _, m in ipairs(meta) do
    if m[2] and m[2] ~= "" then
      table.insert(lines, ("- **%s**: %s"):format(m[1], m[2]))
    end
  end

  local groups = M.group_links(issue)
  local sections = {
    { "Parent", issue.parent and { issue.parent } or {} },
    { "Sub-issues", M.nodes(issue.children) },
    { "Blocked by", groups.blocked_by },
    { "Blocks", groups.blocks },
    { "Related", groups.related },
    { "Duplicate of", groups.duplicate_of },
    { "Duplicated by", groups.duplicated_by },
  }
  for _, s in ipairs(sections) do
    if #s[2] > 0 then
      vim.list_extend(lines, { "", "## " .. s[1], "" })
      for _, i in ipairs(s[2]) do
        table.insert(lines, link_line(i))
      end
    end
  end

  vim.list_extend(lines, { "", "## Description", "" })
  vim.list_extend(
    lines,
    split(
      issue.description ~= nil and issue.description ~= "" and uploads.rewrite(issue.description, files)
        or "_No description_"
    )
  )

  local comments = vim.list_extend({}, M.nodes(issue.comments))
  table.sort(comments, function(a, b)
    return a.createdAt < b.createdAt
  end)
  if #comments > 0 then
    vim.list_extend(lines, { "", ("## Comments (%d)"):format(#comments) })
    for _, c in ipairs(comments) do
      vim.list_extend(
        lines,
        { "", ("### %s · %s"):format(c.user and c.user.name or "Unknown", c.createdAt:sub(1, 10)), "" }
      )
      vim.list_extend(lines, split(uploads.rewrite(c.body, files)))
    end
  end
  return lines
end

---@param text string|nil
---@param opts? { loose?: boolean } loose also accepts lowercase ids (git branch names)
---@return string|nil
function M.find_id(text, opts)
  if not text then
    return nil
  end
  local id = text:match(M.ID_PATTERN)
  if not id and opts and opts.loose then
    id = text:match("%f[%w]%a[%a%d]*%-%d+%f[^%w]")
  end
  return id and id:upper() or nil
end

---Move `issue` to the top of `issues`, adding it when missing.
---@param issues table[]
---@param issue table
---@return table[]
function M.pin_issue(issues, issue)
  local pinned = { issue }
  for _, i in ipairs(issues) do
    if i.identifier ~= issue.identifier then
      table.insert(pinned, i)
    end
  end
  return pinned
end

---@param issue table
---@return table[]
function M.linked_issues(issue)
  local ids, seen = {}, {}
  local function add(i)
    if i and i.identifier and not seen[i.identifier] then
      seen[i.identifier] = true
      table.insert(ids, i)
    end
  end
  add(issue.parent)
  for _, i in ipairs(M.nodes(issue.children)) do
    add(i)
  end
  local groups = M.group_links(issue)
  for _, name in ipairs({ "blocked_by", "blocks", "related", "duplicate_of", "duplicated_by" }) do
    for _, i in ipairs(groups[name]) do
      add(i)
    end
  end
  return ids
end

return M
