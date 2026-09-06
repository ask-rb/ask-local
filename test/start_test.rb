# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class StartCommandTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @state = Dir.mktmpdir
    ENV["ASK_LOCAL_STATE_DIR"] = @state
  end

  def teardown
    ENV.delete("ASK_LOCAL_STATE_DIR")
    FileUtils.remove_entry(@dir) rescue nil
    FileUtils.remove_entry(@state) rescue nil
  end

  def capture
    out, err = StringIO.new, StringIO.new
    orig_out, orig_err = $stdout, $stderr
    $stdout, $stderr = out, err
    code = begin
      yield
      0
    rescue SystemExit => e
      e.status
    end
    [code, out.string, err.string]
  ensure
    $stdout, $stderr = orig_out, orig_err
  end

  def test_help_lists_usage_and_examples
    _code, out, = capture { Ask::Local::CLI::SystemCommand.start(Ask::Local::CLI::Context.new, ["--help"]) }
    assert_includes out, "ask-local start"
    assert_includes out, "ask-local start myapp"
    assert_includes out, "--name <name>"
  end

  def test_fast_path_skips_setup_when_healthy
    # All doctor checks ok => ensure_workstation! must NOT be called.
    Ask::Local::Doctor.stubs(:run).returns([
      Ask::Local::Doctor::Check.new(name: "state", ok: true, message: "writable"),
      Ask::Local::Doctor::Check.new(name: "disk", ok: true, message: "uses 0 B"),
      Ask::Local::Doctor::Check.new(name: "proxy", ok: true, message: "listening on port 443"),
      Ask::Local::Doctor::Check.new(name: "routes", ok: true, message: "no active routes"),
      Ask::Local::Doctor::Check.new(name: "dns", ok: true, message: "no routes to resolve"),
      Ask::Local::Doctor::Check.new(name: "ca", ok: true, message: "CA trusted")
    ])
    Ask::Local::CLI::SystemCommand.expects(:ensure_workstation!).never
    # Stub the boot so we don't actually try to bind a port.
    Ask::Local::CLI::BootCommand.expects(:run_inferred)
      .with { |ctx, _args| ctx.is_a?(Ask::Local::CLI::Context) }
      .returns(nil)

    Ask::Local::CLI::SystemCommand.start(Ask::Local::CLI::Context.new, [])
  end

  def test_triggers_setup_when_doctor_fails
    Ask::Local::Doctor.stubs(:run).returns([
      Ask::Local::Doctor::Check.new(name: "proxy", ok: false, message: "not running")
    ])
    Ask::Local::CLI::SystemCommand.expects(:ensure_workstation!).with { |ctx| ctx.is_a?(Ask::Local::CLI::Context) }
    Ask::Local::CLI::BootCommand.expects(:run_inferred).returns(nil)

    Ask::Local::CLI::SystemCommand.start(Ask::Local::CLI::Context.new, [])
  end

  def test_ensure_workstation_covers_ca_proxy_and_hosts
    ctx = Ask::Local::CLI::Context.new
    Ask::Local::Certs.stubs(:trusted?).returns(false)
    Ask::Local::Trust.stubs(:trust).returns({ trusted: true })
    Ask::Local::ProxyControl.stubs(:listening?).returns(false)
    Ask::Local::ProxyControl.stubs(:root?).returns(false)
    ctx.stubs(:interactive?).returns(false)
    code, _out, err = capture { Ask::Local::CLI::SystemCommand.ensure_workstation!(ctx) }
    assert_equal 1, code
    assert_includes err, "ask-local setup"
  end

  def test_setup_reached_via_noninteractive_proxy_error_points_at_setup
    Ask::Local::Certs.stubs(:trusted?).returns(true)
    Ask::Local::ProxyControl.stubs(:listening?).returns(false)
    Ask::Local::CLI::Context.any_instance.stubs(:interactive?).returns(false)
    ctx = Ask::Local::CLI::Context.new
    _code, _out, err = capture do
      Ask::Local::CLI::SystemCommand.ensure_workstation!(ctx)
    end
    assert_includes err, "ask-local setup"
  end
end
