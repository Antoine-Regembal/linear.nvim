local M = {}

M.enabled = false

local DELAY_MS = 250

local team = { key = "ACME", name = "Acme" }

local cycles = {
  prev = { id = "c11", number = 11, name = "", isActive = false, isNext = false, isPrevious = true },
  active = { id = "c12", number = 12, name = "", isActive = true, isNext = false, isPrevious = false },
  next = { id = "c13", number = 13, name = "", isActive = false, isNext = true, isPrevious = false },
}

local states = {
  backlog = { name = "Backlog", type = "backlog" },
  todo = { name = "Todo", type = "unstarted" },
  progress = { name = "In Progress", type = "started" },
  review = { name = "In Review", type = "started" },
  done = { name = "Done", type = "completed" },
}

local PRIORITY_LABELS = { [0] = "No priority", "Urgent", "High", "Medium", "Low" }

local function issue(n, title, state, priority, cycle, extra)
  local id = "ACME-" .. n
  return vim.tbl_extend("force", {
    id = "demo-" .. n,
    identifier = id,
    title = title,
    state = states[state],
    priority = priority,
    priorityLabel = PRIORITY_LABELS[priority],
    cycle = cycle and cycles[cycle] or nil,
    team = team,
    url = "https://linear.app/acme/issue/" .. id,
    branchName = "alex/acme-" .. n,
    createdAt = "2026-09-01T09:00:00Z",
    updatedAt = "2026-09-20T09:00:00Z",
    assignee = { name = "Alex Martin" },
    creator = { name = "Sam Lee" },
    labels = { nodes = {} },
    description = "",
    comments = { nodes = {} },
  }, extra or {})
end

local list = {
  issue(101, "Settings page redesign", "progress", 2, "active", {
    labels = { nodes = { { name = "Epic" }, { name = "Design" } } },
    project = { name = "Settings v2" },
    description = table.concat({
      "Rework the settings page into tabbed sections.",
      "",
      "## Scope",
      "- General, Appearance, Notifications tabs",
      "- Dark mode toggle",
      "- Persist preferences per user",
    }, "\n"),
    comments = {
      nodes = {
        {
          body = "Mockups are ready in the design file.",
          createdAt = "2026-09-02T10:00:00Z",
          user = { name = "Sam Lee" },
        },
        {
          body = "Splitting this into sub-issues.",
          createdAt = "2026-09-03T14:30:00Z",
          user = { name = "Alex Martin" },
        },
      },
    },
  }),
  issue(102, "Add dark mode to settings page", "progress", 2, "active", {
    parent = "ACME-101",
    labels = { nodes = { { name = "Feature" } } },
    description = "Add a toggle in **Appearance** that switches the app theme.\n\n- Follow the system preference by default\n- Store the choice in user preferences",
    comments = {
      nodes = {
        {
          body = "Blocked until the theme tokens land (ACME-104).",
          createdAt = "2026-09-10T08:15:00Z",
          user = { name = "Alex Martin" },
        },
        { body = "Tokens PR is in review.", createdAt = "2026-09-11T16:40:00Z", user = { name = "Jordan Kim" } },
      },
    },
  }),
  issue(103, "Persist user preferences", "todo", 3, "active", {
    parent = "ACME-101",
    labels = { nodes = { { name = "Backend" } } },
    description = "Expose `GET/PUT /preferences` and store them per user.",
  }),
  issue(104, "Extract theme tokens", "review", 1, "active", {
    labels = { nodes = { { name = "Tech debt" } } },
    description = "Move hard-coded colors to CSS variables so themes can be switched at runtime.",
    comments = {
      nodes = { { body = "Ready for review.", createdAt = "2026-09-12T11:00:00Z", user = { name = "Jordan Kim" } } },
    },
  }),
  issue(105, "Fix login redirect loop", "todo", 1, "active", {
    labels = { nodes = { { name = "Bug" } } },
    description = "After logging out and back in, the app redirects between `/login` and `/home` forever.\n\n**Steps**\n1. Log out\n2. Log in\n3. Observe the loop",
  }),
  issue(106, "Redirect loop after logout", "backlog", 0, nil, {
    labels = { nodes = { { name = "Bug" } } },
    description = "Seems to be the same as ACME-105.",
  }),
  issue(107, "Notification preferences tab", "todo", 3, "next", {
    parent = "ACME-101",
    description = "Let users choose which emails they receive.",
  }),
  issue(108, "Audit settings accessibility", "backlog", 4, "next", {
    labels = { nodes = { { name = "a11y" } } },
    description = "Keyboard navigation and screen reader labels for every settings field.",
  }),
  issue(109, "Onboarding checklist", "done", 3, "prev", {
    description = "Show a checklist to new users.",
  }),
  issue(110, "Update dependencies", "todo", 4, nil, {
    description = "Monthly dependency bump.",
  }),
}

