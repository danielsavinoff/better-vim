vim.pack.add({
  { src = "https://github.com/saghen/blink.cmp", version = vim.version.range("1") },
}, { confirm = false, load = true })

require("blink.cmp").setup({
  completion = {
    list = {
      selection = { preselect = false, auto_insert = false },
    },
  },
  -- The Lua matcher works without downloading a separate binary.
  fuzzy = { implementation = "lua" },
})
