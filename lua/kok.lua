return function(args)
  local cwd = unpack(args)

  local function defer(timeout, callback)
    local timer = vim.loop.new_timer()
    timer:start(
      timeout,
      0,
      function()
        timer:stop()
        timer:close()
        vim.schedule(callback)
      end
    )
    return timer
  end

  local settings = function()
    local go, _settings = pcall(vim.api.nvim_get_var, "KoK_settings")
    local settings = go and _settings or {}
    return settings
  end

  KoK = KoK or {}
  local linesep = "\n"
  local POLLING_RATE = 10

  if KoK.loaded then
    return
  else
    KoK.loaded = true
    local job_id = nil
    local KoK_params = {}
    local err_exit = false

    KoK.on_exit = function(args)
      local code = unpack(args)
      local msg = " | KoK EXITED - " .. code
      if not (code == 0 or code == 143) then
        err_exit = true
        vim.api.nvim_err_writeln(msg)
      else
        err_exit = false
      end
      job_id = nil
      for _, param in ipairs(KoK_params) do
        KoK[KoK_params] = nil
      end
    end

    KoK.on_stdout = function(args)
      local msg = unpack(args)
      vim.api.nvim_out_write(table.concat(msg, linesep))
    end

    KoK.on_stderr = function(args)
      local msg = unpack(args)
      vim.api.nvim_err_write(table.concat(msg, linesep))
    end

    local start = function(...)
      local is_win = vim.api.nvim_call_function("has", {"win32"}) == 1

      local go, _py3 = pcall(vim.api.nvim_get_var, "python3_host_prog")
      local py3 = go and _py3 or (is_win and "python" or "python3")
      local main = cwd .. (is_win and [[\venv.bat]] or "/venv.sh")

      local args =
        vim.tbl_flatten {
        {main, py3, "-m", "KoK"},
        {...},
        (settings().xdg and {"--xdg"} or {})
      }
      local params = {
        on_exit = "KoKon_exit",
        on_stdout = "KoKon_stdout",
        on_stderr = "KoKon_stderr"
      }
      local job_id = vim.api.nvim_call_function("jobstart", {args, params})
      return job_id
    end

    KoK.deps_cmd = function()
      start("deps")
    end

    vim.api.nvim_command [[command! -nargs=0 KoKdeps lua KoK.deps_cmd()]]

    local set_KoK_call = function(name, cmd)
      table.insert(KoK_params, name)
      local t1 = 0
      KoK[name] = function(...)
        local args = {...}
        if t1 == 0 then
          t1 = vim.loop.now()
        end

        if not job_id then
          local server = vim.api.nvim_call_function("serverstart", {})
          job_id = start("run", "--socket", server)
        end

        if not err_exit and _G[cmd] then
          _G[cmd](args)
          t2 = vim.loop.now()
          if settings().profiling and t1 >= 0 then
            print("Init       " .. (t2 - t1) .. "ms")
          end
          t1 = -1
        else
          defer(
            POLLING_RATE,
            function()
              if err_exit then
                return
              else
                KoK[name](unpack(args))
              end
            end
          )
        end
      end
    end

    set_KoK_call("open_cmd", "KoKopen")
    vim.api.nvim_command [[command! -nargs=* KoKopen lua KoK.open_cmd(<f-args>)]]

    set_KoK_call("help_cmd", "KoKhelp")
    vim.api.nvim_command [[command! -nargs=* KoKhelp lua KoK.help_cmd(<f-args>)]]
  end
end