local relations = {
  { "ACME-104", "blocks", "ACME-102" },
  { "ACME-103", "blocks", "ACME-107" },
  { "ACME-102", "related", "ACME-108" },
  { "ACME-106", "duplicate", "ACME-105" },
}

local by_id = {}
for _, i in ipairs(list) do
  by_id[i.identifier] = i
end

local function short(id)
  local i = by_id[id]
  return { identifier = i.identifier, title = i.title, state = i.state }
end

local function summary(i)
  return {
    id = i.id,
    identifier = i.identifier,
    title = i.title,
    priority = i.priority,
    priorityLabel = i.priorityLabel,
    url = i.url,
    branchName = i.branchName,
    updatedAt = i.updatedAt,
    state = i.state,
    team = i.team,
    cycle = i.cycle,
  }
end

local function detail(id)
  local base = by_id[id]
  if not base then
    return nil
  end
  local i = vim.deepcopy(base)
  i.parent = base.parent and short(base.parent) or nil
  local children, rel, inv = {}, {}, {}
  for _, other in ipairs(list) do
    if other.parent == id then
      table.insert(children, short(other.identifier))
    end
  end
  for _, r in ipairs(relations) do
    if r[1] == id then
      table.insert(rel, { type = r[2], relatedIssue = short(r[3]) })
    elseif r[3] == id then
      table.insert(inv, { type = r[2], issue = short(r[1]) })
    end
  end
  i.children = { nodes = children }
  i.relations = { nodes = rel }
  i.inverseRelations = { nodes = inv }
  return i
end

local function my_issues(filter)
  filter = filter or {}
  local excluded = filter.state and filter.state.type and filter.state.type.nin or {}
  local active_only = filter.cycle and filter.cycle.isActive and filter.cycle.isActive.eq
  local nodes = {}
  for _, i in ipairs(list) do
    local keep = not vim.tbl_contains(excluded, i.state.type)
    if active_only then
      keep = keep and i.cycle ~= nil and i.cycle.isActive
    end
    if keep then
      table.insert(nodes, summary(i))
    end
  end
  return nodes
end

---@param query string
---@param variables table
---@return string|nil err, table|nil data
function M.respond(query, variables)
  local name = query:match("query%s+(%w+)")
  if name == "Viewer" then
    return nil, { viewer = { id = "demo-user", name = "Alex Martin (demo)", email = "alex@example.com" } }
  elseif name == "MyIssues" then
    return nil, { viewer = { assignedIssues = { nodes = my_issues(variables.filter) } } }
  elseif name == "IssueDetail" then
    return nil, { issue = detail(variables.id) }
  end
  return "demo mode does not support query " .. tostring(name), nil
end

---@param query string
---@param variables table
---@param cb fun(err: string|nil, data: table|nil)
function M.request(query, variables, cb)
  vim.defer_fn(function()
    cb(M.respond(query, variables))
  end, DELAY_MS)
end

---@param on boolean
function M.set(on)
  M.enabled = on
  require("linear.cache").clear()
end

return M
