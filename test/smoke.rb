# frozen_string_literal: true

require "open3"

root = File.expand_path("..", __dir__)
files = %w[app.rb gui.rb pkg.rb]
failures = []

files.each do |file|
  stdout, stderr, status = Open3.capture3("ruby", "-c", File.join(root, file))
  if status.success?
    puts "PASS #{file}: #{stdout.strip}"
  else
    failures << file
    warn "FAIL #{file}: #{stderr}"
  end
end

abort "Syntax checks failed: #{failures.join(', ')}" unless failures.empty?
puts "All syntax checks passed."
