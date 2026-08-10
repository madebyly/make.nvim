local M = {}

M.check = function()
  vim.health.start('make-async health checks')
  vim.health.ok('This has no configuration that could be broken.')
  vim.health.ok('Issues will probably be due to your compiler or quickfix configurations.')
  vim.health.ok('See the official docs for more in-depth troubleshooting help, `:h make-async-troubleshooting`')
end

return M
