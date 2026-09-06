# frozen_string_literal: true

module Ask
  module Local
    # Resolve the effective {app, service, variant, tlds} for a directory.
    #
    # Precedence per axis: CLI flag > ENV > ask-local.json > inference.
    # Variant adds linked-worktree branch and opt-in current branch.
    module Resolver
      module_function

      Result = Struct.new(:app, :service, :variant, :tlds, :sources, keyword_init: true)

      def resolve(dir = Dir.pwd, name: nil, service: nil, variant: nil,
        tlds: nil, use_branch: false)
        config, config_dir = find_config(dir)
        app_cfg = config ? config.app_config(dir) : {}
        config_source = config_dir ? "ask-local.json (#{relative_label(config_dir, dir)})" : "ask-local.json"

        app, app_source = first_present(
          [name, "flag"],
          [ENV["ASK_LOCAL_NAME"], "ASK_LOCAL_NAME"],
          [app_cfg["name"], config_source],
          [Inference.infer(dir), :infer]
        )
        app, app_source = app_source == :infer ? app : [app, app_source]

        service, service_source = first_present(
          [service, "flag"],
          [ENV["ASK_LOCAL_SERVICE"], "ASK_LOCAL_SERVICE"],
          [app_cfg["service"], config_source]
        )

        variant_value, variant_source = if !variant.nil? || ENV["ASK_LOCAL_VARIANT"] || app_cfg["variant"]
          first_present(
            [variant, "flag"],
            [ENV["ASK_LOCAL_VARIANT"], "ASK_LOCAL_VARIANT"],
            [app_cfg["variant"], config_source]
          )
        else
          Variant.resolve(dir, use_branch: use_branch) || [nil, nil]
        end

        tld_list = parse_tlds(tlds) || parse_tlds(ENV["ASK_LOCAL_TLD"]) ||
          Array(app_cfg["tlds"]) || [Hostname::DEFAULT_TLD]
        tld_list = [Hostname::DEFAULT_TLD] if tld_list.empty?
        tld_list.each do |tld|
          raise ConfigError, "Invalid TLD #{tld.inspect}" unless Sanitize.valid_tld?(tld.downcase)
        end
        tld_list = tld_list.map(&:downcase).uniq

        Result.new(
          app: Sanitize.hostname_label(app),
          service: service && Sanitize.hostname_label(service),
          variant: variant_value && Sanitize.hostname_label(variant_value),
          tlds: tld_list,
          sources: { app: app_source, service: service_source, variant: variant_source }
        )
      end

      def hostnames(result)
        Hostname.build(app: result.app, service: result.service,
          variant: result.variant, tlds: result.tlds)
      end

      # Walk up for the nearest ask-local.json; a root with an "apps" map
      # covers subdirectories (monorepo). A nearer config without a match
      # does not block a farther one with an apps entry.
      def find_config(dir)
        current = File.expand_path(dir)
        fallback = nil
        loop do
          begin
            loaded = Config.load(current)
            if loaded
              if loaded.data["apps"].is_a?(Hash)
                return [loaded, current]
              else
                fallback ||= [loaded, current]
              end
            end
          rescue ConfigError
            nil
          end
          parent = File.dirname(current)
          break if parent == current

          current = parent
        end
        fallback || [nil, nil]
      end

      def relative_label(config_dir, dir)
        return "." if File.expand_path(config_dir) == File.expand_path(dir)

        require "pathname"
        Pathname.new(File.expand_path(dir))
          .relative_path_from(Pathname.new(File.expand_path(config_dir))).to_s
      rescue ArgumentError
        "."
      end

      # NOTE: no `private` keyword here — it would cancel
      # `module_function` mode (see Variant for details).
      def first_present(*pairs)
        pairs.each do |value, source|
          if source == :infer
            inferred, from = value
            return [inferred, from] unless inferred.nil? || inferred.to_s.empty?
          elsif !value.nil? && !value.to_s.strip.empty?
            return [value.to_s.strip, source]
          end
        end
        [nil, nil]
      end

      def parse_tlds(value)
        return nil if value.nil?
        return value.map(&:to_s) if value.is_a?(Array)

        parts = value.to_s.split(",").map(&:strip).reject(&:empty?)
        parts.empty? ? nil : parts
      end
    end
  end
end
