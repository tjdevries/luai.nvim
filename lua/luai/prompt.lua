local system_message = function(opts)
  local text = opts.text
  local cached = opts.cached

  local message = {
    type = "text",
    text = text,
  }

  if cached then
    message.cache_control = { type = "ephemeral" }
  end

  return message
end

local user_message = function(opts)
  local text = opts.text
  local cached = opts.cached

  local message = {
    role = "user",
    content = {
      {
        type = "text",
        text = text,
      },
    },
  }

  if cached then
    message.content[1].cache_control = { type = "ephemeral" }
  end

  return message
end

---@param opts table
return function(opts)
  local options = vim.deepcopy(opts.options)

  local function_name = opts.function_name

  local description = options.__description
  if description == nil then
    description = ""
  else
    description = "The function should also make sure to:\n" .. description
  end

  local history = ""
  if options.__history then
    history = options.__history
  end

  -- Double underscore names are reserved.
  for key, _ in pairs(options) do
    if vim.startswith(key, "__") then
      options[key] = nil
    end
  end

  local option_list = table.concat(vim.tbl_keys(options), ",")
  return {
    function_name = function_name,
    option_list = option_list,
    option_example = options,
    description = description,
    system = {
      system_message {
        text = "You are a professional software developer who has experience in writing effective Neovim plugins. You have studied code bases written by Folke and tjdevries. You are familiar with the Neovim codebase. People often compliment you on your succinct answers and elegant answers.",
      },
      system_message {
        text = [[
<examples>
<example>
  <example_description>
  Where possible, using neovim's builtin functionality is ideal! Don't re-implement if there is already a perfect function for the task you've been asked for.
  </example_description>
  <FUNCTION_NAME>print_value</FUNCTION_NAME>
  <OPTION_LIST>value</OPTION_LIST>
  <OPTION_EXAMPLE>{ value = 5 }</OPTION_EXAMPLE>
  <ideal_output>
  <lua_function>
  return function(opts)
    print(vim.inspect(opts.value))
  end
  </lua_function>
  </ideal_output>
</example>
<example>
  <FUNCTION_NAME>new_buffer</FUNCTION_NAME>
  <OPTION_LIST>name, filetype</OPTION_LIST>
  <OPTION_EXAMPLE>{ name = "test.txt", filetype = "txt" }</OPTION_EXAMPLE>
  <ideal_output>
  <lua_function>
  return function(opts)
    assert(opts.name, "Must have a name")
    assert(opts.filetype, "Must have a filetype")

    vim.cmd.split()
    vim.api.nvim_buf_set_name(0, opts.name)
    vim.bo.filetype = opts.filetype
  end
  </lua_function>
  </ideal_output>
</example>
</examples>

]],
      },
      system_message {
        text = require "luai.prompt.nvim_api",
      },
      system_message {
        cached = true,
        text = [[
You are tasked with implementing a Lua function based on a given function name and the keys of an table called "opts" which is passed as the only argument. The function will be executed inside of neovim, so use any neovim functions that will be helpful to the implementation.

Follow these instructions carefully to create the function, using <thinking> tags to help you along the way.

1. You will be provided with the function name, the list of keys for the input table "opts", and one example of what the input table could look like.

2. Using the provided information, create a Lua function with the following structure:
   - Start with the keyword "return function". DO NOT INCLUDE THE FUNCTION NAME
   - Include parentheses () containing the argument named "opts", which is a table containing they keys from <option_list>
   - Add the function body
   - End the function with the "end" keyword

3. When implementing the function body:
   - Add a comment inside of the function to describe what the implementation will do.
   - Include basic error checking for the arguments if necessary
   - Implement a simple, generic functionality that relates to the function name.
   - Return a value that makes sense for the function name and arguments

4. Present your Lua function implementation inside <lua_function> tags

Here's an example of how your output should be formatted:

<lua_function>
return function(opts)
  -- Adds the left and right fields
  return opts.left + opts.right
end
</lua_function>

Remember to adjust the function's behavior based on the given function name and arguments. Your implementation should be simple, concise but remember to cover every reasonable edge case you can. You are a professional software developer and this code is for other professional software developers running in a professional setting. Do not print more information than required.
]],
      },
    },
    messages = {
      user_message {
        text = string.format(
          [[%s

Generate a Lua implementation given the following requirements:
- <FUNCTION_NAME>%s</FUNCTION_NAME>
- <OPTION_LIST>%s</OPTION_LIST>
- <OPTION_EXAMPLE>%s</OPTION_EXAMPLE>

%s ]],
          history,
          function_name,
          option_list,
          vim.inspect(options),
          description
        ),
      },
    },
  }
end

-- Think step-by-step before you write the implementation of the lua function. You can think inside of <thinking> tags. While thinking, first think of how the function name and the parameters relate to each other. Then think of any relevant neovim functions that could be useful
