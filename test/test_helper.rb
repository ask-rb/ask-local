# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "ask-local"
require "minitest/autorun"
require "mocha/minitest"
require "tmpdir"
require "fileutils"
