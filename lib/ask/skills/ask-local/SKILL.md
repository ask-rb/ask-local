---
name: ask-local
description: Run Ruby apps through ask-local for stable named .localhost URLs (e.g. https://myapp.localhost instead of http://localhost:3000). Use when booting dev servers (Rails, Rack, Roda, Sinatra, Jekyll), wiring frontend to API, configuring OAuth callbacks or webhooks, debugging port conflicts, or working in git worktrees.
---

# Local Dev with ask-local

Never invent ports. Never parse them from logs. Every app has a stable URL.

## One file, one command

Every app declares `config/local.yml` — the single source of truth:

```yaml
service: myapp
proxy:
  tld: localhost
processes:
  web:
    cmd: bundle exec puma -b tcp://127.0.0.1:$PORT config.ru
    proxy: true          # gets https://myapp.localhost
  worker:
    cmd: bundle exec sidekiq
    proxy: false         # background, supervised, no URL
env:
  clear:
    RAILS_ENV: development
```

If the file is missing, ask-local prints `Run ask-local init`. Generate it
with `ask-local init` (migrates an existing Procfile). Rails apps need
no extra gem — the proxied hostname is allowed automatically via
`RAILS_DEVELOPMENT_HOSTS`.

```bash
ask-local start          # setup if needed, then boot every process
ask-local                # same as start
ask-local stop           # stop this app's backend + routes
ask-local status         # show service, processes, and URLs
ask-local log [-f]       # tail the web process log
```

`$PORT` and `ASK_LOCAL_URL` are injected per process; HTTP processes get
stable URLs, background ones are supervised without routes. A process
that exits cleans up the whole tree.

## Cross-service wiring

```bash
ask-local get backend            # -> https://backend.localhost
ask-local get backend --variant demo
```

Use `get` output for frontend-to-API URLs, Cable URLs, and webhook
targets. Do not guess ports.

## Variants are files

A variant is a file overlay, Kamal-style: `config/local.<variant>.yml`
deep-merges over `config/local.yml`. Select it with `ASK_LOCAL_VARIANT`
or `--variant`. Worktrees get a branch prefix automatically.

```bash
ASK_LOCAL_VARIANT=fix-ui ask-local    # boots with config/local.fix-ui.yml merged
```

## First time on a machine

Run `ask-local start` — it does the one-shot CA trust, port 443, and
hosts sync if anything is missing, then boots. Prefer `ask-local setup`
for workstation setup without booting. If any command fails with a
privileged-port error, do not work around it with `-p` — run
`ask-local setup` instead. A `:port` suffix in a URL means someone
explicitly opted into it.

## OAuth and webhooks

Build callback URLs from `ASK_LOCAL_URL` (injected into every HTTP
process):

```ruby
callback = "#{Ask::Local::Rails.url}/auth/google/callback"
```

Strict providers (Google, Apple) reject `.localhost`. Serve the app on a
domain you own instead — no code change, just config:

```yaml
proxy:
  host: myapp.local.example.com   # instead of tld: localhost
```

## Troubleshooting

```bash
ask-local doctor                 # read-only: proxy, routes, DNS, CA trust
ask-local list --json            # routes as stable JSON
ask-local prune                  # clear stale routes from crashed sessions
```

If a hostname does not resolve: `ask-local hosts sync`. If the browser
warns about TLS: `ask-local trust`.

## When NOT to use ask-local

- **CI pipelines**: no TTY, no sudo, no browsers. Run the app's own test
  command directly; ask-local fails fast here by design.
- **Production consoles and servers**: the proxy binds loopback only and
  the CA is self-signed. Use Kamal + kamal-proxy for anything real.
- **Docker-internal networking**: containers reach each other by service
  name on the compose network, not via the host's `.localhost`.
- **Debugging the proxy itself**: use `ask-local proxy start --foreground`
  and read the log; do not layer another ask-local on top.
