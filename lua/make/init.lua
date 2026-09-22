local LOG_PREFIX = 'make.nvim'

--- @alias JobId number
--- @alias QuickfixListId number
--
--- @class (exact) JobData
--- @field quickfix_list_nr QuickfixListId The number of the quickfix list output is being piped to.
--- @field job_id JobId ID of the job whose output is being piped to this list.
--- @field is_complete boolean Whether or not the command is finished.
--- @field status_code number|nil The status code of the job command when it finished or nil if it isn't finished.
--- @field command string The full command of the job.
--- @field path string The path to the file of the buffer that started the job.
--
--- @type table<JobId, JobData>
local make_jobs = {}

-- Used when `vim.g.make_nvim` configuration values aren't set
--- @class (exact) Options
--- @field icon_incomplete string
--- @field icon_error string
--- @field icon_ok string
---
--- @type Options
local default_options = {
  icon_incomplete = '…',
  icon_error = '❌',
  icon_ok = '✓'
}

--- @param key 'icon_incomplete' | 'icon_error' | 'icon_ok'
---  @see Options
---
--- @return string The configuration value as set by the user, or the default value for it if none is set.
local function get_configuration_value(key)
  if vim.g.make_nvim == nil or vim.g.make_nvim[key] == nil then
    return default_options[key]
  end

  return vim.g.make_nvim[key]
end

-- Internal notification wrapper that prepends useful plugin context so the user knows to blame this plugin.
--
--- @param message string Message to send in the notification.
--- @param level vim.log.levels Log level to send the notification under. One of the values from `vim.log.levels`
--- @see vim.log.levels
local function notify(message, level)
  vim.notify(LOG_PREFIX .. ': ' .. message, level)
end

--- @enum OptionScopes
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
--- @param option string Name of the option to get the value of, like `'makeprg'`.
--- @param scope OptionScopes Scope to look in to retrieve the option value.
--- @param buffer_id? number ID of the buffer to pull the option value from if `OptionScopes.local` is given as `scope`.
---  @see OptionScopes
--- @return string|nil The option's value, or nil if it wasn't found in any scope.
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
--- @param option string Name of the option to get the value of, like `'makeprg'`.
--- @param scopes OptionScopes[] Scopes to look in to retrieve the option value.
--- @param buffer_id? number ID of the buffer to pull the option value from if `OptionScopes.local` is given in `scopes`.
---  @see OptionScopes
--- @return string|nil The option's value, or nil if it wasn't found in any scope.
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
--- @param cmd string The command behind the current invocation.
--- @param output string[] Output from the command (errors or otherwise) as an array since commands might send many.
--- @param quickfix_list_nr number Number of the quickfix list to send results to.
--- @param quickfixtextfunc string|nil Quick fix text function, see `:h quickfixtextfunc` for details.
--- @param errorformat string|nil Error format parsing string, see `:h errorformat` for details.
local function handle_make_async_output(cmd, output, quickfix_list_nr, quickfixtextfunc, errorformat)
  vim.schedule(function()
    vim.fn.setqflist({}, 'a', {
      cmd = cmd,
      lines = output,
      quickfixtextfunc = quickfixtextfunc,
      nr = quickfix_list_nr,
      efm = errorformat,
    })
  end)
end

--- @class (exact) Make
--- @field get_makeprg function Gets the `makeprg` that will be run when `make` is invoked.
--- @field make function Runs `:make` asynchronously, piping output from the command into a dedicated quickfix list.
--- @field view function Lists all currently running `:make` jobs, opening the related quickfix list on selection.
--- @field kill function Lists `:make` jobs and stops them when selected.
--- @field QUICKFIX_EVENT_PATTERNS string[] Patterns that can be matched against for when `make` is run.
local M = {}

M.QUICKFIX_EVENT_PATTERNS = { 'make.nvim:make' }

-- Exists only to run the appropriate `autocmd`s once async compilation is complete and the quickfix list is populated.
--
-- All parameters are detailed in Neovim's official docs for `:h job-control` under `on_exit`.
--
--- @param job_id      number
--- @param exit_code   number
local function on_make_async_exit(job_id, exit_code, _)
  make_jobs[job_id].is_complete = true
  make_jobs[job_id].status_code = exit_code

  vim.schedule(function()
    vim.api.nvim_exec_autocmds('QuickFixCmdPost', {
      pattern = M.QUICKFIX_EVENT_PATTERNS,
    })
  end)
end

