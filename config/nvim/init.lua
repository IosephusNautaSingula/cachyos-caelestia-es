-- SPDX-License-Identifier: GPL-3.0-or-later
-- Neovim con el tema de Caelestia (scheme.json, se recarga solo) y ajustes básicos. Ruta: ~/.config/nvim/init.lua
vim.opt.termguicolors = true
vim.g.caelestia_transparent = false      -- fondo opaco del esquema
vim.opt.number = true
vim.opt.mouse = "a"
vim.opt.clipboard = "unnamedplus"        -- portapapeles de Wayland (wl-clipboard)
vim.opt.expandtab = true; vim.opt.shiftwidth = 4; vim.opt.tabstop = 4
vim.opt.ignorecase = true; vim.opt.smartcase = true
vim.opt.undofile = true
pcall(vim.cmd.colorscheme, "caelestia")
