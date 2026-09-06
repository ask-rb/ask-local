# Changelog

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
  reports an unwritable state dir plainly.
- Bounded proxy concurrency (`ASK_LOCAL_MAX_CONNECTIONS`, 503 past the
  cap), mtime-TTL route cache, IPv4+IPv6 loopback listeners, dual-stack
  `ours?` health check.
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
- Ownership module: root write paths chown state back to the invoking
  user; `doctor` reports an unwritable state dir with the fix.
- Proxy hardening: bounded concurrency (503 past the cap), mtime-TTL
  route cache, IPv4+IPv6 loopback listeners, dual-stack health check,
  oversize-hostname refusal.
- `status` (effective naming context), `open [name]`, `log -f`;
  `stop` exit codes 0/2/3; `list` shows backend liveness.
- Sinatra-modular + foreman-`$PORT` fixtures; no-double-injection guard.
- SKILL.md "when NOT to use" section (CI, prod, Docker networks).
- Framework coverage: hanami2 slice layout, jekyll livereload second
  port (`--livereload-port` pinned next to the main port when
  `livereload: true`), roda-plugins managed boot; no-double-injection
  guard for explicit `$PORT`.
- Chunked request uploads pinned by test (streamed intact,
  close-delimited).
- README non-goals section (HTTP/2, tunnels, production) with rationale.
- `ask-local start`: one-setup-and-go entry point (setup-if-needed, then boot).
  `ask-local` bare stays as an alias for it; `ask-local setup` stays for explicit re-setup.
- `ask-local setup`: one-shot workstation setup (CA trust, port 443 via
  root service or sudo daemon, hosts sync, doctor verify) with a clear
  fix-it message on the first failure.
- No silent port fallback: privileged bind failure is a hard error
  pointing at `ask-local setup`, never a degraded `:1355` URL.
- Health probe tries plain HTTP before TLS (a TLS handshake against a
  foreign plain-HTTP server blocked in connect outside any timeout);
  responding foreign servers classify instantly, silent ones after the
  timeout rather than hanging forever.
- DNS-rebinding boundary: foreign Hosts get a bare 404; only our own
  TLDs see the route-listing 404. Proxy takes `--tld` (persisted) so the
  boundary follows custom domains.
- Log rotation (5MB, one generation) on proxy + backend logs; `doctor`
  disk-usage check.
- `--json` on list/status/doctor with stable keys; `status` sources made
  explicit (no more `(from -)`).
- Route cache keyed on file mtime (no TTL race for boot-then-curl);
  foreground supervision polls at 2Hz with the detached-children
  rationale documented.

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
- `base64` declared as a runtime dependency (left the default gems in
  Ruby 3.4).
- Missing `require "optparse"` lost in the CLI split.
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
