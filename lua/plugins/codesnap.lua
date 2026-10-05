vim.pack.add({
  { src = "https://github.com/mistricky/codesnap.nvim", version = "v2.0.5" },
}, { confirm = false, load = true })

require("codesnap").setup({
  show_line_number = false,
  show_workspace = false,
  highlight_color = "#ffffff20",
  snapshot_config = {
    theme = "vercel@https://raw.githubusercontent.com/Railly/one-hunter-vscode/refs/heads/main/themes/OneHunter-Vercel-color-theme.json",
    window = {
      mac_window_bar = true,
      border = {
        width = 1,
        color = "#ffffff30",
      },
    },
    code_config = {
      breadcrumbs = {
        enable = false,
      },
    },
    background = {
      start = { x = 0, y = 0 },
      ["end"] = { x = "max", y = "max" },
      stops = {
        { position = 0, color = "#0a0a0a" },
        { position = 1, color = "#000000" },
      },
    },
  },
})

vim.keymap.set("x", "<leader>cs", ":CodeSnap<CR>", { silent = true, desc = "CodeSnap: Copy snapshot" })
vim.keymap.set("x", "<leader>ch", ":CodeSnapHighlight<CR>", { silent = true, desc = "CodeSnap: Highlight and copy snapshot" })
