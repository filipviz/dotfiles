-- Minimal standalone config: nvim -u ~/.config/nvim/minimal.lua
-- No plugin manager; reuses the main config's leap install when present.

vim.g.mapleader = " "
vim.opt.clipboard = "unnamedplus"
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.undofile = true
vim.opt.number = true
vim.opt.shiftwidth = 4
vim.opt.tabstop = 4
vim.opt.wrap = true
vim.opt.linebreak = true
vim.opt.breakindent = true
vim.opt.termguicolors = true

vim.keymap.set("n", "<Esc>", "<Cmd>nohlsearch<CR>", { silent = true })

for _, key in ipairs({ "h", "j", "k", "l" }) do
	vim.keymap.set("n", "<C-" .. key .. ">", "<C-w>" .. key)
end

vim.api.nvim_create_user_command("ProseSettings", function(opts)
	local width = tonumber(opts.args) or 80
	vim.opt_local.textwidth = width
	vim.opt_local.colorcolumn = tostring(width)
end, { nargs = "?", desc = "Set prose-friendly wrapping (default 80)" })

local leap = vim.fn.stdpath("data") .. "/lazy/leap.nvim"
if (vim.uv or vim.loop).fs_stat(leap) then
	vim.opt.rtp:append(leap)
	vim.keymap.set({ "n", "x", "o" }, "s", "<Plug>(leap)")
end
