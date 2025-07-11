local M = {}

local uv = vim.uv or vim.loop
local fn = vim.fn

---@param path string
---@return string?, string?
function M.linkpath(path)
  local res_path = nil
  local res_type = nil
  while true do
    local stat = uv.fs_stat(path)
    if not stat then
      break
    end

    local linkdata = uv.fs_readlink(path)
    if not linkdata then
      res_path = path
      res_type = stat.type
      break
    end

    path = linkdata
  end

  return res_path, res_type
end

---@return string
function M.getcwd()
  return uv.cwd() or fn.getcwd(0)
end

---@param a string
---@param b string
---@return string
function M.joinpath(a, b)
  return vim.fs.joinpath(a, b)
end

---@param path string
---@return string
function M.abspath(path)
  return vim.fs.abspath(path)
end

---@param path string
function M.relpath(path)
  if vim.fs.relpath ~= nil then
    return vim.fs.relpath(M.getcwd(), path)
  else
    local x = M.joinpath(M.getcwd(), path)
    print(x)
    return x
  end
end

---@param path string
---@return table, string?
function M.listdir(path)
  assert(path, "path is required")

  local items = {}
  local fs, err = uv.fs_scandir(path)
  if not fs then
    return {}, err
  end

  while true do
    local name, type = uv.fs_scandir_next(fs)

    if not name then
      break
    end

    if type == "link" then
      local link_path, link_type = M.linkpath(M.joinpath(path, name))
      table.insert(items, {
        name = name,
        type = type,
        path = M.joinpath(path, name),
        link_path = link_path,
        link_type = link_type,
      })
    else
      table.insert(items, {
        name = name,
        type = type,
        path = M.joinpath(path, name),
      })
    end
  end

  return items, nil
end

---@param path string
function M.create_fs_item(path)
  local stat = uv.fs_stat(path)
  if stat then
    return
  end

  local path_type = string.sub(path, -1) == "/" and "directory" or "file"
  if path_type == "directory" then
    if vim.fn.mkdir(path, "p") == 0 then
      return
    end
  else
    local parent_path = vim.fn.fnamemodify(path, ":h")
    if vim.fn.isdirectory(path) == 0 then
      if vim.fn.mkdir(parent_path, "p") == 0 then
        return
      end
    end

    local fd, err = uv.fs_open(path, "w", 438)
    if not fd or err then
      return
    end

    uv.fs_close(fd)
  end

  vim.notify("CREATE: " .. path, vim.log.levels.INFO)
end

---@param path string
function M.delete_fs_item(path)
  local stat, _, err = uv.fs_stat(path)

  -- Check for symlink loop. If true, delete the symlink
  if not stat and err == "ELOOP" then
    vim.fn.delete(path)
  elseif not stat then
    return
  elseif stat.type == "directory" then
    vim.fn.delete(path, "rf")
  elseif stat.type == "file" or stat.type == "link" then
    vim.fn.delete(path)
  else
    return
  end

  vim.notify("DELETE: " .. path, vim.log.levels.INFO)
end

---@param from string
---@param to string
function M.move_fs_item(from, to)
  local from_stat = uv.fs_stat(from)
  if not from_stat then
    return
  end

  local parent_dir = vim.fn.fnamemodify(to, ":h")
  local parent_stat = uv.fs_stat(parent_dir)
  if not parent_stat then
    M.create_fs_item(parent_dir .. "/")
  end

  uv.fs_rename(from, to)
  vim.notify("MOVE: " .. from .. " > " .. to, vim.log.levels.INFO)
end

return M
