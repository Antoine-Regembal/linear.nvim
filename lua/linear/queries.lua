local M = {}

M.viewer = [[
query Viewer {
  viewer { id name email }
}
]]

local issue_summary = [[
  id
  identifier
  title
  priority
  priorityLabel
  url
  branchName
  updatedAt
  state { name type }
  team { key name }
  cycle { id number name startsAt endsAt isActive isNext isPrevious }
]]

M.my_issues = ([[
query MyIssues($first: Int!, $filter: IssueFilter) {
  viewer {
    assignedIssues(first: $first, filter: $filter, orderBy: updatedAt) {
      nodes { %s }
    }
  }
}
]]):format(issue_summary)

local linked = "identifier title state { name type }"

M.issue_detail = ([[
query IssueDetail($id: String!) {
  issue(id: $id) {
    %s
    description
    createdAt
    assignee { name }
    creator { name }
    labels { nodes { name } }
    project { name }
    parent { %s }
    children(first: 100) { nodes { %s } }
    relations(first: 100) { nodes { type relatedIssue { %s } } }
    inverseRelations(first: 100) { nodes { type issue { %s } } }
    comments(first: 100) { nodes { body createdAt user { name } } }
  }
}
]]):format(issue_summary, linked, linked, linked, linked)

return M
