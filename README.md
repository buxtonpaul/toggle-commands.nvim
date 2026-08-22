# toggle-commands.nvim

A lightweight, context-aware command runner for Neovim that presents a list of configured commands using **Telescope** and executes them inside isolated **ToggleTerm** terminals.

## ✨ Features

- **Context-Aware Interpolation:** Define your commands with `{input}` which is dynamically replaced with either the current file path or the word under the cursor, depending on how you invoke the picker.
- **Vim Filename Modifiers:** Use standard Vim modifiers on paths (e.g., `{input:p}` for absolute path, `{input:h}` for parent directory, `{input:t}` for filename only, `{input:r}` for path without extension). Modifiers are ignored for cursor words.
- **Dynamic Variable Preview:** See the fully-substituted command directly in the Telescope results list before executing it!
- **Interactive `{prompt}` capability:** Include `{prompt}` or `{prompt:Some Label}` in your commands to dynamically ask for additional inputs via `vim.ui.input` before running the command.
- **Isolated Terminal Sessions:** Runs commands in a dedicated ToggleTerm instance (default ID `99`) so your main terminal remains undisturbed.
- **In-line Editing:** Press `<C-e>` in the Telescope picker to manually edit the fully substituted command in-line before execution.
- **Elegant Alignment:** Automatically aligns columns dynamically using Telescope's native layout utilities, perfectly accounting for Nerd Font icons and UTF-8 characters.

---

## 📦 Installation

Install with your favorite package manager:

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "buxtonpaul/toggle-commands.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
    "akinsho/toggleterm.nvim",
  },
  keys = {
    {
      "<leader>cp",
      function()
        require("toggle-commands").open("file")
      end,
      desc = "Toggle Commands (File Context)",
    },
    {
      "<leader>cw",
      function()
        require("toggle-commands").open("word")
      end,
      desc = "Toggle Commands (Word Context)",
    },
    {
      "<leader>cs",
      function()
        require("toggle-commands").open("selection")
      end,
      mode = "v",
      desc = "Toggle Commands (Selection Context)",
    },
  },
  opts = {
    commands = {
      {
        name = "Run Python/Bash file",
        cmd = "chmod +x {input} && {input:p}",
      },
      {
        name = "Grep occurrences in project",
        cmd = "rg {input}",
      },
      {
        name = "Git log / history for file",
        cmd = "git log --follow -p -- {input}",
      },
      {
        name = "Find occurrences with file filter",
        cmd = "rg {input} -g {prompt:Glob pattern (e.g. *.lua)}",
      },
      {
        name = "Git commit staged changes",
        cmd = "git commit -m {prompt:Commit Message}",
      },
    }
  },
  config = function(_, opts)
    require("toggle-commands").setup(opts)
  end,
}
```

---

## ⚙️ Configuration

You can customize the available commands via the `commands` table inside options.

### Command Structure
Each command in the list is a table:
```lua
{
  name = "My Command Name",
  cmd = "your-shell-command {input}",
  key = "<C-g>", -- Optional: direct shortcut inside Telescope picker
  terminal_opts = {
    id = 10,                 -- Custom ToggleTerm ID
    direction = "vertical",  -- "horizontal" | "vertical" | "float" | "tab"
    size = 40,               -- Width/height depending on direction
    go_back = false,         -- Retain focus in terminal
  }
}
```

Global defaults can also be configured in `setup()` under `terminal_opts`. Individual command `terminal_opts` override the global defaults.

### Dynamic Placeholders
1.  **`{input}`**:
    - If opened with `open("file")`, resolves to the **relative path** of the active file.
    - If opened with `open("word")`, resolves to the **word under the cursor**.
    - If opened with `open("selection")`, resolves to the **selected text**.
2.  **`{input:modifier}`**: (Only active in file-mode)
    - `{input:p}`: Absolute path.
    - `{input:h}`: Parent directory/head.
    - `{input:t}`: Filename/tail.
    - `{input:r}`: Path without extension.
3.  **`{line}` / `{line_count}` / `{start_line}` / `{end_line}`**:
    - Current line number, buffer total line count, or selection range start/end lines.
4.  **`{line_text}`**:
    - Full text content of the current cursor line.
5.  **`{clipboard}`**:
    - Contents of the system clipboard (`+` or `"` register).
6.  **`{selection}`**:
    - Visually selected text.
7.  **`{git_branch}` / `{git_root}` / `{blame_commit}`**:
    - Current Git branch name, Git repository root path, or git blame commit hash for current cursor line.
8.  **`{prompt}`** or **`{prompt:Label}`**:
    - Prompts the user dynamically with an input box before executing the command, replacing the placeholder with the custom value.

---

## ⌨️ Bindings

Inside the Telescope picker:
- `<CR>` (Enter): Execute the selected command.
- `<C-e>`: Edit the fully substituted command in-line before running it.
- `[Custom Key]`: Directly run any command configured with `key` / `mapping` (e.g., `<C-g>`).
