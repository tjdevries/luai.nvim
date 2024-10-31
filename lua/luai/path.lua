local uv = vim.uv

local path = {}

--- Checks if file is newer than the provided stat
---@param filepath string: The path to the file to read
---@param stat uv.aliases.fs_stat_table: The stat of the file to check against
path.is_file_newer = function(filepath, stat)
  assert(filepath, "filepath is required")

  -- Check if file exists and is readable
  local current_stat = uv.fs_stat(filepath)
  if not current_stat then
    error("File does not exist or is not accessible: " .. filepath)
  end

  -- Compare modification times
  return current_stat.mtime.sec > stat.mtime.sec
    or (current_stat.mtime.sec == stat.mtime.sec and current_stat.mtime.nsec > stat.mtime.nsec)
end

return path
