.. default-role:: code


##################################
 Asynchronous `:make` replacement
##################################

`make-async` is a package that provides an asynchronous replacement for the `:make` built-in command, allowing users to run their compiler without blocking the editor, dealing with compilation results as they occur.

Full documentation is available in the help files, see `:h make-async`, or the help file directly here `make-async.txt <doc/make-async.txt>`_.

Requirements
############

This package requires the following:

- Neovim, version >= 0.12.0


Installation
############

Install this package like any other Neovim package.

An example installation via the built-in `vim.pack.add`:

.. code:: lua
    vim.pack.add({ 'https://github.com/madebyly/make-async' })


Usage
#####

The package can be used by calling the provided `make_async` function in your
Lua scripts.

Doing so runs |makeprg| almost exactly as it would when run via |:make|,
taking into account almost all the same configuration options and
considerations as the built-in would, see |make-async-differences| for info.

Some useful ways this can be called are noted below:

.. code:: lua
    local plugin = require('make-async')

    -- Defines a command `MakeAsync` that can be called like `:make`,
    -- allowing you to do `:MakeAsync <compiler command args>` directly.
    vim.api.nvim_create_user_command(
      'MakeAsync',
      function(opt)
        plugin.make_async(opt.args)
      end,
      {
        desc = 'Runs `make_async` with the given arguments.',
        nargs = '*',
      }
    )

    -- Sets up a keybinding, allowing you to run the command quickly while
    -- still allowing for compile command customization by prompting you
    -- for input that will be passed as args to the underlying command.
    vim.keymap.set(
      'n',
      '<leader>lhs', -- replace with your desired keybind
      function()
        local args = vim.fn.input({
          prompt = 'Enter arguments for `:make`',
        })

        plugin.make_async(args)
      end,
      {
        desc = 'Runs `make_async` with the given arguments.'
      }
    )

    -- `autocmd`s can be set up to run only when this package runs
    vim.api.nvim_create_autocmd('QuickFixCmdPost', {
      callback = function()
        -- ...your logic here...
      end,
      pattern = 'make-async',
      desc = 'Runs only when `make-async` runs',
    })

    -- Likewise, `autocmd`s that would've already ran on `make` will still run
    vim.api.nvim_create_autocmd('QuickFixCmdPost', {
      callback = function()
        -- ...your logic here...
      end,
      pattern = 'make',
      desc = 'Runs when `make-async` or `:make` are run'
    })


Differences to `:make`
###########

While the functionality provided by this package tries its best to match how the `:make` built-in command would, it differs in some key ways that shouldn't affect most use cases:

- all output from executing the compiler command is sent over to a `quickfix` list by default where the user can handle output from the command later;
- `makeencoding` is ignored completely due to how output is routed;
- `:cnext` and `:cprevious` do nothing because of how output is routed, with navigating between errors being handled the same way you would navigate a `quickfix` list;
  - this doesn't work as-is on Windows, so this should result in no change to your workflow there.
- `makeef` is ignored because of how output is routed, and no error file is written to that can be viewed later or persisted as `makeef` would allow;
- `shellpipe` is ignored due to how output is routed;
- changed buffers will never be written, ignoring `autowrite`, requiring you to manually write them yourself;
- `QuickFixCmdPost` and `QuickFixCmdPre` include an additional pattern that can be matched against to only react to this package's functionality, `make-async-api-autocmd-pattern`.


Development
###########

See `CONTRIBUTING.rst <CONTRIBUTING.rst>`_ for more details.


Troubleshooting
###############

See the `TROUBLESHOOTING` section in the main help file `make-async.txt <doc/make-async.txt>`_ for common problems and their fixes.

You can view this file directly in Neovim by running the command `:h make-async`.

Yes, I'm lazy to copy it here.

Unlike the above installation steps, this should only be relevant once you start using it and need help, in which case the help file has it all.


Changes
#######

See the main `news.txt` file `news.txt <doc/news.txt>`_ for a full list of changes.

Similar reasons to the troubleshooting section as to why this section isn't expanded in the `README`, except changes are also listed on each release with the same content as what you'd find in the news file.


