vim.pack.add({
  { src = "https://github.com/tiesen243/vercel.nvim" },
}, { confirm = false, load = true })

require("vercel").setup({
  theme = "dark",
})
