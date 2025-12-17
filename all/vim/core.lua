return {

  ---------------------------------------------------------------------------
  -- Colorscheme + basic UI
  ---------------------------------------------------------------------------

  -- kanagawa colorscheme
  {
    "rebelot/kanagawa.nvim",
    lazy = false,         -- load at startup so colors are available immediately
    priority = 1000,
    config = function()
      vim.cmd("colorscheme kanagawa-wave")
    end,
  },

  -- Lualine statusline
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("lualine").setup({
        icons_enabled = true,
        options = {
          theme = "auto",
          globalstatus = true,
        },
        sections = {
          lualine_c = {
            {
              'filename',
              path = 1,  -- 3: absolute with ~, 4: filename + parent with ~
            }
          }
        }
      })
    end,
  },

  ---------------------------------------------------------------------------
  -- Treesitter (syntax, highlighting, etc.)
  ---------------------------------------------------------------------------

  -- Treesitter: better syntax highlighting, indentation, textobjects
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    -- event = { "BufReadPost", "BufNewFile" },
    event = "FileType",
    config = function()
      require("nvim-treesitter.configs").setup({
        ensure_installed = {
          "lua",
          "python",
          "rust",
          "bash",
          "json",
          "yaml",
          "markdown",
          "markdown_inline",
        },
        highlight = { enable = true },
        indent = { enable = true },
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
    ft = { "markdown", "avante" }
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
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
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
        -- Your LSP Saga configuration here
        -- You can customize the UI and behavior
        ui = {
          border = "rounded",
          code_action = "💡",
        },
        hover = {
          max_width = 0.9,  -- 90% of screen width
          max_height = 0.8, -- 80% of screen height
          min_width = 20,   -- Minimum width in characters
          min_height = 10,  -- Minimum height in lines
          border = "single", -- Or "rounded", "double", etc.
        },
        finder = {
           max_height = 0.6, -- Set max height to 60%
           layout = "normal", 
        },
      })

      -- Remap diagnostic navigation to use LSP Saga
      vim.keymap.set("n", "[d", "<cmd>Lspsaga diagnostic_jump_prev<CR>", {
        desc = "Jump to previous diagnostic",
        silent = true,
        noremap = true,
      })
      
      vim.keymap.set("n", "]d", "<cmd>Lspsaga diagnostic_jump_next<CR>", {
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
      
      vim.keymap.set("n", "<leader>ca", "<cmd>Lspsaga code_action<CR>", {
        desc = "Code action",
        silent = true,
        noremap = true,
      })
      
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
  {
    "yetone/avante.nvim",
    build = "make",
    event = "VeryLazy",
    opts = {
      -- add any opts here
      -- this file can contain specific instructions for your project
      debug = false,
      version = false, -- Never set this value to "*"! Never!
      mode = "legacy",
      auto_suggestions = false,
      instructions_file = "avante.md",
      -- disabled_tools = {"attempt_completion"},
      provider = "claude",
      providers = {
        claude = {
          endpoint = "https://api.anthropic.com",
          model = "claude-sonnet-4-5",
          timeout = 30000, -- Timeout in milliseconds
            extra_request_body = {
              temperature = 0.75,
              max_tokens = 20480,
            },
        },
      },
      rag_service = {
        enabled = false, -- Make sure RAG is enabled
        host_mount = os.getenv("HOME"), -- Host mount path for the rag service (Docker will mount this path)
        runner = "docker", -- Runner for the RAG service (can use docker or nix)
        docker_extra_args = "", -- Extra arguments to pass to the docker command
        llm = { -- Language Model (LLM) configuration for RAG service
          api_key = "", -- Environment variable name for the LLM API key
          provider = "ollama",
          model = "qwen3:4b", 
          endpoint = "http://127.0.0.1:11434",
          extra = nil, -- Additional configuration options for LLM
        },
        embed = { -- Embedding model configuration for RAG service
          api_key = "", -- Environment variable name for the LLM API key
          provider = "ollama",
          model = "bge-m3",
          endpoint = "http://127.0.0.1:11434",
          extra = {
            embed_batch_size = 8,
          },
        },
      },
    },

    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      --- The below dependencies are optional,
      "nvim-telescope/telescope.nvim", -- for file_selector provider telescope
      "hrsh7th/nvim-cmp", -- autocompletion for avante commands and mentions
      "ibhagwan/fzf-lua", -- for file_selector provider fzf
      "stevearc/dressing.nvim", -- for input provider dressing
      "nvim-tree/nvim-web-devicons", -- or echasnovski/mini.icons
      {
        -- support for image pasting
        "HakonHarnes/img-clip.nvim",
        event = "VeryLazy",
        opts = {
          -- recommended settings
          default = {
            embed_image_as_base64 = false,
            prompt_for_file_name = false,
            drag_and_drop = {
              insert_mode = true,
            },
            -- required for Windows users
            use_absolute_path = true,
          },
        },
      }
    },
  },

  {
    "Exafunction/windsurf.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "hrsh7th/nvim-cmp",
    },
    config = function()
        require("codeium").setup({
          enable_cmp_source = false,  -- do not show codeium in completion, virtual text only
          enable_chat = false,  -- there's another plugin for that (codecompanion or avante)
          workspace_root = {
            use_lsp = true,
          },
          virtual_text = {
            enabled = true,
            filetypes = {
              rust = true,
              python = true,
              lua = true,
              toml = true,
            },
            default_filetype_enabled = false,
            key_bindings = {
              next = "<C-j>",
              prev = "<C-k>",
            },
          },
        })
    end
  },
  ---------------------------------------------------------------------------
  -- Telescope (files, buffers, live grep)
  ---------------------------------------------------------------------------

  -- Telescope: fuzzy finder (files, grep, buffers, help, etc.)
  {
    "nvim-telescope/telescope.nvim",
    branch = "0.1.x",
    cmd = "Telescope",
    dependencies = { 
      "nvim-lua/plenary.nvim",
      "BurntSushi/ripgrep",
    },
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find files" },
      { "<leader>fg", "<cmd>Telescope live_grep<cr>",  desc = "Live grep" },
      { "<leader>fd", "<cmd>Telescope aerial<cr>",  desc = "Code map" },
      { "<leader>fb", "<cmd>Telescope buffers theme=dropdown<cr>",    desc = "Buffers" },
      { "<leader>fh", "<cmd>Telescope help_tags theme=dropdown<cr>",  desc = "Help tags" },
    },
    config = function()
      local telescope = require("telescope")
      local themes = require("telescope.themes")
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
            previewer = true,     -- keep dropdown style (usually no preview)
            layout_config = {
              height = 0.75,   -- 50% of screen height -> more result lines
              width  = 0.75,   -- widen if you want
            },
          }),
          live_grep = themes.get_dropdown({
            previewer = true,     -- keep dropdown style (usually no preview)
            layout_config = {
              height = 0.75,   -- 50% of screen height -> more result lines
              width  = 0.75,   -- widen if you want
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
      { "<leader>gd", "<cmd>DiffviewOpen<cr>",         desc = "Diffview: open" },
      { "<leader>gh", "<cmd>DiffviewFileHistory<cr>", desc = "Diffview: file history" },
    },
    dependencies = { "nvim-lua/plenary.nvim" },
  },

  ---------------------------------------------------------------------------
  -- Motion (EasyMotion-style)
  ---------------------------------------------------------------------------

  -- Leap: fast in-buffer jumps (EasyMotion/Sneak-style)
  {
    "ggandor/leap.nvim",
    event = "VeryLazy",
    config = function()
      local leap = require("leap")
      -- Optional: tweak leap.opts here if desired
      vim.keymap.set({ "n", "x", "o" }, "s",  "<Plug>(leap-forward-to)",  { desc = "Leap forward" })
      vim.keymap.set({ "n", "x", "o" }, "S",  "<Plug>(leap-backward-to)", { desc = "Leap backward" })
      vim.keymap.set({ "n", "x", "o" }, "gs", "<Plug>(leap-from-window)", { desc = "Leap from window" })
    end,
  },

  ---------------------------------------------------------------------------
  -- Comments, surround, which-key, indent guides
  ---------------------------------------------------------------------------

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

  -- Indent-blankline (ibl): show indent guides
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    -- event = { "BufReadPost", "BufNewFile" },
    event = "FileType",
    config = function()
      require("ibl").setup()
    end,
  },
}

