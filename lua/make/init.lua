local LOG_PREFIX = 'make.nvim'

-- Internal notification wrapper that prepends useful plugin context so the user knows to blame this plugin.
--
-- @param message string Message to send in the notification.
-- @param level vim.log.levels Log level to send the notification under. One of the values from |vim.log.levels|
local function notify(message, level)
  vim.notify(LOG_PREFIX .. ': ' .. message, level)
end

-- @enum OptionScopes
--
-- Scopes which an option can be defined in and read from.
--
-- The values are important! The most relevant places options can be found in are the lowest values in the table.
local OPTION_SCOPES = {
  buffer = 0,
  global = 1,
}

-- Gets the most relevant value of the provided option, searching in the given scope, normalizing the return value such
-- that it's either the option's value or `nil` in all cases where the value isn't set.
--
-- @param option string Name of the option to get the value of, like `'makeprg'`.
-- @param scopes OptionScopes Scope to look in to retrieve the option value.
-- @param buffer_id? integer ID of the buffer to pull the option value from if |OptionScopes.local| is given as `scope`.
-- @return string|nil The option's value, or nil if it wasn't found in any scope.
local function do_get_most_relevant_option_value(option, scope, buffer_id)
  local option_value = nil

  if scope == OPTION_SCOPES.buffer then
    if buffer_id == nil then
      notify(
        'No buffer ID given even though local buffer scope specified for `do_get_most_relevant_option_value`!',
        vim.log.levels.ERROR
      )

      return nil
    end

    option_value = vim.api.nvim_get_option_value(option, {
      buf = buffer_id,
    })
  elseif scope == OPTION_SCOPES.global then
    option_value = vim.api.nvim_get_option_value(option, {
      scope = 'global',
    })
  end

  -- An empty string is a little annoying to disambiguate against a real option value, so this forces all cases where
  -- the option's value isn't set to be returned as `nil`.
  if option_value == '' then
    return nil
  end

  return option_value
end

-- Gets the most relevant value of the provided option, searching in the given scopes.
--
-- @param option string Name of the option to get the value of, like `'makeprg'`.
-- @param scopes OptionScopes[] Scopes to look in to retrieve the option value.
-- @param buffer_id? integer ID of the buffer to pull the option value from if |OptionScopes.local| is given in `scopes`.
-- @return string|nil The option's value, or nil if it wasn't found in any scope.
local function get_most_relevant_option_value(option, scopes, buffer_id)
  local option_value = nil

  -- If we only have 1 scope, we can keep it simple and operate on it almost directly
  if #scopes > 1 then
    table.sort(scopes)

    for _, scope in vim.iter(scopes):unique():enumerate() do
      option_value = do_get_most_relevant_option_value(option, scope, buffer_id)

      if option_value ~= nil then
        break
      end
    end
  else
    option_value = do_get_most_relevant_option_value(option, scopes[1], buffer_id)
  end

  return option_value
end

-- Handles compiler command output, filling up the appropriate quick fix list with the output correctly formatted.
--
-- @param cmd string The command behind the current invocation.
-- @param output string[] Output from the command (errors or otherwise) as an array since commands might send many.
-- @param list_number integer Number of the quickfix list to send results to.
-- @param quickfixtextfunc function Quick fix text function, see `:h quickfixtextfunc` for details.
-- @param errorformat string Error format parsing string, see `:h errorformat` for details.
local function handle_make_async_output(cmd, output, list_number, quickfixtextfunc, errorformat)
  -- Since this is a fast context, we have to schedule it to run later.
  vim.schedule(function()
    vim.fn.setqflist({}, 'a', {
      cmd = cmd,
      lines = output,
      quickfixtextfunc = quickfixtextfunc,
      nr = list_number,
      efm = errorformat,
    })
  end)
end

local AUTOCMD_PATTERNS = { 'make', 'make-async' }

