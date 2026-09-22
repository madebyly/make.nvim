local M = {}

M.check = function()
  vim.health.start('make-async health checks')

  if vim.g.make_nvim == nil then
    vim.health.ok([[No configuration found. See |make.nvim-installation| for details on how to configure this plugin.
    Using default configuration values.]])
  else
    local config_value_type = type(vim.g.make_nvim)

    if config_value_type ~= 'table' then
      vim.health.error(
        [[Expected `vim.g.make_nvim` to have a table for its value instead of what it is which is a `]]
          .. config_value_type
          .. [[`.
          Please see |make.nvim-installation| for details on how to configure this plugin.]]
      )

      return
    end

    local config_keys = { 'icon_incomplete', 'icon_error', 'icon_ok' }

    for _, key in pairs(config_keys) do
      local config_key_value = vim.g.make_nvim[key]

      if config_key_value == nil then
        vim.health.ok('No configuration value found for `' .. key .. [[`.
        If this is expected, this can be ignored, otherwise see |make.nvim-installation| for help.]])
      else
        local config_key_value_type = type(config_key_value)

        if config_key_value_type ~= 'string' then
          vim.health.error(
            'Configuration value for key `'
              .. key
              .. '` is the wrong type and should be a `string` but is currently a `'
              .. config_key_value_type
              .. [[`.
          See |make.nvim-installation| for information on how to configure this plugin.]]
          )
        else
          vim.health.ok('Configuration value for key `' .. key .. [[` is the right type.
        If the wrong value is appearing, confirm it's set correctly, or open an issue if it's still broken.]])
        end
      end
    end
  end

  vim.health.ok([[Any additional issues encountered are mostly due to misconfiguration of various |:make| config values.
  See |make.nvim-troubleshooting| for details.]])
end

return M
