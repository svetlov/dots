return {

    ---------------------------------------------------------------------------
    -- Colorscheme + basic UI
    ---------------------------------------------------------------------------

    -- kanagawa colorscheme
    {
        "rebelot/kanagawa.nvim",
        lazy = false, -- load at startup so colors are available immediately
        priority = 1000,
        config = function()
            vim.cmd("colorscheme kanagawa-wave")
            vim.opt.fillchars:append({ diff = " " })
            -- kanagawa Normal fg is beige (#DCD7BA); use true white in terminal buffers
            vim.api.nvim_set_hl(0, "TermNormal", { fg = "#FFFFFF", bg = "#1F1F28" })
            -- kanagawa maps terminal "white" (7/15) to its beige fujiWhite, which
            -- makes ANSI white text (e.g. Claude Code's UI) render gold. Force true white.
            vim.g.terminal_color_7 = "#FFFFFF"
            vim.g.terminal_color_15 = "#FFFFFF"
            vim.api.nvim_create_autocmd("TermOpen", {
                callback = function()
                    vim.wo.winhighlight = "Normal:TermNormal"
                end,
            })
        end,
    },

    -- maximize window on <leader>z
    -- {
    --   'declancm/maximize.nvim',
    --   config = function()
    --     require('maximize').setup()
    --     vim.keymap.set('n', '<leader>z', require('maximize').toggle)
    --   end,
    -- },
    {
      'szw/vim-maximizer',
      keys = {
        { '<leader>z', '<cmd>MaximizerToggle<CR>', desc = 'Maximize toggle' }
      }
    },

    -- vim-tmux-navigator: <C-h/j/k/l> navigate vim splits, then cross into
    -- tmux panes at the edges. Pairs with the `bind-key -n C-h ...` block
    -- in ~/.tmux.conf which forwards C-h/j/k/l to vim when vim is the
    -- foreground program in the pane and `select-pane`s otherwise.
    {
      'christoomey/vim-tmux-navigator',
      lazy = false,
      cmd = {
        'TmuxNavigateLeft',
        'TmuxNavigateDown',
        'TmuxNavigateUp',
        'TmuxNavigateRight',
        'TmuxNavigatePrevious',
      },
      keys = {
        { '<C-h>', '<cmd>TmuxNavigateLeft<cr>',  mode = { 'n', 't' }, desc = 'Pane left'  },
        { '<C-j>', '<cmd>TmuxNavigateDown<cr>',  mode = { 'n', 't' }, desc = 'Pane down'  },
        { '<C-k>', '<cmd>TmuxNavigateUp<cr>',    mode = { 'n', 't' }, desc = 'Pane up'    },
        { '<C-l>', '<cmd>TmuxNavigateRight<cr>', mode = { 'n', 't' }, desc = 'Pane right' },
      },
    },

    -- Lualine statusline
    {
        "nvim-lualine/lualine.nvim",
        event = "VeryLazy",
        dependencies = { "nvim-tree/nvim-web-devicons" },
        config = function()
            -- Claude status polling: scan nvim terminal buffers + tmux panes
            local claude_status = ""
            local claude_state = nil
            local in_tmux = vim.env.TMUX ~= nil
            local tmux_pane = vim.env.TMUX_PANE
            local function check_text(text)
                local lines = type(text) == "table" and text or vim.split(text, "\n")
                local tail = table.concat(lines, "\n", math.max(1, #lines - 4))
                if text:find("Do you want to proceed") or text:find("Would you like to proceed") or text:find("Esc to cancel") or text:find("requires confirmation for this command") or text:find("Do you want to allow Claude to fetch") then
                    return "blocked", "[?] Claude waiting"
                elseif tail:find("❯") or tail:find("%? for shortcuts") then
                    return "idle", "[>] Claude idle"
                elseif tail:find("esc to interrupt") then
                    return "thinking", "[*] Claude thinking"
                end
                return nil, ""
            end
            -- Forward blocked transitions to workmux. The tmux status-bar
            -- daemon (tmux-claude-status.sh) reads @workmux_status, which
            -- workmux sets on the pane's window; the workmux dashboard sees
            -- the same state. Async via jobstart so polling never stalls
            -- nvim on a stuck shell call.
            local function tmux_set_blocked(blocked)
                if in_tmux and tmux_pane then
                    local status = blocked and "waiting" or "working"
                    vim.fn.jobstart({ "workmux", "set-window-status", status }, { detach = true })
                end
            end
            local prev_blocked = false
            local claude_timer = vim.uv.new_timer()
            claude_timer:start(0, 2000, vim.schedule_wrap(function()
                local state = nil
                local status = ""
                -- Check nvim terminal buffers (claude-code.nvim floating terminal)
                for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                    if vim.api.nvim_buf_is_loaded(buf)
                        and vim.bo[buf].buftype == "terminal"
                    then
                        local lines = vim.api.nvim_buf_get_lines(buf, -30, -1, false)
                        local text = table.concat(lines, "\n")
                        local s, st = check_text(text)
                        if s == "blocked" then
                            state, status = s, st
                            break
                        elseif s and (not state or s == "thinking") then
                            state, status = s, st
                        end
                    end
                end
                claude_status = status
                local blocked = state == "blocked"
                if blocked ~= prev_blocked then
                    prev_blocked = blocked
                    tmux_set_blocked(blocked)
                end
                if state ~= claude_state then
                    claude_state = state
                    require("lualine").setup(lualine_cfg(state))
                end
            end))

            -- Full-bar red theme only for blocked state
            local blocked_theme = {
                normal   = { a = { bg = "#c34043", fg = "#1f1f28", gui = "bold" },
                             b = { bg = "#43242b", fg = "#c34043" },
                             c = { bg = "#2a1519", fg = "#e46876" } },
                insert   = { a = { bg = "#c34043", fg = "#1f1f28", gui = "bold" } },
                visual   = { a = { bg = "#c34043", fg = "#1f1f28", gui = "bold" } },
                command  = { a = { bg = "#c34043", fg = "#1f1f28", gui = "bold" } },
                inactive = { c = { bg = "#2a1519", fg = "#c34043" } },
            }

            -- Small badge colors: colored bg with black text
            local badge_colors = {
                blocked  = { bg = "#c34043", fg = "#1f1f28", gui = "bold" },
                thinking = { bg = "#76946a", fg = "#1f1f28", gui = "bold" },
                idle     = { bg = "#dca561", fg = "#1f1f28", gui = "bold" },
            }

            function lualine_cfg(state)
                return {
                    icons_enabled = true,
                    options = {
                        theme = state == "blocked" and blocked_theme or "auto",
                        globalstatus = true,
                    },
                    sections = {
                        lualine_b = {
                            {
                                function() return claude_status end,
                                color = function()
                                    return badge_colors[claude_state]
                                end,
                                cond = function() return claude_status ~= "" end,
                            },
                            'branch',
                        },
                        lualine_c = {
                            {
                                'filename',
                                path = 1,
                            },
                        }
                    }
                }
            end

            require("lualine").setup(lualine_cfg(nil))
        end,
    },

    ---------------------------------------------------------------------------
    -- Treesitter (syntax, highlighting, etc.)
    ---------------------------------------------------------------------------

    -- Treesitter: parser manager + highlighting via nvim built-in
    {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",
        lazy = false,
        config = function()
            require("nvim-treesitter").install({
                "lua", "python", "rust", "bash",
                "json", "yaml", "markdown", "markdown_inline",
            })
            vim.api.nvim_create_autocmd("FileType", {
                callback = function(args)
                    pcall(vim.treesitter.start, args.buf)
                end,
            })
        end,
    },
    {
        'stevearc/aerial.nvim',
        keys = {
            { "<leader>fn", "<cmd>AerialToggle<cr>", desc = "Open code map" },
        },
        config = function()
            require("aerial").setup({
                manage_folds = "auto",
                link_folds_to_tree = false,
                link_tree_to_folds = false,
                layout = {
                    max_width = { 120, 0.5 },
                },
                show_guides = true,
            })
            require("telescope").load_extension("aerial")
        end,
        -- Optional dependencies
        dependencies = {
            "nvim-treesitter/nvim-treesitter",
            "nvim-tree/nvim-web-devicons"
        },
    },


    -- to enable markdown rendering for assistants replies
    {
        "MeanderingProgrammer/render-markdown.nvim",
        ft = { "markdown", "avante", "codecompanion", }
    },

    ---------------------------------------------------------------------------
    -- LSP + Mason + completion (nvim-cmp)
    ---------------------------------------------------------------------------

    -- Mason: installs LSP servers, DAPs, linters, formatters
    {
        "williamboman/mason.nvim",
        build = ":MasonUpdate",
        cmd = "Mason",
        config = function()
            require("mason").setup()
        end,
    },

    -- Mason-LSPConfig: connects Mason to LSP servers (auto-install)
    {
        "williamboman/mason-lspconfig.nvim",
        event = { "BufReadPost", "BufNewFile" },
        dependencies = {
            "williamboman/mason.nvim",
            "neovim/nvim-lspconfig",
        },
        config = function()
            require("mason-lspconfig").setup({
                ensure_installed = { "basedpyright", "rust_analyzer", "lua_ls" },
                automatic_installation = true,
            })
        end,
    },

    -- LSP client setup (basedpyright, rust-analyzer, lua_ls)
    {
        "neovim/nvim-lspconfig",
        -- event = { "BufReadPost", "BufNewFile" },
        event = "FileType",

        config = function()
            local capabilities = require("cmp_nvim_lsp").default_capabilities()

            -- New-style configs for vim.lsp.config
            local servers = {
                basedpyright = {
                    settings = {
                        basedpyright = {
                            analysis = {
                                typeCheckingMode = "standard",
                            },
                        },
                    },
                },
                rust_analyzer = {},
                lua_ls = {
                    settings = {
                        Lua = {
                            diagnostics = { globals = { "vim" } },
                        },
                    },
                },
            }

            -- Register server configs with vim.lsp.config
            for name, cfg in pairs(servers) do
                cfg.capabilities = capabilities
                vim.lsp.config[name] = cfg
            end

            -- Enable servers
            for name, _ in pairs(servers) do
                vim.lsp.enable(name)
            end
        end,
    },

    -- nvim-cmp: completion engine + LuaSnip for snippets
    {
        "hrsh7th/nvim-cmp",
        event = "InsertEnter",
        dependencies = {
            "hrsh7th/cmp-nvim-lsp",
            "hrsh7th/cmp-buffer",
            "hrsh7th/cmp-path",
            "hrsh7th/cmp-cmdline",
            "L3MON4D3/LuaSnip",
            "saadparwaiz1/cmp_luasnip",
            "rafamadriz/friendly-snippets",
        },
        config = function()
            local cmp = require("cmp")
            local luasnip = require("luasnip")

            require("luasnip.loaders.from_vscode").lazy_load()

            cmp.setup({
                snippet = {
                    expand = function(args)
                        luasnip.lsp_expand(args.body)
                    end,
                },
                mapping = cmp.mapping.preset.insert({
                    ["<C-Space>"] = cmp.mapping.complete(),
                    ["<CR>"] = cmp.mapping.confirm({ select = true }),
                    ['<C-k>'] = cmp.mapping(function(fallback)
                        if cmp.visible() then
                            cmp.select_prev_item()
                        else
                            fallback()
                        end
                    end, { "i", "s" }),
                    ['<C-j>'] = cmp.mapping(function(fallback)
                        if cmp.visible() then
                            cmp.select_next_item()
                        else
                            fallback()
                        end
                    end, { "i", "s" }),
                    ["<S-Tab>"] = cmp.mapping(function(fallback)
                        if cmp.visible() then
                            cmp.mapping.confirm({ select = true })
                        else
                            fallback()
                        end
                    end, { "i", "s" }),
                    -- ["<S-Tab>"] = cmp.mapping(function(fallback)
                    --   if cmp.visible() then
                    --     cmp.select_prev_item()
                    --   elseif luasnip.jumpable(-1) then
                    --     luasnip.jump(-1)
                    --   else
                    --     fallback()
                    --   end
                    -- end, { "i", "s" }),
                }),
                sources = cmp.config.sources({
                    -- { name = "codeium" },
                    { name = "nvim_lsp" },
                    { name = "path" },
                    { name = "luasnip" },
                }),
            })
        end,
    },

    -- show signature in floating window
    {
        "ray-x/lsp_signature.nvim",
        event = "InsertEnter",
        opts = {
            -- cfg options
            bind = true,
            handler_opts = {
                border = "rounded"
            },
        },
    },

    -- go def / go ref / docs/ renames / diagnostics / code actions
    {
        'nvimdev/lspsaga.nvim',
        event = 'LspAttach',
        config = function()
            require("lspsaga").setup({
                lightbulb = {
                    enable = false,
                },
                ui = {
                    border = "rounded",
                    code_action = "💡",
                },
                hover = {
                    max_width = 0.9,   -- 90% of screen width
                    max_height = 0.8,  -- 80% of screen height
                    min_width = 20,    -- Minimum width in characters
                    min_height = 10,   -- Minimum height in lines
                    border = "single", -- Or "rounded", "double", etc.
                },
                finder = {
                    max_height = 0.6, -- Set max height to 60%
                    layout = "normal",
                },
            })

            -- Remap diagnostic navigation to use LSP Saga.
            -- Capitals ([D/]D) so lowercase [d/]d is free for diff hunks.
            vim.keymap.set("n", "[D", "<cmd>Lspsaga diagnostic_jump_prev<CR>", {
                desc = "Jump to previous diagnostic",
                silent = true,
                noremap = true,
            })

            vim.keymap.set("n", "]D", "<cmd>Lspsaga diagnostic_jump_next<CR>", {
                desc = "Jump to next diagnostic",
                silent = true,
                noremap = true,
            })

            -- Optional: Jump to diagnostics of specific severity
            vim.keymap.set("n", "[e", function()
                require("lspsaga.diagnostic"):goto_prev({ severity = vim.diagnostic.severity.ERROR })
            end, {
                desc = "Jump to previous error",
                silent = true,
                noremap = true,
            })

            vim.keymap.set("n", "]e", function()
                require("lspsaga.diagnostic"):goto_next({ severity = vim.diagnostic.severity.ERROR })
            end, {
                desc = "Jump to next error",
                silent = true,
                noremap = true,
            })

            -- Optional: Other useful LSP Saga mappings
            vim.keymap.set("n", "K", "<cmd>Lspsaga hover_doc<CR>", {
                desc = "Hover documentation",
                silent = true,
                noremap = true,
            })

            vim.keymap.set("n", "gd", "<cmd>Lspsaga goto_definition<CR>", {
                desc = "Go to definition",
                silent = true,
                noremap = true,
            })

            vim.keymap.set("n", "gp", "<cmd>Lspsaga peek_definition<CR>", {
                desc = "Peek definition",
                silent = true,
                noremap = true,
            })

            vim.keymap.set("n", "gr", "<cmd>Lspsaga finder<CR>", {
                desc = "Find references",
                silent = true,
                noremap = true,
            })

            -- vim.keymap.set("n", "<leader>ca", "<cmd>Lspsaga code_action<CR>", {
            --   desc = "Code action",
            --   silent = true,
            --   noremap = true,
            -- })

            vim.keymap.set("n", "<leader>rn", "<cmd>Lspsaga rename<CR>", {
                desc = "Rename",
                silent = true,
                noremap = true,
            })
        end,
        dependencies = {
            'nvim-treesitter/nvim-treesitter', -- optional
            'nvim-tree/nvim-web-devicons',     -- optional
        }
    },

    -- code autoformatting like ruff or rustfmt
    {
        'stevearc/conform.nvim',
        config = function()
            require('conform').setup({
                formatters_by_ft = {
                    lua = { "stylua" },
                    -- You can also customize some of the format options for the filetype
                    rust = { "rustfmt", lsp_format = "fallback" },
                    -- You can use a function here to determine the formatters dynamically
                    python = function(bufnr)
                        if require("conform").get_formatter_info("ruff_format", bufnr).available then
                            return { "ruff_format" }
                        else
                            return { "isort", "black" }
                        end
                    end,
                    -- Use the "_" filetype to run formatters on filetypes that don't
                    -- have other formatters configured.
                    ["_"] = { "trim_whitespace" },
                },
                -- If this is set, Conform will run the formatter on save.
                -- It will pass the table to conform.format().
                -- This can also be a function that returns the table.
                format_on_save = {
                    -- I recommend these options. See :help conform.format for details.
                    lsp_format = "fallback",
                    timeout_ms = 500,
                },
                -- If this is set, Conform will run the formatter asynchronously after save.
                -- It will pass the table to conform.format().
                -- This can also be a function that returns the table.
                format_after_save = {
                    lsp_format = "fallback",
                },
                -- Set the log level. Use `:ConformInfo` to see the location of the log file.
                log_level = vim.log.levels.ERROR,
                -- Conform will notify you when a formatter errors
                notify_on_error = true,
                -- Conform will notify you when no formatters are available for the buffer
                notify_no_formatters = true,
            })
        end,
    },

    -- ==================================  AI Assistance ================================================================
    -- {
    --   "yetone/avante.nvim",
    --   build = "make",
    --   event = "VeryLazy",
    --   opts = {
    --     -- add any opts here
    --     -- this file can contain specific instructions for your project
    --     debug = false,
    --     version = false, -- Never set this value to "*"! Never!
    --     mode = "legacy",
    --     auto_suggestions = false,
    --     instructions_file = "avante.md",
    --     -- disabled_tools = {"attempt_completion"},
    --     provider = "claude",
    --     providers = {
    --       claude = {
    --         endpoint = "https://api.anthropic.com",
    --         model = "claude-sonnet-4-5",
    --         timeout = 30000, -- Timeout in milliseconds
    --           extra_request_body = {
    --             temperature = 0.75,
    --             max_tokens = 20480,
    --           },
    --       },
    --     },
    --     rag_service = {
    --       enabled = false, -- Make sure RAG is enabled
    --       host_mount = os.getenv("HOME"), -- Host mount path for the rag service (Docker will mount this path)
    --       runner = "docker", -- Runner for the RAG service (can use docker or nix)
    --       docker_extra_args = "", -- Extra arguments to pass to the docker command
    --       llm = { -- Language Model (LLM) configuration for RAG service
    --         api_key = "", -- Environment variable name for the LLM API key
    --         provider = "ollama",
    --         model = "qwen3:4b",
    --         endpoint = "http://127.0.0.1:11434",
    --         extra = nil, -- Additional configuration options for LLM
    --       },
    --       embed = { -- Embedding model configuration for RAG service
    --         api_key = "", -- Environment variable name for the LLM API key
    --         provider = "ollama",
    --         model = "bge-m3",
    --         endpoint = "http://127.0.0.1:11434",
    --         extra = {
    --           embed_batch_size = 8,
    --         },
    --       },
    --     },
    --   },
    --
    --   dependencies = {
    --     "nvim-lua/plenary.nvim",
    --     "MunifTanjim/nui.nvim",
    --     --- The below dependencies are optional,
    --     "nvim-telescope/telescope.nvim", -- for file_selector provider telescope
    --     "hrsh7th/nvim-cmp", -- autocompletion for avante commands and mentions
    --     "ibhagwan/fzf-lua", -- for file_selector provider fzf
    --     "stevearc/dressing.nvim", -- for input provider dressing
    --     "nvim-tree/nvim-web-devicons", -- or echasnovski/mini.icons
    --     {
    --       -- support for image pasting
    --       "HakonHarnes/img-clip.nvim",
    --       event = "VeryLazy",
    --       opts = {
    --         -- recommended settings
    --         default = {
    --           embed_image_as_base64 = false,
    --           prompt_for_file_name = false,
    --           drag_and_drop = {
    --             insert_mode = true,
    --           },
    --           -- required for Windows users
    --           use_absolute_path = true,
    --         },
    --       },
    --     }
    --   },
    -- },
    -- {
    --   "carlos-algms/agentic.nvim",
    --   event = "VeryLazy",
    --   opts = {
    --     -- Available by default: "claude-acp" | "gemini-acp" | "codex-acp" | "opencode-acp" | "cursor-acp"
    --     provider = "codex-acp",
    --   },
    --
    --   -- these are just suggested keymaps; customize as desired
    --   keys = {
    --     {
    --       "<leader>ac", function() require("agentic").toggle() end,
    --       mode = { "n", "v"},
    --       desc = "Toggle Agentic Chat"
    --     },
    --     {
    --       "<leader>aa",
    --       function() require("agentic").add_selection_or_file_to_context() end,
    --       mode = { "n", "v" },
    --       desc = "Add file or selection to Agentic to Context"
    --     },
    --     {
    --       "<leader>as",
    --       function() require("agentic").new_session() end,
    --       mode = { "n", "v"},
    --       desc = "New Agentic Session"
    --     },
    --   },
    -- },
    -- Claude Code: floating terminal (no plugin, just native nvim terminal)
    -- <leader>aa (toggle/continue), <leader>aA (new session), <leader>ar (resume picker)
    -- The floating window + terminal buffer are reused across toggles.
    {
        "nvim-lua/plenary.nvim", -- already a dep elsewhere, just using this entry for the config block
        keys = {
            { "<leader>aa", function() _G.claude_float_toggle("--continue") end, desc = "Claude toggle/continue" },
            { "<leader>aA", function() _G.claude_float_new() end, desc = "Claude new session" },
            { "<leader>ar", function() _G.claude_float_new("--resume") end, desc = "Claude resume session" },
        },
        config = function()
            local claude_buf = nil
            local claude_win = nil

            local function open_float(buf)
                local width = vim.o.columns - 2  -- full width minus border
                -- vim.o.lines includes statusline + cmdline (2 rows); border takes 2 more
                local usable = vim.o.lines - 2
                local height = usable - 2  -- fill all usable space minus border
                local row = 0
                local col = math.floor((vim.o.columns - width) / 2)
                claude_win = vim.api.nvim_open_win(buf, true, {
                    relative = "editor",
                    width = width,
                    height = height,
                    row = row,
                    col = col,
                    style = "minimal",
                    border = "rounded",
                })
            end

            local function buf_alive(buf)
                return buf
                    and vim.api.nvim_buf_is_valid(buf)
                    and vim.bo[buf].channel ~= 0
            end

            local function spawn_claude(flags)
                claude_buf = vim.api.nvim_create_buf(false, true)
                open_float(claude_buf)
                local cmd = "claude"
                if flags then cmd = cmd .. " " .. flags end
                vim.fn.termopen(cmd, {
                    on_exit = function()
                        if claude_win and vim.api.nvim_win_is_valid(claude_win) then
                            vim.api.nvim_win_hide(claude_win)
                            claude_win = nil
                        end
                        claude_buf = nil
                    end,
                })
                vim.cmd("startinsert")
            end

            ---Toggle visibility of the current session; start with `flags` if no session exists.
            ---@param flags? string  e.g. "--continue", "--resume"
            function _G.claude_float_toggle(flags)
                if claude_win and vim.api.nvim_win_is_valid(claude_win) then
                    vim.api.nvim_win_hide(claude_win)
                    claude_win = nil
                    return
                end
                if buf_alive(claude_buf) then
                    open_float(claude_buf)
                    vim.cmd("startinsert")
                    return
                end
                spawn_claude(flags)
            end

            ---Always start a brand-new session, replacing the current one.
            ---@param flags? string
            function _G.claude_float_new(flags)
                if claude_win and vim.api.nvim_win_is_valid(claude_win) then
                    vim.api.nvim_win_hide(claude_win)
                    claude_win = nil
                end
                spawn_claude(flags)
            end

            -- Terminal-mode: \an escapes to normal mode, \aa hides the float
            vim.keymap.set("t", "<leader>a[", [[<C-\><C-n>]], { desc = "Claude normal mode" })
            vim.keymap.set("t", "<leader>aa", function()
                if claude_win and vim.api.nvim_win_is_valid(claude_win) then
                    vim.api.nvim_win_hide(claude_win)
                    claude_win = nil
                end
            end, { desc = "Claude hide float" })
        end,
    },

    -- {
    --     "Exafunction/windsurf.nvim",
    --     -- :Codeium Auth  --
    --     dependencies = {
    --         "nvim-lua/plenary.nvim",
    --         "hrsh7th/nvim-cmp",
    --     },
    --     config = function()
    --         require("codeium").setup({
    --             enable_cmp_source = false, -- do not show codeium in completion, virtual text only
    --             enable_chat = false,       -- there's another plugin for that (codecompanion or avante)
    --             workspace_root = {
    --                 use_lsp = true,
    --             },
    --             virtual_text = {
    --                 enabled = true,
    --                 filetypes = {
    --                     rust = true,
    --                     python = true,
    --                     lua = true,
    --                     toml = true,
    --                 },
    --                 default_filetype_enabled = false,
    --                 key_bindings = {
    --                     next = "<C-J>",
    --                     prev = "<C-K>",
    --                 },
    --             },
    --         })
    --     end
    -- },
    ---------------------------------------------------------------------------
    -- Telescope (files, buffers, live grep)
    ---------------------------------------------------------------------------

    -- Telescope: fuzzy finder (files, grep, buffers, help, etc.)
    {
        "nvim-telescope/telescope.nvim",
        branch = "master",
        cmd = "Telescope",
        dependencies = {
            "nvim-lua/plenary.nvim",
            "BurntSushi/ripgrep",
        },
        keys = {
            { "<leader>ff", "<cmd>Telescope find_files<cr>",               desc = "Find files" },
            { "<leader>fg", "<cmd>Telescope live_grep<cr>",                desc = "Live grep" },
            { "<leader>fd", "<cmd>Telescope git_status<cr>",               desc = "Git changed files (diff)" },
            { "<leader>fb", "<cmd>Telescope buffers theme=dropdown<cr>",   desc = "Buffers" },
            { "<leader>fh", "<cmd>Telescope help_tags theme=dropdown<cr>", desc = "Help tags" },
            { "<leader>fs", "<cmd>Telescope aerial<cr>",                   desc = "Code map" },
            { "<leader>ft", "<cmd>TodoTelescope<cr>",                      desc = "Review comments" },
        },
        config = function()
            local telescope = require("telescope")
            local themes = require("telescope.themes")

            vim.api.nvim_set_hl(0, "TelescopeResultsDiffAdd", { fg = "#76946a" })
            vim.api.nvim_set_hl(0, "TelescopeResultsDiffChange", { fg = "#dca561" })
            vim.api.nvim_set_hl(0, "TelescopeResultsDiffDelete", { fg = "#c34043" })
            vim.api.nvim_set_hl(0, "TelescopeResultsDiffUntracked", { fg = "#727169" })

            telescope.setup({
                defaults = {
                    mappings = {
                        i = {
                            ["<C-j>"] = "move_selection_next",
                            ["<C-k>"] = "move_selection_previous",
                        },
                    },
                },
                pickers = {
                    find_files = themes.get_dropdown({
                        previewer = true,  -- keep dropdown style (usually no preview)
                        layout_config = {
                            height = 0.75, -- 50% of screen height -> more result lines
                            width  = 0.75, -- widen if you want
                        },
                    }),
                    live_grep = themes.get_dropdown({
                        previewer = true,  -- keep dropdown style (usually no preview)
                        layout_config = {
                            height = 0.75, -- 50% of screen height -> more result lines
                            width  = 0.75, -- widen if you want
                        },
                    }),
                    git_status = themes.get_dropdown({
                        previewer = true,
                        layout_config = {
                            height = 0.75,
                            width  = 0.75,
                        },
                        git_icons = {
                            added = "A",
                            changed = "M",
                            copied = "C",
                            deleted = "D",
                            renamed = "R",
                            unmerged = "U",
                            untracked = "?",
                        },
                        entry_maker = (function()
                            local numstat, og
                            return function(entry)
                                if not og then
                                    numstat = {}
                                    local out = vim.fn.systemlist("git diff --numstat HEAD")
                                    for _, line in ipairs(out) do
                                        local a, d, f = line:match("^(%d+)%s+(%d+)%s+(.+)$")
                                        if f then numstat[f] = { add = tonumber(a), del = tonumber(d) } end
                                    end
                                    og = require("telescope.make_entry").gen_from_git_status({
                                        cwd = vim.fn.getcwd(),
                                        git_icons = {
                                            added = "A", changed = "M", copied = "C",
                                            deleted = "D", renamed = "R", unmerged = "U", untracked = "?",
                                        },
                                    })
                                end
                                local result = og(entry)
                                if result then
                                    local stats = numstat[result.value]
                                    if stats then
                                        local og_display = result.display
                                        result.display = function(e)
                                            local text, hl = og_display(e)
                                            local add_str = string.format("+%-4d", stats.add)
                                            local del_str = string.format("-%-4d", stats.del)
                                            local prefix = add_str .. del_str
                                            local plen = #prefix
                                            -- shift existing highlights by prefix length
                                            local new_hl = {
                                                { { 0, #add_str }, "TelescopeResultsDiffAdd" },
                                                { { #add_str, plen }, "TelescopeResultsDiffDelete" },
                                            }
                                            if hl then
                                                for _, h in ipairs(hl) do
                                                    if h[1] then
                                                        table.insert(new_hl, { { h[1][1] + plen, h[1][2] + plen }, h[2] })
                                                    end
                                                end
                                            end
                                            return prefix .. text, new_hl
                                        end
                                    end
                                end
                                return result
                            end
                        end)(),
                        mappings = {
                            i = {
                                ["<CR>"] = function(prompt_bufnr)
                                    local action_state = require("telescope.actions.state")
                                    local entry = action_state.get_selected_entry()
                                    require("telescope.actions").close(prompt_bufnr)
                                    vim.schedule(function()
                                        vim.cmd("edit " .. entry.value)
                                        require("unified.diff").show_current("HEAD")
                                    end)
                                end,
                                ["<C-d>"] = function(prompt_bufnr)
                                    local action_state = require("telescope.actions.state")
                                    local entry = action_state.get_selected_entry()
                                    require("telescope.actions").close(prompt_bufnr)
                                    vim.schedule(function()
                                        vim.cmd("DiffviewOpen -- " .. entry.value)
                                        vim.cmd("DiffviewToggleFiles")
                                    end)
                                end,
                                ["<C-o>"] = function(prompt_bufnr)
                                    require("telescope.actions").select_default(prompt_bufnr)
                                end,
                            },
                        },
                    }),
                },
                extensions = {
                    fzf = {
                        fuzzy = true,
                        override_generic_sorter = true,
                        override_file_sorter = true,
                        case_mode = "smart_case",
                    },
                    aerial = {
                        show_nesting = {
                            ["_"] = false,
                            python = true,
                            json = true,
                            yaml = true,
                        },
                    },
                },
            })
            pcall(telescope.load_extension, "all_recent")
        end,
    },
    {
        'nvim-telescope/telescope-fzf-native.nvim',
        dependencies = {
            "nvim-telescope/telescope.nvim",
        },
        build = 'cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release --target install',
        config = function()
            require("telescope").load_extension("fzf")
        end,
    },
    {
        'prochri/telescope-all-recent.nvim',
        dependencies = {
            "nvim-telescope/telescope.nvim",
            "kkharji/sqlite.lua",
            -- optional, if using telescope for vim.ui.select
            "stevearc/dressing.nvim"
        },
        config = function()
            require("telescope-all-recent").setup({
                -- optional tuning, defaults already work well
                -- default_actions = { "select" },
                -- sorting = "frecency",  -- or "recent"
            })
        end,
    },

    ---------------------------------------------------------------------------
    -- File explorer (neo-tree)
    ---------------------------------------------------------------------------

    -- Neo-tree: file explorer, buffers, git status sidebar
    {
        "nvim-neo-tree/neo-tree.nvim",
        version = "v3.*",
        cmd = "Neotree",
        keys = {
            { "<leader>e", "<cmd>Neotree toggle<cr>", desc = "Toggle Neo-tree" },
        },
        dependencies = {
            "nvim-lua/plenary.nvim",
            "nvim-tree/nvim-web-devicons",
            "MunifTanjim/nui.nvim",
        },
        config = function()
            require("neo-tree").setup({
                sources = { "filesystem", "buffers", "git_status" },
                window = {
                    position = "left",
                    width = 30,
                },
            })
        end,
    },

    ---------------------------------------------------------------------------
    -- Git: gitsigns + neogit + diffview
    ---------------------------------------------------------------------------

    -- Gitsigns: git diff signs in the gutter + blame + hunk actions
    {
        "lewis6991/gitsigns.nvim",
        -- event = { "BufReadPost", "BufNewFile" },
        event = "FileType",
        config = function()
            require("gitsigns").setup({
                current_line_blame = true,
            })
        end,
    },

    -- Neogit: Magit-like git UI inside Neovim
    {
        "NeogitOrg/neogit",
        cmd = "Neogit",
        keys = {
            { "<leader>gs", "<cmd>Neogit<cr>", desc = "Neogit status" },
        },
        dependencies = {
            "nvim-lua/plenary.nvim",
            "sindrets/diffview.nvim",
        },
        config = function()
            require("neogit").setup({})
        end,
    },

    -- Diffview: side-by-side diffs and file history
    {
        "sindrets/diffview.nvim",
        cmd = { "DiffviewOpen", "DiffviewFileHistory" },
        keys = {
            { "<leader>gh", "<cmd>DiffviewFileHistory<cr>", desc = "Diffview: file history" },
        },
        dependencies = { "nvim-lua/plenary.nvim" },
        config = function()
            require("diffview").setup({
                hooks = {
                    view_opened = function()
                        vim.o.showtabline = 0
                    end,
                    view_closed = function()
                        vim.o.showtabline = 1
                    end,
                    diff_buf_win_enter = function(bufnr, winid)
                        vim.schedule(function()
                            if not vim.api.nvim_win_is_valid(winid) then return end
                            -- lspsaga's init_winbar skips diff buffers (checks vim.o.diff),
                            -- so temporarily disable diff to let it initialize the winbar
                            vim.api.nvim_win_call(winid, function()
                                local saved = vim.wo[winid].diff
                                vim.wo[winid].diff = false
                                pcall(function()
                                    require("lspsaga.symbol.winbar").init_winbar(bufnr)
                                end)
                                vim.wo[winid].diff = saved
                            end)
                        end)
                    end,
                },
            })
        end,
    },

    -- Unified.nvim: inline unified diffs in buffer
    {
        "axkirillov/unified.nvim",
        cmd = "Unified",
        keys = {
            { "]c", function() require("unified.navigation").next_hunk() end, desc = "Next diff hunk" },
            { "[c", function() require("unified.navigation").previous_hunk() end, desc = "Previous diff hunk" },
            { "]d", function() require("unified.navigation").next_hunk() end, desc = "Next diff hunk" },
            { "[d", function() require("unified.navigation").previous_hunk() end, desc = "Previous diff hunk" },
            { "<leader>gD", function()
                local hunks = vim.b.unified_hunks
                if hunks and #hunks > 0 then
                    vim.cmd("Unified reset")
                else
                    require("unified.diff").show_current("HEAD")
                end
            end, desc = "Toggle unified diff" },
            { "<leader>gd", function()
                local diffview_open = false
                pcall(function()
                    diffview_open = require("diffview.lib").get_current_view() ~= nil
                end)
                if diffview_open then
                    vim.cmd("DiffviewClose")
                    vim.schedule(function()
                        require("unified.diff").show_current("HEAD")
                    end)
                else
                    local file = vim.fn.expand("%:p")
                    pcall(vim.cmd, "Unified reset")
                    local ok, err = pcall(vim.cmd, "DiffviewOpen -- " .. file)
                    if ok then
                        vim.cmd("DiffviewToggleFiles")
                    else
                        vim.notify("DiffviewOpen failed: " .. err, vim.log.levels.WARN)
                    end
                end
            end, desc = "Toggle unified/diffview" },
        },
        opts = {},
    },

    ---------------------------------------------------------------------------
    -- Motion (EasyMotion-style)
    ---------------------------------------------------------------------------

    -- Leap: fast in-buffer jumps (EasyMotion/Sneak-style)
    {
        url = "https://codeberg.org/andyg/leap.nvim",
        event = "VeryLazy",
        config = function()
            local leap = require("leap")
            -- Optional: tweak leap.opts here if desired
            vim.keymap.set({ "n", "x", "o" }, "s", "<Plug>(leap-forward-to)", { desc = "Leap forward" })
            vim.keymap.set({ "n", "x", "o" }, "S", "<Plug>(leap-backward-to)", { desc = "Leap backward" })
            vim.keymap.set({ "n", "x", "o" }, "gs", "<Plug>(leap-from-window)", { desc = "Leap from window" })
        end,
    },

    ---------------------------------------------------------------------------
    -- Comments, surround, which-key, indent guides
    ---------------------------------------------------------------------------

    -- todo-comments: highlight and search review annotations (AGENT, FIX, Q, TODO)
    {
        "folke/todo-comments.nvim",
        event = "FileType",
        dependencies = { "nvim-lua/plenary.nvim" },
        config = function()
            require("todo-comments").setup({
                keywords = {
                    AGENT = { icon = " ", color = "hint" },
                    FIX   = { icon = " ", color = "error" },
                    TODO  = { icon = " ", color = "info" },
                    NOTE  = { icon = " ", color = "hint" },
                    Q     = { icon = "?", color = "warning", alt = { "QUESTION" } },
                },
            })
            vim.keymap.set("n", "]t", function()
                require("todo-comments").jump_next()
            end, { desc = "Next todo comment" })
            vim.keymap.set("n", "[t", function()
                require("todo-comments").jump_prev()
            end, { desc = "Previous todo comment" })
        end,
    },

    -- Comment.nvim: toggle comments (gc, gcc, etc.)
    {
        "numToStr/Comment.nvim",
        -- event = { "BufReadPost", "BufNewFile" },
        event = "FileType",
        config = function()
            require("Comment").setup()
        end,
    },

    -- nvim-surround: change/add/remove surrounding characters (ys, cs, ds)
    {
        "kylechui/nvim-surround",
        event = "VeryLazy",
        config = function()
            require("nvim-surround").setup()
        end,
    },

    -- which-key: popup for keymaps when pressing <leader>
    {
        "folke/which-key.nvim",
        event = "VeryLazy",
        config = function()
            require("which-key").setup()
        end,
    },

    -- Wrapwidth: virtual soft-wrap at a specific column
    {
        "rickhowe/wrapwidth",
        event = "FileType",
        config = function()
            vim.g.wrapwidth_sign = "↪"

            local function wrapwidth_exclude_tables(buf)
                local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
                for i, line in ipairs(lines) do
                    if line:match("^|") then
                        vim.cmd(i .. "Wrapwidth 0")
                    end
                end
            end

            vim.api.nvim_create_autocmd("FileType", {
                pattern = { "markdown", "text", "gitcommit" },
                callback = function(ev)
                    vim.wo.linebreak = true
                    vim.cmd("Wrapwidth 88")
                    if ev.match == "markdown" then
                        wrapwidth_exclude_tables(ev.buf)
                        vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
                            buffer = ev.buf,
                            callback = function()
                                wrapwidth_exclude_tables(ev.buf)
                            end,
                        })
                    end
                end,
            })
        end,
    },

    -- Indent-blankline (ibl): show indent guides
    {
        "lukas-reineke/indent-blankline.nvim",
        main = "ibl",
        -- event = { "BufReadPost", "BufNewFile" },
        event = "FileType",
        config = function()
            require("ibl").setup({
                scope = {
                    enabled = true,
                    show_start = false,
                    show_end = false,
                },
            })
        end,
    },
    ---------------------------------------------------------------------------
    -- Filetype-specific plugins
    ---------------------------------------------------------------------------

    -- (jupyter) {
    {
        "benlubas/molten-nvim",
        version = "^1.0.0", -- use version <2.0.0 to avoid breaking changes
        dependencies = { "3rd/image.nvim" },
        build = ":UpdateRemotePlugins",
        init = function()
            vim.g.molten_image_provider = "image.nvim"

            vim.g.molten_auto_open_output = false
            vim.g.molten_enter_output_behavior = "open_and_enter"
            -- Output as virtual text. Allows outputs to always be shown
            vim.g.molten_virt_text_output = true
            vim.g.molten_wrap_output = true
            -- truncate top of output instead of bottom
            vim.g.molten_virt_text_truncate = "top"

            -- this will make it so the output shows up below the \`\`\` cell delimiter
            -- vim.g.molten_virt_lines_off_by_1 = false  -- this doesn't work properly


            vim.keymap.set("n", "<leader>ji", function()
                vim.cmd("QuartoActivate")
                local venv = os.getenv("VIRTUAL_ENV_PROMPT") or os.getenv("CONDA_PREFIX")
                if venv ~= nil then
                    vim.cmd(("MoltenInit %s"):format(venv))
                else
                    vim.cmd("MoltenInit")
                end
            end, { desc = "initialize ipynb kernel", silent = true })

            vim.keymap.set('n', "<leader>jI", function()
                vim.cmd("MoltenRestart")
            end, { desc = "restart ipynb kernel", silent = true })

            vim.keymap.set('n', "<leader>js", function()
                vim.cmd("MoltenInterrupt")
            end, { desc = "interrupt cell execution", silent = true })

            vim.keymap.set("n", "<leader>jo", function()
                local code_win = vim.api.nvim_get_current_win()
                local code_win_height = vim.api.nvim_win_get_height(code_win)
                local code_cursor_line = vim.api.nvim_win_get_cursor(code_win)[1]

                vim.cmd("noautocmd MoltenEnterOutput")
                vim.cmd("set filetype=python")
                local error_win = vim.api.nvim_get_current_win()
                local error_win_height = vim.api.nvim_win_get_height(error_win)
                local error_win_height = math.max(error_win_height, 25)
                vim.cmd(("resize %d"):format(error_win_height))

                -- Calculate proper centering for the smaller code window
                vim.api.nvim_win_call(code_win, function()
                    local new_code_win_height = code_win_height - error_win_height
                    local target_topline = math.max(1, code_cursor_line - math.floor(new_code_win_height / 2))
                    vim.fn.winrestview({ topline = target_topline })
                end)
            end, { desc = "show cell output", silent = true })

            local default_notebook = [[
          {
            "cells": [
             {
              "cell_type": "markdown",
              "metadata": {},
              "source": [
                ""
              ]
             }
            ],
            "metadata": {
             "kernelspec": {
              "display_name": "Python 3",
              "language": "python",
              "name": "python3"
             },
             "language_info": {
              "codemirror_mode": {
                "name": "ipython"
              },
              "file_extension": ".py",
              "mimetype": "text/x-python",
              "name": "python",
              "nbconvert_exporter": "python",
              "pygments_lexer": "ipython3"
             }
            },
            "nbformat": 4,
            "nbformat_minor": 5
          }
        ]]

            local function new_notebook(filename)
                local path = filename .. ".ipynb"
                local file = io.open(path, "w")
                if file then
                    file:write(default_notebook)
                    file:close()
                    vim.cmd("edit " .. path)
                else
                    print("Error: Could not open new notebook file for writing.")
                end
            end

            vim.api.nvim_create_user_command('NewNotebook', function(opts)
                new_notebook(opts.args)
            end, {
                nargs = 1,
                complete = 'file'
            })
        end,
    },
    {
        "quarto-dev/quarto-nvim",
        dependencies = {
            "jmbuhr/otter.nvim",
            "nvim-treesitter/nvim-treesitter",
        },
        config = function()
            require("quarto").setup({
                lspFeatures = {
                    -- NOTE: put whatever languages you want here:
                    languages = { "python", "rust" },
                    chunks = "all",
                    diagnostics = {
                        enabled = true,
                        triggers = { "BufWritePost" },
                    },
                    completion = {
                        enabled = true,
                    },
                },
                -- keymap = {
                --     -- NOTE: setup your own keymaps:
                --     hover = "K",
                --     definition = "gd",
                --     -- rename = "<leader>rn",
                --     references = "gr",
                --     -- format = "<leader>gf",
                -- },
                codeRunner = {
                    enabled = true,
                    default_method = "molten",
                },
            })
            local runner = require("quarto.runner")
            vim.keymap.set("n", "<leader>jc", runner.run_cell, { desc = "run cell", silent = true })
            vim.keymap.set("n", "<leader>ja", runner.run_above, { desc = "run cell and above", silent = true })
            vim.keymap.set("n", "<leader>jA", runner.run_all, { desc = "run all cells", silent = true })
            vim.keymap.set("n", "<leader>jl", runner.run_line, { desc = "run line", silent = true })
            vim.keymap.set("v", "<leader>j", runner.run_range, { desc = "run visual range", silent = true })
            vim.keymap.set("n", "<leader>JA", function()
                runner.run_all(true)
            end, { desc = "run all cells of all languages", silent = true })
        end,
    },
    {
        "GCBallesteros/jupytext.nvim",
        config = function()
            require("jupytext").setup({
                style = "markdown",
                output_extension = "md",
                force_ft = "markdown",
            })
        end,
        lazy = false, -- to fix some errors mentioned in README.md in their repo
    },
    {
        -- see the image.nvim readme for more information about configuring this plugin
        -- system dependencies:
        --    sudo apt-get install imagemagick libmagickwand-dev luarocks
        --    luarocks install --lua-version=5.1 --local magick

        "3rd/image.nvim",
        opts = {
            backend = "kitty", -- whatever backend you would like to use
            max_width = 100,
            max_height = 12,
            max_height_window_percentage = math.huge,
            max_width_window_percentage = math.huge,
            window_overlap_clear_enabled = true, -- toggles images when windows are overlapped
            window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "" },
        },
    },
    -- } (jupyter)
}
