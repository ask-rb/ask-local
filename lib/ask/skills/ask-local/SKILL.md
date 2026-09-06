---
name: ask-local
description: Run Ruby apps through ask-local for stable named .localhost URLs (e.g. https://myapp.localhost instead of http://localhost:3000). Use when booting dev servers (Rails, Rack, Roda, Sinatra, Jekyll, Procfile apps), wiring frontend to API, configuring OAuth callbacks or webhooks, debugging port conflicts, or working in git worktrees.
---

# Local Dev with ask-local

Never invent ports. Never parse them from logs. Every app has a stable URL.

## Booting apps

```bash
ask-local                        # infer name, boot -> https://<app>.localhost
ask-local --service api          # -> https://api.myapp.localhost
ask-local run -- bin/dev         # Procfile apps, PORT injected
ask-local run --proc worker      # boot a specific Procfile process
```

Managed apps are supervised by the proxy daemon: they idle-stop after 15
minutes (`ASK_LOCAL_IDLE_TIMEOUT`), stop when `tmp/restart.txt` is
touched, and boot again on the next request.

## Lifecycle

```bash
ask-local stop                   # stop this app's backend + routes
ask-local restart                # touch tmp/restart.txt (supervised reboot)
ask-local log [n]                # tail this app's backend log
```

The runner injects `ASK_LOCAL_URL`, `PORT`, and `HOST=127.0.0.1` into the
child. In Rails, read it via `Ask::Local::Rails.url` — never hardcode
`localhost:3000`.

## Cross-service wiring

```bash
ask-local get backend            # -> https://backend.localhost
```

Use `get` output for frontend-to-API URLs, Cable URLs, and webhook
targets. Do not guess ports.

## Variants (worktrees, branches, demos)

Hostnames compose as `{variant}.{service}.{app}.{tld}`. Linked worktrees
get a branch prefix automatically (`fix-ui.myapp.localhost`); main keeps
the bare name. Override with `--variant` or `ASK_LOCAL_VARIANT`.

## OAuth and webhooks

Build callback URLs from `ASK_LOCAL_URL`:

```ruby
callback = "#{Ask::Local::Rails.url}/auth/google/callback"
```

Strict providers (Google, Apple) reject `.localhost`. Serve the app on a
domain you own instead — no code change:

```bash
ask-local --tld local.example.com   # -> https://myapp.local.example.com
```

## Troubleshooting

```bash
ask-local doctor                 # read-only: proxy, routes, DNS, CA trust
ask-local list                   # active routes
ask-local prune                  # clear stale routes from crashed sessions
```

Prefer `list --json`, `status --json`, and `doctor --json` when parsing
output programmatically — stable keys, no prose scraping.

If a hostname does not resolve: `ask-local hosts sync`. If the browser
warns about TLS: `ask-local trust`. Never run dev servers on bare ports
alongside ask-local — they bypass routing and reintroduce conflicts.

## When NOT to use ask-local

- **CI pipelines**: no TTY, no sudo, no browsers. Run the app's own test
  command directly; ask-local fails fast here by design.
- **Production consoles and servers**: the proxy binds loopback only and
  the CA is self-signed. Use Kamal + kamal-proxy for anything real.
- **Docker-internal networking**: containers reach each other by service
  name on the compose network, not via the host's `.localhost`.
- **Debugging the proxy itself**: use `ask-local proxy start --foreground`
  and read the log; do not layer another ask-local on top.
