
require "json"
require "uri"
require "net/http"
require "fileutils"
require "digest"

class PackageManager
  ROOT = File.expand_path(".rublang", Dir.pwd)
  PACKAGES = File.join(ROOT, "packages")
  REGISTRY = File.join(ROOT, "registry.json")
  MAX_SIZE = 1_000_000

  def initialize
    FileUtils.mkdir_p(PACKAGES)
  end

  def registry
    return {} unless File.file?(REGISTRY)
    JSON.parse(File.read(REGISTRY))
  end

  def safe_name(name)
    unless name.is_a?(String) &&
           name.match?(/\A[a-zA-Z][a-zA-Z0-9_-]*\z/)
      raise ArgumentError, "Invalid package name"
    end
    name
  end

  def package_path(name)
    File.join(PACKAGES, "#{safe_name(name)}.lang")
  end

  def check_size(bytes)
    if bytes.bytesize > MAX_SIZE
      raise RangeError, "Package exceeds 1 MB limit"
    end
  end

  def install_local
    manifest_path = File.join(Dir.pwd, "rublang.json")

    unless File.file?(manifest_path)
      raise "Missing rublang.json"
    end

    manifest = JSON.parse(File.read(manifest_path))

    name = safe_name(manifest.fetch("name"))
    entry = manifest.fetch("entry")

    unless entry.is_a?(String) &&
           entry.match?(/\A[a-zA-Z0-9_-]+\.lang\z/)
      raise "Invalid package entry"
    end

    unless File.file?(entry)
      raise "Entry file not found: #{entry}"
    end

    bytes = File.binread(entry)
    check_size(bytes)

    File.binwrite(package_path(name), bytes)

    puts "Installed #{name}"
    puts "Version: #{manifest.fetch('version', 'unknown')}"
  end

  def install_url(source)
    uri = URI.parse(source)

    unless uri.is_a?(URI::HTTPS)
      raise "Only HTTPS URLs are supported"
    end

    found = registry.find do |_name, record|
      record.is_a?(Hash) && record["url"] == source
    end

    raise "URL is not registered" unless found

    name, record = found
    safe_name(name)

    expected = record.fetch("sha256")

    unless expected.is_a?(String) &&
           expected.match?(/\A[0-9a-f]{64}\z/)
      raise "Invalid SHA256 in registry"
    end

    puts "Fetching #{name}..."

    response = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: true,
      open_timeout: 8,
      read_timeout: 15
    ) do |http|
      http.get(uri.request_uri)
    end

    unless response.is_a?(Net::HTTPSuccess)
      raise "HTTP error #{response.code}"
    end

    bytes = response.body
    check_size(bytes)

    actual = Digest::SHA256.hexdigest(bytes)

    unless actual == expected
      raise "SHA256 mismatch: package verification failed"
    end

    File.binwrite(package_path(name), bytes)

    puts "Installed #{name}"
    puts "SHA256 verified."
  end

  def install(source)
    if source == "."
      install_local
    elsif source.start_with?("https://")
      install_url(source)
    else
      raise "Use . or a registered HTTPS URL"
    end
  end

  def list
    paths = Dir.glob(File.join(PACKAGES, "*.lang")).sort

    if paths.empty?
      puts "No packages installed."
      return
    end

    puts "Installed Rublang packages:"

    paths.each do |path|
      puts " - #{File.basename(path, '.lang')}"
    end
  end

  def remove(name)
    path = package_path(name)

    unless File.file?(path)
      raise "Package not installed: #{name}"
    end

    File.delete(path)
    puts "Removed #{name}"
  end

  def register(name, url, sha256)
    safe_name(name)

    uri = URI.parse(url)

    unless uri.is_a?(URI::HTTPS)
      raise "Registry URLs must use HTTPS"
    end

    unless sha256.match?(/\A[0-9a-f]{64}\z/)
      raise "SHA256 must be 64 lowercase hexadecimal characters"
    end

    data = registry

    data[name] = {
      "url" => url,
      "sha256" => sha256
    }

    File.write(REGISTRY, JSON.pretty_generate(data))

    puts "Registered #{name}"
  end

  def run(path)
    unless File.file?(path)
      raise "Program not found: #{path}"
    end

    require_relative "rublang"

    Language.new.run(File.read(path))
  end

  def help
    puts <<~HELP
      RUBLANG PACKAGE MANAGER

      ruby app.rb install .
      ruby app.rb install URL
      ruby app.rb list
      ruby app.rb remove NAME
      ruby app.rb register NAME URL SHA256
      ruby app.rb run FILE

      Packages are stored in:
      #{PACKAGES}
    HELP
  end

  def execute(args)
    command = args.shift

    case command
    when "install"
      raise "Missing source" unless args.length == 1
      install(args[0])

    when "list"
      list

    when "remove"
      raise "Missing package name" unless args.length == 1
      remove(args[0])

    when "register"
      unless args.length == 3
        raise "Usage: register NAME URL SHA256"
      end
      register(*args)

    when "run"
      raise "Missing program" unless args.length == 1
      run(args[0])

    when "help", nil
      help

    else
      raise "Unknown command: #{command}"
    end
  end
end

begin
  PackageManager.new.execute(ARGV)

rescue ZeroDivisionError => e
  warn "PackageError: Division by zero: #{e.message}"
  exit 1

rescue RangeError => e
  warn "PackageError: Range error: #{e.message}"
  exit 1

rescue JSON::ParserError => e
  warn "PackageError: Invalid JSON: #{e.message}"
  exit 1

rescue Errno::ENOENT => e
  warn "PackageError: Missing file: #{e.message}"
  exit 1

rescue StandardError => e
  warn "PackageError: #{e.message}"
  exit 1
end
