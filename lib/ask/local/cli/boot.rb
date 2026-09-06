# frozen_string_literal: true

module Ask
  module Local
    class CLI
      # Boot commands: bare `ask-local`, `run`, and `<name> <cmd>`.
      # Owns managed/run boot orchestration, Procfile resolution, and the
      # foreground supervision loop.
      module BootCommand
        # Frameworks that ignore $PORT get explicit flags (portless lesson:
        # Vite/Astro/Expo need --port; Jekyll/Middleman/Bridgetown do too).
        # Only injects when the user hasn't already set a port.
        PORT_IGNORING = %w[jekyll middleman bridgetown].freeze

        module_function

        def run_inferred(ctx, args)
          opts = ctx.parse_flags(args, %i[name service variant tld branch proc force])
          resolved = Resolver.resolve(Dir.pwd, name: opts[:name],
            service: opts[:service], variant: opts[:variant],
            tlds: opts[:tld], use_branch: opts[:branch])
          hostnames = Resolver.hostnames(resolved)
          ensure_proxy!(ctx)
          framework = Framework.detect(Dir.pwd)
          runner = Runner.new(store: ctx.store)
          if Framework.managed?(framework) && opts[:rest].empty?
            boot_managed(ctx, runner, resolved, hostnames, opts)
          else
            command = opts[:rest].empty? ? default_command(framework, opts[:proc]) : opts[:rest]
            boot_run(ctx, runner, resolved, hostnames, command, opts)
          end
        end

        def run_explicit(ctx, args)
          opts = ctx.parse_flags(args, %i[name service variant tld branch proc force])
          resolved = Resolver.resolve(Dir.pwd, name: opts[:name],
            service: opts[:service], variant: opts[:variant],
            tlds: opts[:tld], use_branch: opts[:branch])
          hostnames = Resolver.hostnames(resolved)
          ensure_proxy!(ctx)
          framework = Framework.detect(Dir.pwd)
          command = opts[:rest].empty? ? default_command(framework, opts[:proc]) : opts[:rest]
          boot_run(ctx, Runner.new(store: ctx.store), resolved, hostnames, command, opts)
        end

        def run_named(ctx, name, args)
          opts = ctx.parse_flags(args, %i[force app_port])
          resolved = Resolver.resolve(Dir.pwd, name: name)
          hostnames = Resolver.hostnames(resolved)
          ensure_proxy!(ctx)
          if opts[:rest].empty?
            $stderr.puts "Error: no command given for #{name}."
            exit 1
          end
          boot_run(ctx, Runner.new(store: ctx.store), resolved, hostnames, opts[:rest], opts)
        end

        def boot_managed(ctx, runner, resolved, hostnames, opts)
          primary = hostnames.first
          url = Hostname.url(primary, port: ctx.proxy_port, tls: ctx.proxy_tls)
          puts "ask-local"
          puts "-- #{hostnames.join(", ")}"
          app = runner.boot_managed(name: resolved.app, hostname: primary,
            url: url, dir: Dir.pwd, force: opts[:force])
          register_all(ctx, hostnames, app, force: opts[:force], spec: { "dir" => File.expand_path(Dir.pwd) })
          puts "\n  -> #{url}\n"
          ctx.report_unresolved(hostnames)
          trap_cleanup(ctx, hostnames)
          supervise_backend(ctx, hostnames, app)
        end

        def boot_run(ctx, runner, resolved, hostnames, command, opts)
          primary = hostnames.first
          url = Hostname.url(primary, port: ctx.proxy_port, tls: ctx.proxy_tls)
          puts "ask-local"
          puts "-- #{hostnames.join(", ")}"
          port = opts[:app_port] || Ports.find_free
          command = inject_port_flags(command, port)
          app = runner.boot_run(name: resolved.app, hostname: primary, url: url,
            dir: Dir.pwd, command: command, port: port, force: opts[:force])
          register_all(ctx, hostnames, app, force: opts[:force])
          puts "\n  -> #{url}\n"
          puts "Running: PORT=#{app.target.split(":").last} ASK_LOCAL_URL=#{url} #{command.join(" ")}"
          ctx.report_unresolved(hostnames)
          trap_cleanup(ctx, hostnames)
          supervise_backend(ctx, hostnames, app)
        end

        # Foreground loop: exit (cleaning up) when the backend dies, so a
        # crashed app never leaves a stale route behind. Backends are
        # spawned detached (so Ctrl+C in the CLI never SIGINTs the app),
        # which rules out Process.wait — detached children are already
        # reaped. Poll liveness at 2Hz: prompt enough for crash cleanup
        # without spinning.
        def supervise_backend(ctx, hostnames, app)
          until !ProxyControl.pid_alive?(app.pid)
            sleep 0.5
          end
          puts "\nBackend exited — cleaning up."
          cleanup_routes(ctx, hostnames)
          exit 0
        end

        def inject_port_flags(command, port)
          return command if command.empty?
          return command if command.any? { |a| a.match?(/\A(-p|--port)(=|\z)/) }
          # A literal $PORT already present (e.g. Procfile `web: x --port $PORT`,
          # foreman --port passthrough): injecting again would double-set it.
          return command if command.any? { |a| a.include?("$PORT") }

          bin = File.basename(command.first.to_s)
          needs_flags = PORT_IGNORING.include?(bin) ||
            (command.length > 2 && PORT_IGNORING.include?(File.basename(command[2].to_s)))
          return command unless needs_flags

          flags = ["--port", port.to_s, "--host", "127.0.0.1"]
          flags.concat(jekyll_livereload_flags(port)) if jekyll_command?(command)
          command + flags
        end

        # Jekyll's livereload runs its own server on a second port
        # (default 35729) serving the livereload.js WebSocket. It cannot go
        # through the proxy (one route = one backend), so pin it next to the
        # main port and document the direct URL. Only when the app enables
        # livereload in _config.yml; explicit user flags always win.
        JEKYLL_LIVERELOAD_DEFAULT_PORT = 35_729

        def jekyll_command?(command)
          command.any? { |a| File.basename(a.to_s) == "jekyll" }
        end

        def jekyll_livereload_flags(port)
          return [] unless File.file?("_config.yml")
          return [] unless File.read("_config.yml").match?(/^\s*livereload:\s*true/i)
          return [] if port + 1 > Ports::MAX_PORT

          ["--livereload-port", (port + 1).to_s]
        rescue SystemCallError
          []
        end

        def default_command(framework, proc_name = nil)
          case framework
          when :procfile
            procfile_command(proc_name) || raise(Error,
              proc_name ? "Procfile has no '#{proc_name}' process, or its line is " \
                "compound (&&, ||, |, ;) — ask-local cannot inject PORT safely. " \
                "Run explicitly instead: ask-local run -- <command>" :
                "Procfile.dev first line is compound (&&, ||, |, ;) or unreadable — " \
                "ask-local cannot inject PORT safely. Run explicitly instead: " \
                "ask-local run -- <command>")
          when :jekyll then %w[bundle exec jekyll serve]
          when :bridgetown then %w[bin/bridgetown start]
          when :middleman then %w[bundle exec middleman server]
          else raise(Error, "No command given and no bootable app detected. Usage: ask-local run -- <command>")
          end
        end

        # First process by default; --proc <name> picks a specific line
        # (the overmind `-P web` convention teams already use).
        #
        # Trust boundary: the Procfile line is repo code, so `sh -c` is
        # safe here the way it would not be for user-supplied input.
        def procfile_command(process = nil)
          path = File.file?("Procfile.dev") ? "Procfile.dev" : "Procfile"
          lines = File.readlines(path).map(&:strip).reject { |l| l.empty? || l.start_with?("#") }
          chosen =
            if process
              lines.find { |l| l.start_with?("#{process}:") }
            else
              lines.first
            end
          return nil unless chosen

          cmd = chosen.split(":", 2).last.to_s.strip
          # Refuse compound lines we cannot safely inject PORT into.
          return nil if cmd.match?(/&&|\|\||[|;]/)

          ["sh", "-c", cmd]
        end

        def trap_cleanup(ctx, hostnames)
          %w[INT TERM].each do |sig|
            trap(sig) do
              cleanup_routes(ctx, hostnames)
              exit 0
            end
          end
        end

        # Primary hostname is registered by the runner; secondaries (extra
        # TLDs) share the same backend. Every hostname gets a backend sidecar
        # so `ask-local stop` finds the process from any of them, and the
        # daemon supervisor needs the spec on every hostname.
        def register_all(ctx, hostnames, app, force:, spec: nil)
          hostnames[1..].each do |h|
            ctx.store.add_route(h, app.target, Process.pid, kind: app.kind,
              force: force, spec: spec)
            write_backend_sidecar(ctx, h, app.pid)
          end
        end

        def write_backend_sidecar(ctx, hostname, pid)
          ctx.store.ensure_dir
          File.write(File.join(ctx.store.dir, "backend-#{hostname}.pid"), "#{pid}\n")
        rescue SystemCallError
          nil
        end

        # Foreground boot semantics (portless model): leaving = routes gone
        # AND backend stopped. No orphans on Ctrl+C, TERM, or clean exit.
        def cleanup_routes(ctx, hostnames)
          hostnames.each do |h|
            begin
              entry = ctx.store.find(h)
              pid = ctx.backend_pid_for(entry) if entry
              if pid && ProxyControl.pid_alive?(pid)
                Process.kill("TERM", pid) rescue nil
              end
              ctx.store.remove_route(h, owner_pid: Process.pid) rescue nil
              FileUtils.rm_f(File.join(ctx.store.dir, "backend-#{h}.pid"))
            rescue StandardError
              nil
            end
          end
        end

        def ensure_proxy!(ctx)
          port = ctx.proxy_port
          tls = ctx.proxy_tls
          if ProxyControl.listening?(port)
            if ProxyControl.ours?(port, tls: tls)
              return
            end

            $stderr.puts "Error: port #{port} is in use by another process."
          end

          privileged = port < 1024 && !ProxyControl.root?
          if privileged && !ctx.interactive?
            $stderr.puts "Proxy is not running and no TTY is available for sudo."
            $stderr.puts "Start it in a terminal: ask-local proxy start"
            $stderr.puts "Or use an unprivileged port: ask-local proxy start -p 1355"
            exit 1
          end
          puts "Starting proxy#{privileged ? " (will prompt for sudo to bind port #{port})" : ""}..."
          ProxyControl.spawn_daemon(store: ctx.store, port: port, tls: tls, sudo: privileged)
        rescue Errno::EACCES
          $stderr.puts "Error: could not bind port #{port}. Try: ask-local proxy start -p 1355"
          exit 1
        end
      end
    end
  end
end
