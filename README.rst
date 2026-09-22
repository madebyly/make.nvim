.. default-role:: code


Drop-in asynchronous `:make` replacement for Neovim
===================================================
``make.nvim`` is a package that provides a replacement for the built-in ``:make`` that aims to provide an asynchronous drop-in replacement for it.

Full documentation is available in the help files, see ``:h make.nvim``, or the help file directly here `make.nvim.txt <doc/make.nvim.txt>`_.

This README is a shallow copy of the documentation contained within designed to make it easy to know how to get started and how to contribute if desired.


Features
========
This package provides the following features:
- an asynchronous replacement for the ``:make`` command that allows you to continue using the editor while compilers are running in the background;
- facilities to navigate quickfix lists being populated by these asynchronous compiler jobs and to manage them.


Requirements
============

This package requires the following:

- ``neovim`` version >= 0.12.0


Installation and Configuration
==============================
Install this package like any other Neovim package.

An example installation via the built-in ``vim.pack.add``:

.. code:: lua
   vim.pack.add({ 'https://github.com/madebyly/make.nvim' })

The package works out of the box with no further configuration, following the usual requirements for ``:make`` to work, see ``make.nvim-troubleshooting`` and ``make.nvim-differences-to-:make`` for details.

You can, however, customize some visual aspects of the plugin if you'd like.

This plugin checks the global variable ``vim.g.make_nvim`` for replacements for the strings used when viewing jobs with ``view`` (see ``:h make.nvim-usage``), which are used as icons for e.g. what state a compiler job is in.

It expects it to be a dictionary where the keys are one of the following:
- ``icon_incomplete``
- ``icon_error``
- ``icon_ok``

The values are strings that will be used as "icons" for the state of the compilation job in the view list.

These can be set at anytime and the plugin will take the latest value set, if any.

An example configuration is below:

.. code:: lua
   vim.g.make_nvim = {
     icon_incomplete = '…',
     icon_error = '❌',
     icon_ok = '✓'
   }


Usage
=====
The package can be used by calling the provided `make` function in your Lua scripts.

Doing so runs ``makeprg`` almost exactly as it would when run via ``:make``, taking into account almost all the same configuration options and considerations as the built-in would.

See ``:h make.nvim-differences`` for info on the differences it has.

Notably, this emits ``QuickFixCmdPre`` and ``QuickFixCmdPost`` with different patterns, details of which can be found at ``make.nvim-api-make-autocmd-pattern``.

Some useful ways this can be called are noted below:

.. code:: lua
   local plugin = require('make')

   -- Defines a command `Make` that can be called like `:make`,
   -- allowing you to do `:Make <compiler command args>` directly.
   vim.api.nvim_create_user_command(
     'Make',
     function(opt)
       plugin.make(opt.args)
     end,
     {
       desc = 'Runs `make.nvim` with the given arguments.',
       nargs = '*',
     }
   )

   -- Sets up a keybinding, allowing you to run the command quickly while
   -- still allowing for compile command customization by prompting you
   -- for input that will be passed as args to the underlying command.
   vim.keymap.set(
     'n',
     'keybind', -- replace with your desired keybind
     function()
       -- This is provided for convenience since |makeprg| can be sourced
       -- from a number of places.
       local makeprg = plugin.get_makeprg()

       local args = vim.fn.input({
         prompt = string.format('Enter arguments for `%s`: ', makeprg),
       })

       if args:len() == 0 then
         return
       end

       plugin.make(args)
     end,
     {
       desc = 'Runs `make.nvim` with the given arguments.'
     }
   )

   -- `autocmd`s for both `QuickFixCmdPre` and `QuickFixCmdPost` can be set
   -- up to run when this package's functions run.
   vim.api.nvim_create_autocmd('QuickFixCmdPre', {
     callback = function()
       -- ...your logic here...
     end,
     -- Can also use the pattern as a string directly 'make.nvim'
     pattern = plugin.QUICKFIX_EVENT_PATTERNS,
     desc = 'Runs only when `make.nvim:make` runs',
   })

   vim.api.nvim_create_autocmd('QuickFixCmdPost', {
     callback = function()
       -- ...your logic here...
     end,
     pattern = plugin.QUICKFIX_EVENT_PATTERNS
   })

The plugin provides a ``view`` function that allows you to view all current and previous compiler jobs started via this plugin, setting their quickfix list as the current one on selection.

This function emits a ``User`` ``autocmd`` event with the patterns exposed via the ``VIEW_EVENT_PATTERNS`` field on the plugin module once a selection is made, allowing you to react to the quickfix list now changing.

This pattern is detailed at ``make.nvim-api-view-autocmd-pattern``.

This can be used as follows:

.. code:: lua
   -- ...continuing from the previous example...
   vim.keymap.set('n', 'keybind', function()
     make.view()
   end)

   vim.api.nvim_create_autocmd('User', {
     pattern = make.VIEW_EVENT_PATTERNS,
     callback = function(event)
       vim.cmd('copen')
     end,
   })

This leverages ``vim.ui.select``, so anything you register as the handler for that will be used to preview the choices as well.

To kill any long-running compiler jobs, use the ``kill`` function, which similarly displays a list of jobs, filtered to only show those that are still running, stopping their associated job when selected:

.. code:: lua
   -- ...continuing from the previous example...
   vim.keymap.set('n', 'keybind', function()
     plugin.kill()
   end)

This also displays the choices via ``vim.ui.select`` as ``view`` does.


Development
===========
See `CONTRIBUTING.rst <CONTRIBUTING.rst>`_ for more details.


Troubleshooting
===============
See the ``TROUBLESHOOTING`` section in the main help file `make.nvim.txt <doc/make.nvim.txt>`_ for common problems and their fixes.

You can view this file directly in Neovim by running the command ``:h make.nvim``.


Changes
=======
See the main ``news.txt`` file `news.txt <doc/news.txt>`_ for a full list of changes when a new version is released.


