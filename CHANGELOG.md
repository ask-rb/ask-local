# Changelog

## [0.1.1] — 2026-09-06

Patch release focused on workstation setup, URL correctness, and proxy reliability.

### Added — `ask-local setup` & `ask-local start`

- `ask-local setup` — one-shot workstation setup for clean
  `https://<app>.localhost` URLs: trust the local CA, serve port 443
  (root launchd/systemd service when possible, sudo daemon otherwise),
  sync `/etc/hosts`, and verify with `doctor`. Each step reports
  `==>` / `ok` and the first failure aborts with the specific fix.
- `ask-local start` — one-setup-and-go entry point: an idempotent
  workstation-check-then-boot (`ask-local setup` if needed, then the
  app). `ask-local` bare is an alias for it; `ask-local setup` stays for
  explicit re-setup.
- `askl` — shell-friendly alias binary (`bin/askl`, same entry point as
  `bin/ask-local`). Keep `ask-local` in logs and docs so `grep` stays
  useful.

### Added — DNS-rebinding & log hygiene

- DNS-rebinding boundary: foreign `Host` headers get a bare 404 naming
  nothing; only hosts under our own configured TLDs see the route-listing
  404. The proxy takes `--tld` (persisted to `proxy.tlds`) so the boundary
  follows custom domains. The `X-Ask-Local: 1` health header marks our
  proxy responses (including 404s) for the `ours?` probe.
- Log rotation — `proxy.log` and per-app backend logs rotate at 5MB
  (`ASK_LOCAL_LOG_MAX_BYTES`, one generation) before each write. A new
  `doctor` disk-usage check warns past 100MB of state.

### Fixed

- **Silent `:1355` URL fallback removed.** Privileged-port (443) bind
  failure is now a hard error pointing at `ask-local setup`, never a
  booted app on `https://app.localhost:1355` that silently corrupts
  downstream consumers of `ASK_LOCAL_URL`. The only port-suffixed URLs
  are the ones you explicitly ask for (`proxy start -p 1355`).
- **Health probe `130+?` hang fixed.** The TLS probe's `connect` sat
  outside the timeout: a TLS handshake against a foreign plain-HTTP
  server blocked in `connect` for 60s+. Connect is now inside the
  timeout, plain HTTP is tried first (our proxy answers plain HTTP via
  byte-peeking even on the TLS port), and any HTTP response without our
  header short-circuits as foreign — only silent servers wait for the
  timeout.
- `start` dispatch was missing from the dispatcher despite being in
  `SUBCOMMANDS`, so `ask-local start` fell through to `run_named` with
  "start" as an app name. The kamal-help append drifted to a 6-space
  indent. Both are fixed and pinned by tests.
- `base64` declared as a runtime dependency (it left the default gems in
  Ruby 3.4).
- Missing `require "optparse"` lost in the CLI split.

### Tests — new coverage for this patch

- `start_test.rb` — help, fast-path vs. needs-setup branching, and the
  non-interactive hard-error message.
- `setup_test.rb` — four-step orchestration (all-steps-stubbed), first-failure
  abort with fix text, `--no-service` flag, and the three `ensure_proxy!`
  hard-error paths (non-interactive, foreign port, spawn failure) plus
  explicit-port URL honesty and responding-foreign-server fast classification.
- Pinned under `bundle exec rake test` (fast unit suite); no `test:e2e`
  needed for these.

## [0.2.0] — Unreleased

### Changed

- `cli.rb` (757 lines) split into command objects behind a shared
  Context: `cli/boot.rb` (run/boot/supervision), `cli/routes.rb`
  (get/alias/list/prune/stop/restart/log/status/open),
  `cli/system.rb` (proxy/service/hosts/trust/clean/doctor/kamal).
- Default `rake test` runs the fast unit suite (~6s); `rake test:e2e`
  runs daemon/TLS/live-boot tests; `rake test:all` runs everything.

### Added

- Daemon-owned supervision (puma-dev model): managed apps idle-stop
  after 15 minutes (`ASK_LOCAL_IDLE_TIMEOUT`), stop when tmp/restart.txt
  changes, and boot transparently on the next request.
- `ask-local stop` (exit 0 stopped / 2 no route / 3 backend already
  gone), `restart`, `log [-f] [n]`, `status` (effective naming context),
  `open [name]` (browser). `list` shows backend liveness per route.
