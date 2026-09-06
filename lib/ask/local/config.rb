# frozen_string_literal: true

require "json"

module Ask
  module Local
    # Optional ask-local.json in the app directory.
    #
    #   { "name": "myapp" }
    #   { "name": "myapp", "service": "api", "variant": "demo",
    #     "tlds": ["localhost"], "appPort": 3000 }
    #
    # Monorepo roots may add an "apps" map keyed by path relative to the
    # config dir; top-level fields apply only in single-app mode.
    class Config
      FILENAME = "ask-local.json"
      TOP_KEYS = %w[name service variant tlds appPort proxy apps].freeze
      APP_KEYS = %w[name service variant tlds appPort proxy].freeze

      attr_reader :data, :dir

      def self.load(dir = Dir.pwd)
        path = File.join(dir, FILENAME)
        return nil unless File.file?(path)

        parsed = JSON.parse(File.read(path))
        raise ConfigError, "#{path} must be a JSON object" unless parsed.is_a?(Hash)

        new(parsed, dir, path)
      rescue JSON::ParserError => e
        raise ConfigError, "Invalid JSON in #{path}: #{e.message}"
      end

      def initialize(data, dir, path = FILENAME)
        @data = data
        @dir = dir
        @path = path
        validate!
      end

      def app_config(package_dir = dir)
        return slice(APP_KEYS) unless data["apps"].is_a?(Hash)

        rel = relative(package_dir)
        return {} if rel.nil? || rel.start_with?("..")

        candidate = rel
        loop do
          hit = data["apps"][candidate]
          return hit.select { |k, _| APP_KEYS.include?(k) } if hit.is_a?(Hash)

          parent = File.dirname(candidate)
          break if parent == "." || parent == candidate

          candidate = parent
        end
        {}
      end

      def [](key)
        data[key]
      end

      private

      def slice(keys)
        data.select { |k, _| keys.include?(k) }
      end

      def relative(package_dir)
        require "pathname"
        Pathname.new(File.expand_path(package_dir))
          .relative_path_from(Pathname.new(File.expand_path(dir))).to_s
      rescue ArgumentError
        nil
      end

      def validate!
        data.each_key do |key|
          warn "Warning: Unknown key #{key.inspect} in #{@path}. Known keys: #{TOP_KEYS.join(", ")}" unless TOP_KEYS.include?(key)
        end
        validate_app_fields(data, "top level")
        if data["apps"]
          raise ConfigError, %("apps" in #{@path} must be an object) unless data["apps"].is_a?(Hash)

          data["apps"].each do |name, entry|
            raise ConfigError, %("apps.#{name}" in #{@path} must be an object) unless entry.is_a?(Hash)

            validate_app_fields(entry, "apps.#{name}")
          end
        end
      end

      def validate_app_fields(fields, prefix)
        if fields["appPort"] && !(fields["appPort"].is_a?(Integer) && fields["appPort"].between?(1, 65_535))
          raise ConfigError, %("#{prefix}.appPort" in #{@path} must be an integer 1-65535)
        end
        if fields.key?("proxy") && ![true, false].include?(fields["proxy"])
          raise ConfigError, %("#{prefix}.proxy" in #{@path} must be a boolean)
        end
        %w[name service variant].each do |key|
          next unless fields.key?(key)
          next if fields[key].is_a?(String) && !fields[key].strip.empty?

          raise ConfigError, %("#{prefix}.#{key}" in #{@path} must be a non-empty string)
        end
        if fields["tlds"] && !(fields["tlds"].is_a?(Array) && fields["tlds"].all? { |t| t.is_a?(String) })
          raise ConfigError, %("#{prefix}.tlds" in #{@path} must be an array of strings)
        end
      end
    end
  end
end
