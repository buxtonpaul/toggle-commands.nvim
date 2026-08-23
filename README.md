# toggle-commands.nvim

A lightweight, context-aware command runner for Neovim that presents a list of configured commands using **Telescope** and executes them inside isolated **ToggleTerm** terminals. Commands can be run either interactively via Telescope or directly with global keybindings and Lua API calls without opening the picker.

## ✨ Features

- **Context-Aware Interpolation:** Define your commands with `{input}` which is dynamically replaced with the current file path, the word under the cursor, or visual selection.
- **Direct Execution & Keybindings:** Bind commands directly to global Neovim keymaps via `key` in your config, or run them programmatically via `require("toggle-commands").run("Command Name")`.
- **Vim Filename Modifiers:** Use standard Vim modifiers on paths (e.g., `{input:p}` for absolute path, `{input:h}` for parent directory, `{input:t}` for filename only, `{input:r}` for path without extension). Modifiers are ignored for cursor words.
- **Dynamic Variable Preview:** See the fully-substituted command directly in the Telescope results list before executing it!
- **Interactive `{prompt}` capability:** Include `{prompt}` or `{prompt:Some Label}` in your commands to dynamically ask for additional inputs via `vim.ui.input` before running the command.
- **Isolated Terminal Sessions:** Runs commands in a dedicated ToggleTerm instance (default ID `99`) so your main terminal remains undisturbed.
- **In-line Editing:** Press `<C-e>` in the Telescope picker to manually edit the fully substituted command in-line before execution.
- **User Commands:** Run commands from the Vim command line using `:ToggleCommand <Name>` with tab completion.

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
        key = "<leader>rf", -- Directly launch from Neovim without opening the picker!
      },
      {
        name = "Grep occurrences in project",
        cmd = "rg {input}",
        key = "<leader>rg",
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
  key = "<leader>rc",           -- Optional: direct Neovim keybind (normal & visual mode by default)
  key_mode = { "n", "v" },      -- Optional: vim mode(s) for the keymap ("n", "v", etc.)
  context = "file",             -- Optional: "file" | "word" | "selection" | "auto" (default: "auto")
  terminal_opts = {
    id = 10,                    -- Custom ToggleTerm ID
    direction = "vertical",     -- "horizontal" | "vertical" | "float" | "tab"
    size = 40,                  -- Width/height depending on direction
    go_back = false,            -- Retain focus in terminal
  }
}
```

Global defaults can also be configured in `setup()` under `terminal_opts`. Individual command `terminal_opts` override the global defaults.

### Dynamic Placeholders
1.  **`{input}`**:
    - If context is `"file"`, resolves to the **relative path** of the active file.
    - If context is `"word"`, resolves to the **word under the cursor**.
    - If context is `"selection"`, resolves to the **selected text**.
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

## 🚀 Direct Execution & Keybindings

### 1. Direct Keybindings via Config
Add `key` (or `keys` / `mapping`) to any command in `opts.commands`. `setup()` automatically registers them in Neovim:

```lua
{
  name = "Run Python/Bash file",
  cmd = "chmod +x {input} && {input:p}",
  key = "<leader>rf", -- Pressing <leader>rf in Neovim runs this command directly!
}
```

### 2. Lua API (`run`)
You can trigger any command by name or index from your own mappings or Lua functions:

```lua
-- By command name:
require("toggle-commands").run("Run Python/Bash file")

-- By index (1-based):
require("toggle-commands").run(1)

-- With explicit context ("file", "word", "selection", or "auto"):
require("toggle-commands").run("Grep occurrences in project", "word")
```

### 3. User Commands
- `:ToggleCommand <Command Name>`: Executes a command directly with tab-completion.
- `:ToggleCommands [file|word|selection]`: Opens the Telescope picker.

---

## ⌨️ Telescope Picker Bindings

When browsing inside the Telescope picker:
- `<CR>` (Enter): Execute the selected command.
- `<C-e>`: Edit the fully substituted command in-line before running it.
- `[Custom Key]`: Directly run any command configured with `key` / `mapping` if pressed inside the picker.
