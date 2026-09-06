# frozen_string_literal: true

require_relative "test_helper"

# CLI smoke tests: --help, --version, get, list, doctor, kamal, alias.
# Full boot paths (managed/run) are covered by manual QA; these pin the
# read-only surface agents depend on. DNS is stubbed: real resolution
# has no timeout guarantees in sandboxed CI.
class CLITest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @orig_state = ENV["ASK_LOCAL_STATE_DIR"]
    ENV["ASK_LOCAL_STATE_DIR"] = @dir
    Ask::Local::Hosts.stubs(:unresolved).returns([])
  end

  def teardown
    FileUtils.remove_entry(@dir)
    ENV["ASK_LOCAL_STATE_DIR"] = @orig_state
  end

  def run_cli(*args)
    out = StringIO.new
    orig = $stdout
    $stdout = out
    code = begin
      Ask::Local::CLI.run(args)
    rescue SystemExit => e
      e.status
    end
    [code, out.string]
  ensure
    $stdout = orig
  end

  def test_help
    code, out = run_cli("--help")
    assert_equal 0, code
    assert_includes out, "ask-local"
  end

  def test_version
    code, out = run_cli("--version")
    assert_equal 0, code
    assert_includes out, Ask::Local::VERSION
  end

  def test_get_prints_url
    code, out = run_cli("get", "backend")
    assert_equal 0, code
    assert_includes out, "https://backend.localhost"
  end

  def test_list_empty
    code, out = run_cli("list")
    assert_equal 0, code
    assert_includes out, "No active routes"
  end

  def test_alias_and_list_and_remove
    run_cli("alias", "dockerapp", "8080")
    _c, out = run_cli("list")
    assert_includes out, "dockerapp.localhost"
    assert_includes out, "127.0.0.1:8080"
    run_cli("alias", "--remove", "dockerapp")
    _c, out = run_cli("list")
    assert_includes out, "No active routes"
  end

  def test_doctor_reports_proxy_down_but_passes_dns
    code, out = run_cli("doctor")
    assert_equal 1, code
    assert_includes out, "proxy"
    assert_includes out, "[ok] dns"
  end

  def test_kamal_snippet_resolves_app_from_flag
    code, out = run_cli("kamal", "fix-ui", "--app", "myapp",
      "--domain", "preview.example.com")
    assert_equal 0, code
    assert_includes out, "myapp-fix-ui.preview.example.com"
  end

  def test_kamal_snippet_inherits_app_from_directory
    code, out = run_cli("kamal", "demo")
    assert_equal 0, code
    # cwd here is the ask-local repo -> gemspec name.
    assert_match(%r{\A#.*\nproxy:\n  ssl: true\n  hosts:\n    - ask-local-demo\.preview\.example\.com\n}, out)
  end

  def test_get_inherits_variant_from_env
    ENV["ASK_LOCAL_VARIANT"] = "fix-ui"
    code, out = run_cli("get", "backend")
    assert_equal 0, code
    assert_includes out, "https://fix-ui.backend.localhost"
  ensure
    ENV.delete("ASK_LOCAL_VARIANT")
  end

  def test_alias_accepts_full_hostname
    code, out = run_cli("alias", "web.preview.example.com", "9292")
    assert_equal 0, code
    _c, out = run_cli("list")
    assert_includes out, "web.preview.example.com"
  end

  def test_alias_uses_ask_local_tld
    ENV["ASK_LOCAL_TLD"] = "preview.example.com"
    run_cli("alias", "dockerapp", "8080")
    _c, out = run_cli("list")
    assert_includes out, "dockerapp.preview.example.com"
  ensure
    ENV.delete("ASK_LOCAL_TLD")
  end

  def test_unknown_flag_errors
    code, _out = run_cli("run", "--bogus")
    assert_equal 1, code
  end
end
