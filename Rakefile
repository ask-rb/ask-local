# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

# Heavy end-to-end tests (real daemon spawn, TLS handshakes, live Puma
# boots) live apart so the default suite stays fast. CI runs both.
def e2e_files
  FileList["test/proxy_lifecycle_test.rb"] +
    FileList["test/supervisor_test.rb"] +
    FileList["test/e2e/**/*_test.rb"]
end

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"].to_a - e2e_files.to_a
end

Rake::TestTask.new("test:e2e") do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = e2e_files
end

Rake::TestTask.new("test:all") do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

task default: :test