-- Runs something similar to the built-in `:make` asynchronously, feeding into a quickfix list while compiling.
-- Respects all quickfix and compiler options.
--
-- Has all the same considerations for `:make`, and uses quickfix lists, so if you run into issues, be sure you've
-- done all that you have to for `:make` and `quickfix` lists to work, like running `:compiler` and setting it to the
-- correct compiler for your project, see `:h :make` and `:h quickfix`.
--
-- Further help can be found in the official documentation of this package, see `:h make-async`
--
--- @param make_args string Arguments to append to `:make` as a string. This is passed directly to `makeprg`, so space
--                          out arguments accordingly as you would when running the command on the command line.
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
  --- @type string
  local cmd = vim.fn.expandcmd(makeprg):gsub('[ \t]+%$%*$', '') .. ' ' .. make_args

  -- Users expect this to be run in their quickfix lists, so retrieve this and pass it along.
  --
  -- This can only be set globally, so no need to check in any more specific places.
  local quickfixtextfunc = get_most_relevant_option_value('quickfixtextfunc', { OPTION_SCOPES.global })

  local errorformat =
    get_most_relevant_option_value('errorformat', { OPTION_SCOPES.buffer, OPTION_SCOPES.global }, buffer_id)

  -- `:make` would usually cause this autocmd event to fire so this has to replicate it with our own custom pattern.
  vim.api.nvim_exec_autocmds('QuickFixCmdPre', {
    pattern = M.QUICKFIX_EVENT_PATTERNS,
  })

  local path = vim.api.nvim_buf_get_name(0)

  -- Need to make a new qflist to store the results in so that old ones aren't clobbered
  vim.fn.setqflist({}, ' ', {
    nr = '$',
    title = string.format('cmd: %s | path: %s', cmd, path)
  })

  -- The above doesn't return the qflist number directly due to the `nr` argument so we have to get it manually and
  -- hope that nothing else creates a quickfix list in-between these two calls.
  --- @type number
  local quickfix_list_nr = vim.fn.getqflist({ nr = '$' }).nr

  --- See `:h job-control` -> `job-control-usage` for details on parameter specifics in Neovim's official help files.
  --
  --- @param data string[]
  local function output_handler(_, data, _)
    handle_make_async_output(cmd, data, quickfix_list_nr, quickfixtextfunc, errorformat)
  end

  -- Specifically uses this form of `jobstart` with a cmd string in order to invoke it in the shell as `:make` would.
  local job_id = vim.fn.jobstart(cmd, {
    on_stdout = output_handler,
    on_stderr = output_handler,
    on_exit = on_make_async_exit,
  })

  make_jobs[job_id] = {
    quickfix_list_nr = quickfix_list_nr,
    job_id = job_id,
    is_complete = false,
    command = cmd,
    path = path,
  }
end

-- Gets the most relevant `makeprg` option value.
--
--- @return string|nil The option's value, or nil if it wasn't found in any scope.
M.get_makeprg = function()
  local buffer_id = vim.api.nvim_get_current_buf()

  local makeprg = get_most_relevant_option_value('makeprg', { OPTION_SCOPES.buffer, OPTION_SCOPES.global }, buffer_id)

  return makeprg
end

--- @return { choices: string[], job_data: JobData[] } | nil
local function get_make_job_choices()
  if vim.tbl_isempty(make_jobs) then
    -- TODO: info log for no jobs active

    return nil
  end

  local job_data = vim.tbl_values(make_jobs)

  --- @type string[]
  local choices = {}

  for _, v in ipairs(job_data) do
    local job_status_icon = get_configuration_value('icon_incomplete')

    if v.status_code ~= nil then
      if v.status_code == 0 then
        job_status_icon = get_configuration_value('icon_ok')
      else
        job_status_icon = get_configuration_value('icon_error')
      end
    end

    table.insert(choices, string.format('%s | path: %s | cmd: %s', job_status_icon, v.path, v.command))
  end

  return { job_data = job_data, choices = choices }
end

M.view = function()
  local data = get_make_job_choices()

  if data == nil then
    return
  end

  vim.ui.select(data.choices, {
    prompt = 'Choose a job to view output for: ',
  }, function(_, index)
    if index == nil then
      return
    end

    vim.cmd(string.format('%d%s', data.job_data[index].quickfix_list_nr, 'chistory'))
  end)
end

M.kill = function()
  local data = get_make_job_choices()

  if data == nil then
    return
  end

  vim.ui.select(data.choices, {
    -- TODO: maybe explain that this will also remove easy way to access the quickfix list but will leave the list there
    prompt = 'Choose a job to kill: ',
  }, function(_, index)
    if index == nil then
      return
    end

    local job_id = data.job_data[index].job_id

    make_jobs[job_id]:remove()

    vim.fn.jobstop(job_id)
  end)
end

return M