- Root-owned `service install` (launchd/systemd) binding 80/443 at boot
  with the invoking user's state dir; sudo re-exec when needed.
- All root write paths chown state back to the invoking user; `doctor`
  reports an unwritable state dir plainly. The privileged auto-start
  re-execs under `sudo` with the correct state dir.
- Bounded proxy concurrency (`ASK_LOCAL_MAX_CONNECTIONS`, 503 past the
  cap), mtime-based route cache (no TTL race for boot-then-curl), IPv4+IPv6
  loopback listeners, dual-stack `ours?` health check.
- `get` inherits variant/TLD context from the current directory
  (`get backend` in a fix-ui worktree -> fix-ui.backend.localhost);
  `--service/--variant/--tld` overrides.
- `alias` accepts full hostnames on any TLD and honors ASK_LOCAL_TLD.
- `kamal` snippet resolves the app from the directory; `--app/--domain`
  flags and ASK_LOCAL_KAMAL_DOMAIN.
- `clean` untrusts the CA from the OS trust store.
- `--proc <name>` picks a specific Procfile process.
- Ships the `ask-local` agent skill (ask/skills/ask-local/SKILL.md).
- `test:e2e` / `test:all` rake tasks; CI matrix (3.2/3.3/3.4/4.0),
  macOS e2e leg, fixture-sweep job.
- Ownership module, framework fixtures (sinatra-modular,
  foreman-`$PORT`, hanami2 slice layout, jekyll livereload), SKILL.md
  "when NOT to use" section, README non-goals, vite/Shakapacker recipe.
- Host authorization patterns default TLDs from `ASK_LOCAL_TLD`.
- WebSocket Upgrade end-to-end test (RFC 6455 handshake + frame echo),
  hop-loop 508 rejection, chunked framing, and spinning-loop fix.

### Fixed

- Daemon spawn and service install resolved the ask-local binary one
  directory too high — `proxy start` failed outright; failures now
  include the proxy log tail.
- Keep-alive connections now rewrite headers (X-Forwarded-Proto) on
  every request, not just the first — request 2+ previously reached the
  backend unrewritten, breaking ssl detection and OmniAuth callbacks.
- Ctrl+C / TERM stops the backend process (no orphans); the CLI exits
  when the backend dies, cleaning up routes.
- SNI certificate minting is arity-agnostic across ruby-openssl versions
  (callback args differ; a raise surfaced as an unrecognized-name alert).
- Proxy honors HTTP/1.1 framing per request: Content-Length bodies are
  forwarded exactly; chunked bodies and responses close-delimit.
- Bidirectional streaming terminates promptly on `Connection: close`
  (each pump direction closes its peer on EOF).
- `alias --remove` now appends the default TLD.
- Install generator `source_root` pointed at a doubled path; generator
  file checks now resolve against `destination_root`.
- Port-flag injection no longer double-sets an explicit `$PORT`.

## [0.1.0]

### Added

- Initial release: explicit-run reverse proxy giving every Ruby app a
  stable `https://<app>.localhost` URL.
- Zero-flag name inference (Rails module, gemspec, package.json, git
  root, directory) with `ask-local.json` overrides.
- `{variant}.{service}.{app}.{tld}` hostname composition; linked-worktree
  branch prefixes; custom `--tld` including owned domains.
- Managed Rack boot on unix sockets (rackup/TCP fallback); run mode with
  `PORT`/`ASK_LOCAL_URL` injection; `Procfile.dev` and static-site
  framework detection.
- Local CA + per-host SNI certs (in-memory LRU), `trust`, `hosts sync`,
  `doctor`, `prune`, `alias`, `get`, `kamal` snippet.
- Explicit `--port/--host` injection for port-ignoring CLIs (Jekyll,
  Middleman, Bridgetown), skipped when the user already set a port.

### Changed

- Rails module inference kebab-cases CamelCase and digit runs:
  `Rails8Min` → `rails-8-min` (was `rails8min`).
- Monorepo `ask-local.json` with an `apps:` map is discovered by walking
  up from the package directory.
- `service: web` produces the bare `app.tld` (all other services prefix).
- Puma 8 command shape (positional `config.ru`; `--rackup` was removed
  upstream) and spawned backends run unbundled so system/bundle puma is
  reachable regardless of the invoking bundle.
- Boot failures include the backend log tail in the error message.