-- Exists only to run the appropriate `autocmd`s once async compilation is complete and the quickfix list is populated.
local function on_make_async_exit()
  vim.schedule(function()
    vim.api.nvim_exec_autocmds('QuickFixCmdPost', {
      pattern = AUTOCMD_PATTERNS,
    })
  end)
end

-- @class (exact) Make
-- @field setup function Runs `:make` asynchronously
-- @field make_async function Runs `:make` asynchronously
local M = {}

-- Runs something similar to the built-in `:make` asynchronously, feeding into a quickfix list while compiling.
-- Respects all quickfix and compiler options.
--
-- Has all the same considerations for `:make`, and uses quickfix lists, so if you run into issues, be sure you've
-- done all that you have to for `:make` and `quickfix` lists to work, like running `:compiler` and setting it to the
-- correct compiler for your project, see `:h :make` and `:h quickfix`.
--
-- Further help can be found in the official documentation of this package, see `:h make-async`
--
-- @param make_args string Arguments to append to `:make` as a string. This is passed directly to `makeprg`, so space
--                         out arguments accordingly as youl would when running the command on the command line.
M.make = function(make_args)
  local buffer_id = vim.api.nvim_get_current_buf()

  local makeprg = M.get_makeprg()

  if makeprg == nil then
    notify('`makeprg` not set! Set up your compiler options before running this again.', vim.log.levels.ERROR)

    return
  end

  -- `makeprg` can have any number of special placeholders that get expanded when used via the command line
  -- (normally by calling `:make` in this case) which need to be expanded to preserve the original calling intent.
  --
  -- The only special placeholder that doesn't get expanded due to special rules, and that this plugin doesn't care
  -- about, is the `$*` placeholder, which is the argument placeholder that gets replaced by whatever arguments the user
  -- enters for `:make`.
  --
  -- We perform our own argument substitution in lieu of this by concatenating the command with the arguments directly,
  -- so we remove this from the command since it'd otherwise fail to run if kept in, along with any trailing spaces
  -- that would've been left behind.
  local cmd = vim.fn.expandcmd(makeprg):gsub('[ \t]+%$%*$', '') .. ' ' .. make_args

  -- Users expect this to be run in their quickfix lists, so retrieve this and pass it along.
  --
  -- This can only be set globally, so no need to check in any more specific places.
  local quickfixtextfunc = get_most_relevant_option_value('quickfixtextfunc', { OPTION_SCOPES.global })

  local errorformat =
    get_most_relevant_option_value('errorformat', { OPTION_SCOPES.buffer, OPTION_SCOPES.global }, buffer_id)

  -- This acts like `:make`, so this also has to send the command pattern over such that any existing autocmds would
  -- match as expected, passing in a custom pattern that can be matched against if the user wants to.
  vim.api.nvim_exec_autocmds('QuickFixCmdPre', {
    pattern = AUTOCMD_PATTERNS,
  })

  -- Need to make a new qflist to store the results in so that old ones aren't clobbered
  vim.fn.setqflist({}, ' ', {
    nr = '$',
  })

  -- The above doesn't return the qflist number, so we have to get it manually and hope that nothing else creates
  -- a qflist in-between these two calls.
  local qflist_number = vim.fn.getqflist({ nr = '$' }).nr

  local function output_handler(_, data, _)
    handle_make_async_output(cmd, data, qflist_number, quickfixtextfunc, errorformat)
  end

  -- Specifically uses this form of `jobstart` with a cmd string in order to invoke it in the shell as `:make` would
  vim.fn.jobstart(cmd, {
    on_stdout = output_handler,
    on_stderr = output_handler,
    on_exit = on_make_async_exit,
  })
end

-- Gets the most relevant `makeprg` option value.
--
-- @return string|nil The option's value, or nil if it wasn't found in any scope.
M.get_makeprg = function()
  local buffer_id = vim.api.nvim_get_current_buf()

  local makeprg = get_most_relevant_option_value('makeprg', { OPTION_SCOPES.buffer, OPTION_SCOPES.global }, buffer_id)

  return makeprg
end

return M
