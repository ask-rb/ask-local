# frozen_string_literal: true

module Ask
  module Local
    class CLI
      # System commands: proxy, service, hosts, trust, clean, doctor, kamal.
      module SystemCommand
        module_function

        def doctor(ctx, args)
          json = args.delete("--json")
          failed = Doctor.print(Doctor.run(store: ctx.store), out: $stdout, json: !!json)
          exit(failed.zero? ? 0 : 1)
        end

        def trust(_ctx, _args)
          result = Trust.trust
          if result[:trusted]
            puts "CA trusted."
          else
            $stderr.puts "Error: #{result[:error]}"
            exit 1
          end
        end

        def clean(ctx, _args)
          ProxyControl.stop(ctx.store)
          result = Trust.untrust
          puts "CA removed from trust store." if result[:removed]
          warn "CA untrust failed: #{result[:error]}" if result[:error]
          Hosts.clean
          require "fileutils"
          FileUtils.rm_rf(ctx.store.dir)
          puts "Cleaned ask-local state."
        end

        def hosts(ctx, args)
          sub = args.first
          case sub
          when "sync"
            hostnames = ctx.store.load_routes.map { |r| r["hostname"] }
            if Hosts.sync(hostnames)
              puts "Synced #{hostnames.length} hostname(s) to /etc/hosts."
            else
              $stderr.puts "Could not write /etc/hosts (try sudo)."
              exit 1
            end
          when "clean"
            Hosts.clean
            puts "Removed ask-local entries from /etc/hosts."
          else
            raise Error, "Usage: ask-local hosts [sync|clean]"
          end
        end

        def proxy(ctx, args)
          sub = args.first
          case sub
          when "start"
            port, tls, foreground = parse_proxy_start(args[1..])
            tlds = active_tlds(args[1..])
            if foreground
              write_tls_marker(ctx, tls)
              write_tlds_file(ctx, tlds)
              sup = Supervisor.new(store: ctx.store, runner: Runner.new(store: ctx.store),
                on_event: ->(m) { warn m })
              sup.start
              Proxy.new(store: ctx.store, port: port, tls: tls,
                state_dir: ctx.store.dir, supervisor: sup, tlds: tlds).start_foreground
            else
              ProxyControl.spawn_daemon(store: ctx.store, port: port, tls: tls, tlds: tlds)
              puts "Proxy started on port #{port}#{tls ? " (HTTPS)" : " (HTTP)"}."
            end
          when "stop"
            case ProxyControl.stop(ctx.store)
            when :stopped then puts "Proxy stopped."
            when :stale then puts "Removed stale proxy state."
            when :not_running then puts "Proxy is not running."
            when :unknown_process then puts "Port in use by an unknown process."
            end
          else
            raise Error, "Usage: ask-local proxy [start|stop]"
          end
        end

        def write_tls_marker(ctx, tls)
          ctx.store.ensure_dir
          path = File.join(ctx.store.dir, "proxy.tls")
          tls ? File.write(path, "1") : File.write(path, "0")
        end

        # TLDs the proxy serves: --tld flags, else ASK_LOCAL_TLD, else
        # localhost. Persisted so auto-restarted daemons agree, and so
        # the 404 page knows which hosts are "ours" (rebinding boundary).
        def active_tlds(args)
          flags = []
          i = 0
          while i < args.length
            if args[i] == "--tld"
              flags << args.fetch(i + 1).to_s
              i += 2
            else
              i += 1
            end
          end
          list = flags.any? ? flags : (ENV["ASK_LOCAL_TLD"]&.split(",")&.map(&:strip) || [])
          list = list.reject(&:empty?).map(&:downcase).uniq
          list.empty? ? [Hostname::DEFAULT_TLD] : list
        end

        def write_tlds_file(ctx, tlds)
          ctx.store.ensure_dir
          File.write(File.join(ctx.store.dir, "proxy.tlds"), "#{tlds.join("\n")}\n")
        rescue SystemCallError
          nil
        end

        def parse_proxy_start(args)
          port = nil
          tls = true
          foreground = false
          i = 0
          while i < args.length
            case args[i]
            when "-p", "--port" then port = args.fetch(i + 1).to_i; i += 2
            when "--no-tls" then tls = false; i += 1
            when "--https" then tls = true; i += 1
            when "--foreground" then foreground = true; i += 1
            when "--tld" then i += 2 # consumed by active_tlds
            else i += 1
            end
          end
          [port || ProxyControl.default_port(tls), tls, foreground]
        end

        def service(ctx, args)
          sub = args.first
          case sub
          when "install" then service_install(ctx, args)
          when "uninstall" then service_uninstall
          when "status" then service_status(ctx)
          else raise Error, "Usage: ask-local service [install|uninstall|status]"
          end
        end

        # Root-owned LaunchDaemon binding 80/443 at boot (puma-dev model).
        # Re-execs under sudo; the proxy runs with the invoking user's state
        # dir so routes registered by unprivileged CLIs are shared
        # (portless pattern). A root proxy can also write /etc/hosts.
        def service_install(ctx, args)
          if !ProxyControl.root? && !args.include?("--internal")
            puts "Installing system service (sudo required)..."
            state = Certs.state_dir
            ok = system("sudo", "env", "ASK_LOCAL_STATE_DIR=#{state}",
              RbConfig.ruby, ProxyControl.bin_path,
              "service", "install", "--internal")
            exit(ok ? 0 : 1)
          end
          case RUBY_PLATFORM
          when /darwin/ then install_launchd(ctx)
          when /linux/ then print_linux_unit
          else raise Error, "Service install not supported on #{RUBY_PLATFORM}"
          end
        end

        def user_home_for_service
          sudo_user = ENV["SUDO_USER"]
          if sudo_user && !sudo_user.empty?
            require "etc"
            Etc.getpwnam(sudo_user).dir
          else
            Certs.home
          end
        rescue ArgumentError
          Certs.home
        end

        def install_launchd(ctx)
          require "etc"
          home = user_home_for_service
          state_dir = ENV["ASK_LOCAL_STATE_DIR"] || File.join(home, ".ask-local")
          dir = "/Library/LaunchDaemons"
          FileUtils.mkdir_p(dir)
          plist = <<~PLIST
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
              <key>Label</key><string>dev.ask.local</string>
              <key>ProgramArguments</key>
              <array>
                <string>#{RbConfig.ruby}</string>
                <string>#{ProxyControl.bin_path}</string>
                <string>proxy</string><string>start</string><string>--foreground</string>
              </array>
              <key>EnvironmentVariables</key>
              <dict>
                <key>ASK_LOCAL_STATE_DIR</key><string>#{state_dir}</string>
                <key>HOME</key><string>#{home}</string>
              </dict>
              <key>KeepAlive</key><true/>
              <key>RunAtLoad</key><true/>
            </dict>
            </plist>
          PLIST
          path = File.join(dir, "dev.ask.local.plist")
          File.write(path, plist)
          File.chmod(0o644, path)
          Ownership.chown_service_files(path)
          system("launchctl", "unload", path) rescue nil
          system("launchctl", "load", path) or raise Error, "launchctl load failed"
          puts "Installed root LaunchDaemon on port 443 (state: #{state_dir})."
          puts "Restart your machine or run: sudo launchctl load #{path}"
        end

        def print_linux_unit
          home = user_home_for_service
          state_dir = ENV["ASK_LOCAL_STATE_DIR"] || File.join(home, ".ask-local")
          puts <<~UNIT
            # /etc/systemd/system/ask-local.service  (binds 80/443 at boot)
            [Unit]
            After=network.target

            [Service]
            ExecStart=#{RbConfig.ruby} #{ProxyControl.bin_path} proxy start --foreground
            Environment=ASK_LOCAL_STATE_DIR=#{state_dir}
            Environment=HOME=#{home}

            [Install]
            WantedBy=multi-user.target

            Install with: sudo cp ask-local.service /etc/systemd/system/ && sudo systemctl enable --now ask-local
            (Run that install command with sudo so the service is root-owned.)
          UNIT
        end

        def service_uninstall(_ctx)
          if !ProxyControl.root?
            state = Certs.state_dir
            ok = system("sudo", "env", "ASK_LOCAL_STATE_DIR=#{state}",
              RbConfig.ruby, ProxyControl.bin_path, "service", "uninstall", "--internal")
            exit(ok ? 0 : 1)
          end
          case RUBY_PLATFORM
          when /darwin/
            path = "/Library/LaunchDaemons/dev.ask.local.plist"
            system("launchctl", "unload", path) rescue nil
            FileUtils.rm_f(path)
            puts "Removed root LaunchDaemon."
          else
            puts "Remove /etc/systemd/system/ask-local.service, then: sudo systemctl disable --now ask-local"
          end
        end

        def service_status(ctx)
          port = ProxyControl.proxy_port(ctx.store)
          if port.nil? || !ProxyControl.listening?(port)
            puts "Proxy not running."
          elsif ProxyControl.ours?(port, tls: ProxyControl.proxy_tls(ctx.store))
            puts "Proxy running on port #{port}."
          else
            puts "Port #{port} in use by another process."
          end
        end

        # ask-local kamal <variant> [--app myapp] [--domain preview.example.com]
        def kamal(_ctx, args)
          opts = {}
          rest = []
          i = 0
          a = args.dup
          while i < a.length
            case a[i]
            when "--app" then opts[:app] = a.fetch(i + 1); i += 2
            when "--domain" then opts[:domain] = a.fetch(i + 1); i += 2
            else rest << a[i]; i += 1
            end
          end
          variant = rest.first
          raise Error, "Usage: ask-local kamal <variant> [--app myapp] [--domain preview.example.com]" unless variant

          app = opts[:app] || Resolver.resolve(Dir.pwd, use_branch: false).app
          domain = opts[:domain] || ENV["ASK_LOCAL_KAMAL_DOMAIN"] || "preview.example.com"
          slug = Sanitize.hostname_label(variant)
          puts "# Paste into deploy.yml proxy section for a preview of variant #{slug}:"
          puts "proxy:"
          puts "  ssl: true"
          puts "  hosts:"
          puts "    - #{app}-#{slug}.#{domain}"
        end
      end
    end
  end
end
