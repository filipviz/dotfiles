vim.opt.clipboard = "unnamedplus" -- Use system clipboard
vim.opt.scrolloff = 0

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

local lazypath = "/Users/f/.local/share/lunarvim/site/pack/lazy/opt/lazy.nvim"
vim.opt.rtp:prepend(lazypath)
require("lazy").setup({
  {
    "ggandor/leap.nvim",
    config = function()
      require("leap").add_default_mappings()
    end,
  },
})
