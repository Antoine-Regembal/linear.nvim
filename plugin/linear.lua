if vim.g.loaded_linear then
  return
end
vim.g.loaded_linear = true

vim.api.nvim_create_user_command("Linear", function(cmd)
  local sub = cmd.fargs[1] or "issues"
  local fn = require("linear").subcommands[sub]
  if not fn then
    vim.notify("Linear: unknown subcommand '" .. sub .. "'", vim.log.levels.ERROR)
    return
  end
  fn(cmd.fargs[2])
end, {
  nargs = "*",
  desc = "Linear issues",
  complete = function(arg, line)
    if #vim.split(line, "%s+", { trimempty = true }) > (arg == "" and 1 or 2) then
      return {}
    end
    return vim.tbl_filter(function(s)
      return vim.startswith(s, arg)
    end, vim.tbl_keys(require("linear").subcommands))
  end,
})
