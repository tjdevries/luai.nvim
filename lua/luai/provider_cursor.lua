local M = {}

---@param prompt string
---@param model string
---@return string
M.request_generation = function(prompt, model)
  if vim.fn.executable "agent" ~= 1 then
    error "[luai] Could not find `agent` on PATH. Install Cursor Agent CLI and make sure it is available in your shell."
  end

  local workspace = vim.uv.cwd() or vim.fn.getcwd()
  local result = vim.system({
    "agent",
    "-p",
    "--mode",
    "ask",
    "--output-format",
    "json",
    "--model",
    model,
    "--trust",
    "--workspace",
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
      error(string.format("[luai] Cursor Agent request failed: %s", details))
    end

    error(string.format("[luai] Cursor Agent request failed with exit code %s", result.code))
  end

  local ok, decoded = pcall(vim.json.decode, stdout)
  if not ok then
    error(string.format("[luai] Cursor Agent returned invalid JSON:\n%s", stdout))
  end

  if type(decoded) ~= "table" or type(decoded.result) ~= "string" then
    error(string.format("[luai] Cursor Agent JSON did not contain a string `result` field:\n%s", stdout))
  end

  return decoded.result
end

return M
