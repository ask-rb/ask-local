# frozen_string_literal: true

require_relative "test_helper"

class ConfigTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_missing_config_returns_nil
    assert_nil Ask::Local::Config.load(@dir)
  end

  def test_loads_name
    File.write(File.join(@dir, "ask-local.json"), '{"name": "myapp"}')
    config = Ask::Local::Config.load(@dir)
    assert_equal "myapp", config["name"]
  end

  def test_invalid_json_raises_config_error
    File.write(File.join(@dir, "ask-local.json"), "{bad")
    assert_raises(Ask::Local::ConfigError) { Ask::Local::Config.load(@dir) }
  end

  def test_invalid_app_port_raises
    File.write(File.join(@dir, "ask-local.json"), '{"appPort": 99999}')
    assert_raises(Ask::Local::ConfigError) { Ask::Local::Config.load(@dir) }
  end

  def test_apps_map_resolves_nested_package
    File.write(File.join(@dir, "ask-local.json"),
      '{"apps": {"apps/web": {"name": "webapp"}}}')
    config = Ask::Local::Config.load(@dir)
    assert_equal({ "name" => "webapp" },
      config.app_config(File.join(@dir, "apps", "web")))
    assert_equal({}, config.app_config(File.join(@dir, "other")))
  end
end

class HostsTest < Minitest::Test
  H = Ask::Local::Hosts

  def test_managed_block_format
    block = H.managed_block(["b.localhost", "a.localhost"])
    assert_includes block, H::BEGIN_MARKER
    assert_includes block, "127.0.0.1 a.localhost"
    assert_includes block, H::END_MARKER
  end

  def test_sync_and_clean_roundtrip_in_tempfile
    path = File.join(Dir.mktmpdir, "hosts")
    File.write(path, "127.0.0.1 localhost\n")
    assert H.sync(["myapp.localhost"], path)
    assert_includes H.managed_hostnames(File.read(path)), "myapp.localhost"
    # Second sync replaces, not duplicates.
    assert H.sync(["other.localhost"], path)
    names = H.managed_hostnames(File.read(path))
    assert_equal ["other.localhost"], names
    assert H.clean(path)
    assert_equal [], H.managed_hostnames(File.read(path))
    assert_includes File.read(path), "127.0.0.1 localhost"
  end
end

class ResolverTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @orig_env = ENV.to_h
  end

  def teardown
    FileUtils.remove_entry(@dir)
    ENV.replace(@orig_env)
  end

  def test_flag_beats_env_beats_config
    File.write(File.join(@dir, "ask-local.json"), '{"name": "configname"}')
    ENV["ASK_LOCAL_NAME"] = "envname"
    r = Ask::Local::Resolver.resolve(@dir, name: "flagname")
    assert_equal "flagname", r.app
    assert_equal "flag", r.sources[:app]
    r = Ask::Local::Resolver.resolve(@dir)
    assert_equal "envname", r.app
    ENV.delete("ASK_LOCAL_NAME")
    r = Ask::Local::Resolver.resolve(@dir)
    assert_equal "configname", r.app
  end

  def test_tld_parsing_and_validation
    r = Ask::Local::Resolver.resolve(@dir, tlds: "Localhost,preview.example.com")
    assert_equal ["localhost", "preview.example.com"], r.tlds
    assert_raises(Ask::Local::ConfigError) do
      Ask::Local::Resolver.resolve(@dir, tlds: "BAD TLD!")
    end
  end

  def test_hostnames_compose_all_axes
    r = Ask::Local::Resolver.resolve(@dir, name: "MyApp", service: "API",
      variant: "Fix_UI", tlds: "localhost")
    assert_equal ["fix-ui.api.myapp.localhost"], Ask::Local::Resolver.hostnames(r)
  end
end

class PortsTest < Minitest::Test
  def test_finds_free_port_in_range
    port = Ask::Local::Ports.find_free
    assert port.between?(4000, 4999)
    assert Ask::Local::Ports.free?(port)
  end

  def test_skips_blocked_ports
    # Occupy nothing; just verify blocked ports never returned over many draws.
    20.times do
      port = Ask::Local::Ports.find_free
      refute Ask::Local::Ports::BLOCKED[port], "returned blocked port #{port}"
    end
  end
end

class VersionTest < Minitest::Test
  def test_version_format
    assert_match(/\A\d+\.\d+\.\d+\z/, Ask::Local::VERSION)
  end
end

class GemspecTest < Minitest::Test
  def test_gemspec_valid
    spec = Gem::Specification.load(File.expand_path("../ask-local.gemspec", __dir__))
    refute_nil spec
    assert_equal "ask-local", spec.name
  end
end
