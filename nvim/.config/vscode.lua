vim.opt.clipboard = "unnamedplus" -- Use system clipboard
vim.opt.scrolloff = 0

vim.keymap.set("n", "<Esc>", "<Cmd>nohlsearch<CR>", { silent = true })
-- Remove search highlighting on insert mode
vim.api.nvim_create_autocmd("InsertEnter", {
	pattern = "*",
	command = "set nohlsearch",
})


-- Enable search highlighting when entering command-line mode for search commands
vim.api.nvim_create_autocmd("CmdlineEnter", {
	pattern = { "/", "?" },
	command = "set hlsearch",
})

vim.api.nvim_create_user_command("ProseSettings", function(opts)
	local width = tonumber(opts.args) or 80
	vim.opt_local.textwidth = width
	vim.opt_local.colorcolumn = tostring(width)
end, { nargs = "?", desc = "Set prose-friendly wrapping (default 80)" })

local lazypath = "/Users/filip/.local/share/nvim/lazy/lazy.nvim"
vim.opt.rtp:prepend(lazypath)
require("lazy").setup({
  {
    "ggandor/leap.nvim",
	lazy = false,
    config = function()
      require("leap").add_default_mappings()
    end,
  },
})
