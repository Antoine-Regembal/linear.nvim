-- Run with: nvim --headless -l tests/run.lua
vim.opt.rtp:prepend(vim.fn.getcwd())

local model = require("linear.model")
local api = require("linear.api")

local failures, count = 0, 0
local function test(name, fn)
  count = count + 1
  local ok, err = pcall(fn)
  if ok then
    print("ok   " .. name)
  else
    failures = failures + 1
    print("FAIL " .. name .. "\n     " .. tostring(err))
  end
end

local function eq(a, b)
  assert(vim.deep_equal(a, b), ("expected %s, got %s"):format(vim.inspect(b), vim.inspect(a)))
end

local function issue(id, cycle, state, priority)
  return { identifier = id, title = id, cycle = cycle, state = { name = state, type = state }, priority = priority }
end

test("sort: active, next, older cycles desc, no cycle; then state and priority", function()
  local active = { number = 12, isActive = true }
  local nxt = { number = 13, isNext = true }
  local old = { number = 10 }
  local older = { number = 9 }
  local sorted = model.sort_issues({
    issue("A-1", nil, "started", 1),
    issue("A-2", older, "started", 1),
    issue("A-3", old, "started", 1),
    issue("A-4", nxt, "unstarted", 2),
    issue("A-5", active, "backlog", 1),
    issue("A-6", active, "started", 0),
    issue("A-7", active, "started", 2),
  })
  eq(vim.tbl_map(function(i)
    return i.identifier
  end, sorted), { "A-7", "A-6", "A-5", "A-4", "A-3", "A-2", "A-1" })
end)

test("group_links: blocks vs blocked by, related, duplicates", function()
  local g = model.group_links({
    relations = {
      nodes = {
        { type = "blocks", relatedIssue = { identifier = "X-2" } },
        { type = "related", relatedIssue = { identifier = "X-3" } },
        { type = "duplicate", relatedIssue = { identifier = "X-4" } },
      },
    },
    inverseRelations = {
      nodes = {
        { type = "blocks", issue = { identifier = "X-5" } },
        { type = "duplicate", issue = { identifier = "X-6" } },
      },
    },
  })
  eq(g.blocks[1].identifier, "X-2")
  eq(g.related[1].identifier, "X-3")
  eq(g.duplicate_of[1].identifier, "X-4")
  eq(g.blocked_by[1].identifier, "X-5")
  eq(g.duplicated_by[1].identifier, "X-6")
end)

test("find_id: typical branch names", function()
  eq(model.find_id("alex/acme-102-dark-mode", { loose = true }), "ACME-102")
  eq(model.find_id("ACME-102-fix-login", { loose = true }), "ACME-102")
  eq(model.find_id("feature/ACME-102", { loose = true }), "ACME-102")
  eq(model.find_id("main", { loose = true }), nil)
  eq(model.find_id(nil, { loose = true }), nil)
end)

test("pin_issue: moves an existing issue to the top, adds a missing one", function()
  local list = { { identifier = "A-1" }, { identifier = "A-2" }, { identifier = "A-3" } }
  local function ids(l)
    return vim.tbl_map(function(i)
      return i.identifier
    end, l)
  end
  eq(ids(model.pin_issue(list, list[3])), { "A-3", "A-1", "A-2" })
  eq(ids(model.pin_issue(list, { identifier = "B-9" })), { "B-9", "A-1", "A-2", "A-3" })
end)

test("find_id: strict and loose", function()
  eq(model.find_id("- ENG-42  [Todo]  Fix it"), "ENG-42")
  eq(model.find_id("nothing here"), nil)
  eq(model.find_id("antoine/eng-42-fix-it"), nil)
  eq(model.find_id("antoine/eng-42-fix-it", { loose = true }), "ENG-42")
  eq(model.find_id("ENG-42", { loose = true }), "ENG-42")
end)

test("render: sections, description and comments in order", function()
  local lines = model.render({
    identifier = "ENG-1",
    title = "Title",
    state = { name = "In Progress", type = "started" },
    priorityLabel = "High",
    url = "https://linear.app/x/issue/ENG-1",
    description = "line 1\nline 2",
    labels = { nodes = { { name = "bug" } } },
    parent = { identifier = "ENG-0", title = "Epic", state = { name = "Todo" } },
    children = { nodes = {} },
    relations = { nodes = { { type = "blocks", relatedIssue = { identifier = "ENG-2", title = "B", state = { name = "Todo" } } } } },
    inverseRelations = { nodes = {} },
    comments = {
      nodes = {
        { body = "second", createdAt = "2026-02-01T00:00:00Z", user = { name = "Bob" } },
        { body = "first", createdAt = "2026-01-01T00:00:00Z", user = { name = "Alice" } },
      },
    },
  })
  local text = table.concat(lines, "\n")
  assert(text:find("## Parent\n\n%- ENG%-0"), "parent section")
  assert(text:find("## Blocks\n\n%- ENG%-2"), "blocks section")
  assert(not text:find("## Blocked by"), "empty sections are hidden")
  assert(text:find("line 1\nline 2"), "description")
  assert(text:find("Alice.-first.-Bob.-second"), "comments sorted by date")
  assert(text:find("%*%*Labels%*%*: bug"), "labels")
end)

test("linked_issues: deduplicated", function()
  local same = { identifier = "ENG-2" }
  local linked = model.linked_issues({
    parent = same,
    children = { nodes = { same } },
    relations = { nodes = { { type = "related", relatedIssue = same } } },
  })
  eq(#linked, 1)
end)

test("linked_issues: stable order, parent then blocked by then blocks then related", function()
  local function i(id)
    return { identifier = id }
  end
  local linked = model.linked_issues({
    parent = i("P-1"),
    relations = { nodes = { { type = "related", relatedIssue = i("R-1") }, { type = "blocks", relatedIssue = i("B-1") } } },
    inverseRelations = { nodes = { { type = "blocks", issue = i("BB-1") } } },
  })
  eq(vim.tbl_map(function(x)
    return x.identifier
  end, linked), { "P-1", "BB-1", "B-1", "R-1" })
end)

test("parse_response: data, auth error, rate limit, garbage", function()
  local err, data = api.parse_response('{"data":{"viewer":{"name":"A"}}}')
  eq(err, nil)
  eq(data.viewer.name, "A")
  err = api.parse_response('{"errors":[{"message":"x","extensions":{"code":"AUTHENTICATION_ERROR"}}]}')
  assert(err:find("Linear login"))
  err = api.parse_response('{"errors":[{"message":"x","extensions":{"code":"RATELIMITED"}}]}')
  assert(err:find("rate limited"))
  err = api.parse_response("<html>")
  assert(err:find("unexpected"))
end)

test("parse_response: null becomes nil", function()
  local _, data = api.parse_response('{"data":{"issue":{"parent":null}}}')
  eq(data.issue.parent, nil)
end)

print(("\n%d/%d passed"):format(count - failures, count))
os.exit(failures == 0 and 0 or 1)
