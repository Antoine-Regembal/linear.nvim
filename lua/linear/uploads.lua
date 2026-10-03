-- Images embedded in issues (`![alt](https://uploads.linear.app/...)`).
-- Linear's file storage is private: files are downloaded with the API key into a local
-- cache, then the issue is rendered with links to the local files so snacks.image can show them.
local M = {}

M.HOST = "https://uploads.linear.app/"

local EXTENSIONS = {
  ["image/png"] = "png",
  ["image/jpeg"] = "jpg",
  ["image/gif"] = "gif",
  ["image/webp"] = "webp",
  ["image/heic"] = "heic",
  ["image/avif"] = "avif",
  ["video/mp4"] = "mp4",
  ["video/quicktime"] = "mov",
  ["video/webm"] = "webm",
  ["video/x-matroska"] = "mkv",
  ["application/pdf"] = "pdf",
}

local IMAGE = { png = true, jpg = true, gif = true, webp = true, heic = true, avif = true }

-- embeds named like a video are not downloaded with the issue, only on `gx`
local VIDEO = { mp4 = true, mov = true, webm = true, mkv = true, avi = true }

-- `![alt](url)` or `![alt](url "title")`
local EMBED = "!%[([^%]]*)%]%(([^%s%)]+)[^%)]*%)"

---@class linear.Upload
---@field path string local file
---@field kind "image"|"file"

---@type table<string, fun(err: string|nil, entry: linear.Upload|nil)[]>
local pending = {}

---@return string
function M.dir()
  return vim.fs.joinpath(vim.fn.stdpath("cache"), "linear.nvim", "uploads")
end

---@param url string
---@return boolean
function M.is_upload(url)
  return type(url) == "string" and vim.startswith(url, M.HOST) and not url:find("[%s\"'`\\]")
end

---@param content_type string|nil
---@return string
function M.extension(content_type)
  local mime = content_type and content_type:match("^%s*([^;%s]+)")
  return mime and EXTENSIONS[mime:lower()] or "bin"
end

---Embedded uploads (`![alt](url)`) of a markdown text, in order, without duplicates.
---@param text string|nil
---@return { url: string, alt: string }[]
function M.extract(text)
  local found, seen = {}, {}
  for alt, url in (text or ""):gmatch(EMBED) do
    if M.is_upload(url) and not seen[url] then
      seen[url] = true
      table.insert(found, { url = url, alt = alt })
    end
  end
  return found
end

---Embedded uploads of an issue's description and comments, except videos.
---@param issue table
---@return { url: string, alt: string }[]
function M.collect(issue)
  local texts = { issue.description }
  for _, c in ipairs(require("linear.model").nodes(issue.comments)) do
    table.insert(texts, c.body)
  end
  return vim.tbl_filter(function(u)
    return not VIDEO[vim.fn.fnamemodify(u.alt, ":e"):lower()]
  end, M.extract(table.concat(texts, "\n")))
end

---Point embedded images to their local files. Other uploads keep their remote URL.
---@param text string|nil
---@param files table<string, linear.Upload>
---@return string|nil
function M.rewrite(text, files)
  if not text or not next(files) then
    return text
  end
  return (
    text:gsub(EMBED, function(alt, url)
      local file = files[url]
      if file and file.kind == "image" then
        return ("![%s](%s)"):format(alt, file.path)
      end
    end)
  )
end

---@param path string
---@return linear.Upload
local function entry(path)
  local ext = vim.fn.fnamemodify(path, ":e"):lower()
  return { path = path, kind = IMAGE[ext] and "image" or "file" }
end

---Cached file of an upload, without downloading it.
---@param url string
---@return linear.Upload|nil
function M.get(url)
  local base = vim.fs.joinpath(M.dir(), vim.fn.sha256(url))
  for _, path in ipairs(vim.fn.glob(base .. ".*", false, true)) do
    if not path:match("%.part$") then
      return entry(path)
    end
  end
end

---Cached files of an issue's uploads.
---@param issue table
---@return table<string, linear.Upload>
function M.cached(issue)
  local files = {}
  for _, u in ipairs(M.collect(issue)) do
    files[u.url] = M.get(u.url)
  end
  return files
end

local function finish(url, err, result)
  local cbs = pending[url] or {}
  pending[url] = nil
  for _, cb in ipairs(cbs) do
    cb(err, result)
  end
end

---@param url string
---@param part string
---@param ext string
local function store(url, part, ext)
  local path = part:gsub("%.part$", "." .. ext)
  local ok, err = vim.uv.fs_rename(part, path)
  if not ok then
    finish(url, err, nil)
    return
  end
  vim.uv.fs_chmod(path, tonumber("600", 8))
  finish(url, nil, entry(path))
end

---Download an upload into the cache (once), then call `cb` with its local file.
---The API key is only ever sent to uploads.linear.app, and redirects are not followed.
---@param url string
---@param cb fun(err: string|nil, entry: linear.Upload|nil)
function M.fetch(url, cb)
  if not M.is_upload(url) then
    vim.schedule(function()
      cb("not a Linear upload: " .. tostring(url), nil)
    end)
    return
  end
  local cached = M.get(url)
  if cached then
    vim.schedule(function()
      cb(nil, cached)
    end)
    return
  end
  if pending[url] then
    table.insert(pending[url], cb)
    return
  end
  pending[url] = { cb }

  vim.fn.mkdir(M.dir(), "p", tonumber("700", 8))
  local part = vim.fs.joinpath(M.dir(), vim.fn.sha256(url) .. ".part")

  local demo = require("linear.demo")
  if demo.enabled then
    local src = demo.upload(url)
    vim.schedule(function()
      if not src or not vim.uv.fs_copyfile(src, part) then
        finish(url, "demo upload not found: " .. url, nil)
        return
      end
      store(url, part, vim.fn.fnamemodify(src, ":e"))
    end)
    return
  end

  local key = require("linear.auth").get_key()
  if not key then
    vim.schedule(function()
      finish(url, "not logged in, run :Linear login", nil)
    end)
    return
  end
  local max_mb = require("linear.config").options.attachments.max_size_mb
  -- headers go through stdin so the key never shows up in the process list
  vim.system({
    "curl",
    "--silent",
    "--show-error",
    "--fail",
    "--max-time",
    "120",
    "--max-filesize",
    tostring(max_mb * 1024 * 1024),
    "-H",
    "@-",
    "--output",
    part,
    "--write-out",
    "%{content_type}",
    url,
  }, { text = true, stdin = "Authorization: " .. key .. "\n" }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        os.remove(part)
        finish(url, "download failed: " .. vim.trim(res.stderr or ""), nil)
        return
      end
      store(url, part, M.extension(res.stdout))
    end)
  end)
end

---Download every upload of an issue, then call `cb` once with all local files.
---@param issue table
---@param cb fun(files: table<string, linear.Upload>, errors: string[])
function M.fetch_all(issue, cb)
  local list = M.collect(issue)
  local files, errors, left = {}, {}, #list
  if left == 0 then
    vim.schedule(function()
      cb(files, errors)
    end)
    return
  end
  for _, u in ipairs(list) do
    M.fetch(u.url, function(err, result)
      files[u.url] = result
      if err then
        table.insert(errors, err)
      end
      left = left - 1
      if left == 0 then
        cb(files, errors)
      end
    end)
  end
end

function M.clear()
  vim.fn.delete(M.dir(), "rf")
end

return M
