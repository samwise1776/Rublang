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

# Verify actual interpreter behavior without executing a .lang program.
require File.join(root, "app")
language = Language.new

cases = {
  'factorial(5)' => 120,
  'factorial(0)' => 1,
  'pow(2, 8)' => 256,
  'sqrt(81)' => 9.0,
  'floor(3.9)' => 3,
  'ceil(3.1)' => 4,
  'sum([1, 2, 3])' => 6,
  'average([2, 4, 6])' => 4.0,
  'sort([3, 1, 2])' => [1, 2, 3],
  'unique([2, 2, 1])' => [2, 1],
  'join(["a", "b"], "-")' => "a-b",
  'split("a,b", ",")' => ["a", "b"],
  'replace("banana", "na", "NO")' => "baNONO",
  'upper("hello")' => "HELLO",
  'lower("HELLO")' => "hello",
  'trim(" hi ")' => "hi",
  'contains("hello", "ell")' => true,
  'starts_with("hello", "he")' => true,
  'ends_with("hello", "lo")' => true,
  'json_encode([1, 2])' => "[1,2]",
  'json_decode("[1,2]")' => [1, 2],
  'type_of(123)' => "int"
}

cases.each do |source, expected|
  actual = language.evaluate(source)
  abort "FAIL #{source}: expected #{expected.inspect}, got #{actual.inspect}" unless actual == expected
  puts "PASS #{source}"
end

begin
  language.evaluate("factorial(-1)")
  abort "FAIL factorial(-1): expected RangeError"
rescue RangeError
  puts "PASS factorial(-1) raises RangeError"
end

puts "All #{cases.length + 1} interpreter assertions passed."
