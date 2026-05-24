local M = {}

---@param prompt string
---@param model string
---@return string
M.request_generation = function(prompt, model)
  if vim.fn.executable "opencode" ~= 1 then
    error "[luai] Could not find `opencode` on PATH. Install opencode and make sure it is available in your shell."
  end

  local workspace = vim.uv.cwd() or vim.fn.getcwd()
  local result = vim.system({
    "opencode",
    "run",
    "-m",
    model,
    "--format",
    "json",
    "--dir",
    workspace,
    prompt,
  }, { text = true }):wait()

  local stdout = result.stdout or ""
  local stderr = result.stderr or ""

  if result.code ~= 0 then
    stderr = vim.trim(stderr)
    stdout = vim.trim(stdout)
    local details = stderr ~= "" and stderr or stdout
    if details ~= "" then
      error(string.format("[luai] opencode request failed: %s", details))
    end

    error(string.format("[luai] opencode request failed with exit code %s", result.code))
  end

  -- Parse NDJSON output (one JSON object per line)
  local parts = {}
  for line in stdout:gmatch("[^\r\n]+") do
    local ok, decoded = pcall(vim.json.decode, line)
    if ok and type(decoded) == "table" and decoded.type == "text" then
      if type(decoded.part) == "table" and type(decoded.part.text) == "string" then
        table.insert(parts, decoded.part.text)
      end
    end
  end

  if #parts == 0 then
    error(string.format("[luai] opencode returned no text response:\n%s", stdout))
  end

  return table.concat(parts, "")
end

return M
