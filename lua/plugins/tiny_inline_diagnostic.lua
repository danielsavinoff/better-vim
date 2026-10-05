vim.pack.add({
  { src = "https://github.com/rachartier/tiny-inline-diagnostic.nvim" },
}, { confirm = false, load = true })

require("tiny-inline-diagnostic").setup()
vim.diagnostic.config({ virtual_text = false })
