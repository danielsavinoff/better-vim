vim.pack.add({
  { src = "https://github.com/Erl-koenig/theme-hub.nvim" },
  { src = "https://github.com/projekt0n/github-nvim-theme" },
}, { confirm = false, load = true })

require("theme-hub").setup({
  auto_install_on_select = true,
  persistent = true,
})
