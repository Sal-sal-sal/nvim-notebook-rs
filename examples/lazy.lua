return {
  {
    "Sal-sal-sal/nvim-notebook-rs",
    build = "cargo build --release --locked",
    config = function()
      require("notebook_rs").setup({
        distance_between_cells = 2,
        nootbook_hidden_id_line = true,
        nootbook_result = "nootbook",
      })
    end,
  },
}
