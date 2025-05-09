-- Read the docs: https://www.lunarvim.org/docs/configuration
-- Example configs: https://github.com/LunarVim/starter.lvim
-- Video Tutorials: https://www.youtube.com/watch?v=sFA9kX-Ud_c&list=PLhoH5vyxr6QqGu0i7tt_XoVK9v-KvZ3m6
-- Forum: https://www.reddit.com/r/lunarvim/
-- Discord: https://discord.com/invite/Xb9B4Ny

-- Non-default plugins.
lvim.plugins = {
  {
    "ggandor/leap.nvim",
    name = "leap",
    config = function()
      require("leap").add_default_mappings()
    end,
  },
  { "rebelot/kanagawa.nvim" },
  {
    "rose-pine/neovim",
    name = "rose-pine",
    config = function()
      require("rose-pine").setup({ styles = { italic = false } })
    end,
  },
}

-- Check whether we're in dark mode, and choose the corresponding colorscheme.
local is_dark_mode = false
local status, output = pcall(vim.fn.system, "defaults read -g AppleInterfaceStyle 2>/dev/null")

if status and output:match("Dark") then
  is_dark_mode = true
end

if is_dark_mode then
  lvim.colorscheme = "kanagawa-wave"
else
  lvim.colorscheme = "rose-pine-dawn"
end

-- Standard vim options
vim.opt.wrap = true
vim.opt.scrolloff = 0

lvim.keys.normal_mode["<Tab>"] = ":bn<CR>"
lvim.keys.normal_mode["<S-Tab>"] = ":bp<CR>"
lvim.keys.normal_mode["<ESC>"] = ":nohlsearch<CR>"

lvim.builtin.cmp.on_config_done = function(cmp)
  cmp.setup.filetype({ "markdown", "md", "text", "gitcommit" }, {
    enabled = false, -- disable autocomplete for Markdown/text
  })
end

-- Normal quotes
vim.api.nvim_create_user_command('NormalQuotes', function()
  vim.cmd [[silent! %s/[‘’]/'/g]]
  vim.cmd [[silent! %s/[“”]/"/g]]
end, { desc = 'Replace non-standard quotes with standard quotes' })
