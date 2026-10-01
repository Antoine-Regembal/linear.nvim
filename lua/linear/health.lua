local M = {}

function M.check()
  local h = vim.health
  h.start("linear.nvim")

  if vim.fn.has("nvim-0.10") == 1 then
    h.ok("Neovim >= 0.10")
  else
    h.error("Neovim >= 0.10 is required")
  end

  if vim.fn.executable("curl") == 1 then
    h.ok("curl found")
  else
    h.error("curl is required")
  end

  if pcall(require, "snacks") then
    h.ok("snacks.nvim found")
  else
    h.warn("snacks.nvim not found, falling back to vim.ui.select (no preview)")
  end

  local auth = require("linear.auth")
  local backend = auth.backend()
  if backend == "file" then
    h.warn(
      "No OS keychain found (macOS `security` or `secret-tool`); the key is stored in "
        .. auth._credentials_path()
        .. " (0600)"
    )
  else
    h.ok("Credential storage: " .. backend)
  end

  if require("linear.demo").enabled then
    h.warn("Demo mode is on: fictional data, no API calls (:Linear demo off)")
  end

  local key, source = auth.get_key()
  if key then
    h.ok("API key found (" .. source .. ")")
  else
    h.warn("Not logged in, run :Linear login")
  end
end

return M
