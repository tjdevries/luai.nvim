local M = {}

---@param prompt string
---@param model string
---@return string
M.request_generation = function(prompt, model)
  if vim.fn.executable "ollama" ~= 1 then
    error "[luai] Could not find `ollama` on PATH. Install Ollama and make sure it is available in your shell."
  end

  local result = vim.system({
    "ollama",
    "run",
    model,
    prompt,
    "--format",
    "json",
    "--hidethinking",
  }, { text = true }):wait()

  local stdout = result.stdout or ""
  local stderr = result.stderr or ""

  if result.code ~= 0 then
    stderr = vim.trim(stderr)
    stdout = vim.trim(stdout)
    local details = stderr ~= "" and stderr or stdout
    if details ~= "" then
      error(string.format("[luai] Ollama request failed: %s", details))
    end

    error(string.format("[luai] Ollama request failed with exit code %s", result.code))
  end

  -- With --format json the model should respond with valid JSON.
  -- Try to parse the output and extract the response text.
  local trimmed = vim.trim(stdout)
  local ok, decoded = pcall(vim.json.decode, trimmed)
  if not ok then
    -- Not JSON; return raw output as-is.
    return trimmed
  end

  -- JSON string -- return it directly.
  if type(decoded) == "string" then
    return decoded
  end

  -- JSON object -- look for a string field that holds the response.
  if type(decoded) == "table" then
    for _, key in ipairs({ "response", "content", "code", "message", "text", "result" }) do
      if type(decoded[key]) == "string" then
        return decoded[key]
      end
    end
  end

  -- Fallback: return the raw JSON output as a string (the caller expects a
  -- string, so encode back if needed, or just return the original text).
  return trimmed
end

return M
