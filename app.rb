
require "fileutils"
require "json"
require "open3"
require "tempfile"
require "tmpdir"

begin
  require_relative "gui"
rescue LoadError
  # GUI is optional until import gui.
end

class Language
  MAX_INT = 2_147_483_647
  MAX_LONG = 9_223_372_036_854_775_807
  MAX_LONG_LONG = 10_000_000_000_000_000_000_000

  TYPES = %w[vs vf vi vb vl vll va].freeze

  PRECEDENCE = {
    "||" => 1,
    "&&" => 2,
    "==" => 3,
    "!=" => 3,
    "<" => 4,
    ">" => 4,
    "<=" => 4,
    ">=" => 4,
    "+" => 5,
    "-" => 5,
    "*" => 6,
    "/" => 6,
    "%" => 6
  }.freeze

  class ReturnSignal < StandardError
    attr_reader :value

    def initialize(value)
      @value = value
      super("return")
    end
  end

  def initialize
    @variables = {}
    @functions = {}
    @namespaces = {}
    @classes = {}
    @imports = {}
    @extensions = {}
    @keywords = {}

    @time_imported = false
    @gui_imported = false

    @tokens = []
    @position = 0
    @call_depth = 0
    @source_file = nil
    @error_count = 0
  end

  # ==========================================================
  # EXPRESSIONS
  # ==========================================================

  def tokenize(source)
    pattern = /\G\s*("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\d+(?:\.\d+)?|[A-Za-z_]\w*|::|==|!=|<=|>=|&&|\|\||[\[\](),.+*\/%!<>-])/

    tokens = []
    offset = 0

    while offset < source.length
      match = pattern.match(source, offset)

      unless match && match.begin(0) == offset
        break if source[offset..].strip.empty?
        raise SyntaxError, "Invalid expression near #{source[offset..]}"
      end

      tokens << match[1]
      offset = match.end(0)
    end

    tokens
  end

  def peek
    @tokens[@position]
  end

  def take
    value = peek
    @position += 1 unless value.nil?
    value
  end

  def expect(value)
    actual = take

    unless actual == value
      raise SyntaxError, "Expected #{value}, got #{actual.inspect}"
    end

    actual
  end

  def numeric(value)
    unless value.is_a?(Numeric)
      raise TypeError, "Expected number, got #{value.class}"
    end

    value
  end

  def truthy?(value)
    value != false && !value.nil?
  end

  def evaluate(source)
    old_tokens = @tokens
    old_position = @position

    @tokens = tokenize(source.to_s)
    @position = 0

    return nil if @tokens.empty?

    result = expression(0)

    if peek
      raise SyntaxError, "Unexpected token #{peek}"
    end

    result
  ensure
    @tokens = old_tokens
    @position = old_position
  end

  def decode_string(token)
    text = token[1...-1]

    text.gsub(/\\([ntr"'\\])/) do
      char = Regexp.last_match(1)

      {
        "n" => "\n",
        "t" => "\t",
        "r" => "\r",
        '"' => '"',
        "'" => "'",
        "\\" => "\\"
      }.fetch(char, char)
    end
  end

  def expression(minimum = 0)
    token = take

    raise SyntaxError, "Missing expression" unless token

    left =
      case token
      when "("
        value = expression(0)
        expect(")")
        value

      when "["
        values = []

        unless peek == "]"
          loop do
            values << expression(0)
            break unless peek == ","
            take
          end
        end

        expect("]")
        values

      when "-"
        -numeric(expression(7))

      when "+"
        numeric(expression(7))

      when "!"
        !truthy?(expression(7))

      when /\A\d+\.\d+\z/
        token.to_f

      when /\A\d+\z/
        token.to_i

      when /\A["']/
        decode_string(token)

      when "true"
        true

      when "false"
        false

      when "nil"
        nil

      else
        unless token.match?(/\A[A-Za-z_]\w*\z/)
          raise SyntaxError, "Unexpected token #{token}"
        end

        if peek == "." || peek == "::"
          separator = take
          method = take

          unless method&.match?(/\A[A-Za-z_]\w*\z/)
            raise SyntaxError, "Expected method name"
          end

          expect("(")
          args = parse_arguments
          scoped_call(token, separator, method, args)

        elsif peek == "("
          take
          args = parse_arguments
          call_function(token, args)

        else
          unless @variables.key?(token)
            raise NameError, "Unknown variable #{token}"
          end

          @variables[token][:value]
        end
      end

    # Postfix array indexing and value methods.
    loop do
      if peek == "["
        take
        index = evaluate_index
        expect("]")

        unless left.is_a?(Array) || left.is_a?(String)
          raise TypeError, "Cannot index #{left.class}"
        end

        left = left.fetch(index)

      elsif peek == "."
        take
        method = take

        case method
        when "its", "to_s", "str"
          left = left.to_s
        when "to_i", "int"
          left = Integer(left)
        when "to_f", "float"
          left = Float(left)
        when "length", "size"
          left = left.length
        when "first"
          left = left.first
        when "last"
          left = left.last
        when "reverse"
          left = left.reverse
        else
          raise NameError, "Unknown value method #{method}"
        end

      else
        break
      end
    end

    while (operator = peek) &&
          PRECEDENCE.fetch(operator, -1) >= minimum

      priority = PRECEDENCE[operator]
      take

      right = expression(priority + 1)
      left = calculate(left, operator, right)
    end

    left
  end

  def evaluate_index
    index = expression(0)

    unless index.is_a?(Integer)
      raise TypeError, "Array index must be an integer"
    end

    index
  end

  def parse_arguments
    args = []

    unless peek == ")"
      loop do
        args << expression(0)
        break unless peek == ","
        take
      end
    end

    expect(")")
    args
  end

  def calculate(a, operator, b)
    case operator
    when "+"
      if a.is_a?(Array) && b.is_a?(Array)
        a + b
      elsif a.is_a?(String) || b.is_a?(String)
        a.to_s + b.to_s
      else
        numeric(a) + numeric(b)
      end

    when "-"
      numeric(a) - numeric(b)

    when "*"
      numeric(a) * numeric(b)

    when "/"
      numeric(a)
      numeric(b)
      raise ZeroDivisionError, "Division by zero" if b == 0
      a.fdiv(b)

    when "%"
      numeric(a)
      numeric(b)
      raise ZeroDivisionError, "Modulo by zero" if b == 0
      a % b

    when "=="
      a == b

    when "!="
      a != b

    when "<", ">", "<=", ">="
      compatible =
        (a.is_a?(Numeric) && b.is_a?(Numeric)) ||
        (a.is_a?(String) && b.is_a?(String))

      raise TypeError, "Incompatible comparison" unless compatible

      a.public_send(operator, b)

    when "&&"
      truthy?(a) && truthy?(b)

    when "||"
      truthy?(a) || truthy?(b)

    else
      raise SyntaxError, "Unknown operator #{operator}"
    end
  end

  # ==========================================================
  # VARIABLES AND ARRAYS
  # ==========================================================

  def assign(name, value, type = nil)
    unless name.match?(/\A[A-Za-z_]\w*\z/)
      raise SyntaxError, "Invalid variable name #{name}"
    end

    if type.nil?
      unless @variables.key?(name)
        raise NameError, "Unknown variable #{name}"
      end

      type = @variables[name][:type]
    end

    case type
    when "vs"
      raise TypeError, "Expected string" unless value.is_a?(String)

    when "vf"
      numeric(value)
      value = value.to_f

    when "vi", "vl", "vll"
      raise TypeError, "Expected integer" unless value.is_a?(Integer)

      maximum = {
        "vi" => MAX_INT,
        "vl" => MAX_LONG,
        "vll" => MAX_LONG_LONG
      }.fetch(type)

      if value.abs > maximum
        raise RangeError, "#{type} overflow (max #{maximum})"
      end

    when "vb"
      unless value == true || value == false
        raise TypeError, "Expected boolean"
      end

    when "va"
      raise TypeError, "Expected array" unless value.is_a?(Array)

    when nil
      # Untyped function parameters.

    else
      raise TypeError, "Unknown type #{type}"
    end

    @variables[name] = {
      type: type,
      value: value
    }

    value
  end

  def set_array_item(name, index, value)
    entry = @variables[name]

    raise NameError, "Unknown array #{name}" unless entry
    raise TypeError, "#{name} is not an array" unless entry[:value].is_a?(Array)

    index = Integer(index)

    if index < 0
      raise RangeError, "Negative array assignment index"
    end

    if index > 1_000_000
      raise RangeError, "Array index too large"
    end

    entry[:value][index] = value
    value
  end

  # ==========================================================
  # INPUT
  # ==========================================================

  def read_input(prompt = "")
    print prompt
    STDOUT.flush

    value = STDIN.gets
    raise EOFError, "End of input" unless value

    value.chomp
  end

  def convert_input(value, type)
    case type
    when "vi", "vl", "vll"
      Integer(value)
    when "vf"
      Float(value)
    when "vb"
      unless %w[true false].include?(value)
        raise ArgumentError, "Expected true or false"
      end
      value == "true"
    else
      value
    end
  end

  def assignment_value(source, type)
    match = /\Astdin::c\s*<<\s*(.+)\z/.match(source)

    return evaluate(source) unless match

    prompt = evaluate(match[1])

    unless prompt.is_a?(String)
      raise TypeError, "Input prompt must be a string"
    end

    convert_input(read_input(prompt), type)
  end

  # ==========================================================
  # INTERPOLATION
  # ==========================================================

  def interpolate(text)
    # Rublang interpolation:
    # "Hello $&{name}"
    # "Count $&{count.its}"

    text.gsub(/\$&\{([^{}]+)\}/) do
      source = Regexp.last_match(1).strip

      if source =~ /\A(.+)\.its\s*\(.*\)\z/
        source = Regexp.last_match(1)
        evaluate(source).to_s
      else
        evaluate(source).to_s
      end
    end
  end

  def display_value(source)
    value = evaluate(source)

    if value.is_a?(String)
      interpolate(value)
    else
      value
    end
  end

  # ==========================================================
  # BUILT-IN FUNCTIONS
  # ==========================================================

  def fib(n)
    n = Integer(n)

    raise RangeError, "Negative Fibonacci index" if n < 0
    raise RangeError, "Fibonacci index too large" if n > 100_000

    a = 0
    b = 1

    n.times do
      a, b = b, a + b
    end

    a
  end

  def call_function(name, args)
    case name
    when "print"
      puts(*args)
      return nil

    when "str"
      check_args(name, args, 1)
      return args[0].to_s

    when "int"
      check_args(name, args, 1)
      return Integer(args[0])

    when "float"
      check_args(name, args, 1)
      return Float(args[0])

    when "len"
      check_args(name, args, 1)
      return args[0].length

    when "abs"
      check_args(name, args, 1)
      return numeric(args[0]).abs

    when "min"
      check_args(name, args, 2)
      return args.min

    when "max"
      check_args(name, args, 2)
      return args.max

    when "round"
      check_args(name, args, 1)
      return numeric(args[0]).round

    when "fib"
      check_args(name, args, 1)
      return fib(args[0])

    when "push"
      check_args(name, args, 2)
      raise TypeError, "Expected array" unless args[0].is_a?(Array)
      args[0] << args[1]
      return args[0]

    when "pop"
      check_args(name, args, 1)
      raise TypeError, "Expected array" unless args[0].is_a?(Array)
      return args[0].pop

    when "range"
      check_args(name, args, 2)
      return (Integer(args[0])..Integer(args[1])).to_a
    end

    function = @functions[name]

    raise NameError, "Unknown function #{name}" unless function

    invoke_function(function, args, name)
  end

  def check_args(name, args, expected)
    unless args.length == expected
      raise ArgumentError, "#{name} expects #{expected} arguments"
    end
  end

  # ==========================================================
  # FUNCTIONS, CLASSES, NAMESPACES
  # ==========================================================

  def parameters(source)
    return [] if source.strip.empty?

    params = source.split(",").map(&:strip)

    valid = params.all? do |param|
      param.match?(/\A[A-Za-z_]\w*\z/)
    end

    unless valid && params.uniq == params
      raise SyntaxError, "Invalid function parameters"
    end

    params
  end

  def invoke_function(function, args, name)
    expected = function[:params].length

    unless args.length == expected
      raise ArgumentError, "#{name} expects #{expected} arguments"
    end

    if @call_depth >= 100
      raise RangeError, "Function recursion limit reached"
    end

    previous = @variables
    @variables = previous.dup
    @call_depth += 1

    function[:params].zip(args).each do |param, value|
      @variables[param] = {
        type: nil,
        value: value
      }
    end

    begin
      execute(function[:body], true)
      nil
    rescue ReturnSignal => signal
      signal.value
    ensure
      @variables.each do |key, entry|
        if previous.key?(key) &&
           !function[:params].include?(key)
          previous[key] = entry
        end
      end

      @variables = previous
      @call_depth -= 1
    end
  end

  def define_scope(kind, name, body)
    table = kind == "namespace" ? @namespaces : @classes
    table[name] ||= {}

    index = 0

    while index < body.length
      line = body[index][:text]

      if line.empty? || comment_line?(line)
        index += 1
        next
      end

      match = /\Adef\s+([A-Za-z_]\w*)\s*\(([^()]*)\)\s*\z/.match(line)

      unless match
        raise SyntaxError, "Only methods allowed inside #{kind} #{name}"
      end

      method_name = match[1]
      params = parameters(match[2])

      method_body, last, middle = extract_block(body, index)

      raise SyntaxError, "Unexpected else" if middle

      table[name][method_name] = {
        params: params,
        body: method_body
      }

      index = last + 1
    end
  end

  def scoped_call(owner, separator, method, args)
    if owner == "GUI" && separator == "::"
      raise NameError, "Import gui first" unless @gui_imported
      raise LoadError, "GUI engine unavailable" unless defined?(RublangGUI)

      return RublangGUI.call(method, args)
    end

    if owner == "time" && separator == "."
      raise NameError, "Import time first" unless @time_imported

      if method == "sleep"
        check_args("time.sleep", args, 1)
        seconds = numeric(args[0])
        raise RangeError, "Negative sleep" if seconds < 0
        sleep(seconds)
        return nil
      end
    end

    table = separator == "." ? @namespaces : @classes
    scope = table[owner]

    unless scope
      raise NameError, "Unknown scope #{owner}"
    end

    function = scope[method]

    unless function
      raise NameError, "Unknown method #{owner}#{separator}#{method}"
    end

    invoke_function(function, args, "#{owner}#{separator}#{method}")
  end

  # ==========================================================
  # IMPORTS
  # ==========================================================

  def import_package(name)
    return if @imports[name]

    case name
    when "time"
      @time_imported = true
      @imports[name] = true
      return

    when "gui"
      raise LoadError, "GUI engine unavailable" unless defined?(RublangGUI)
      @gui_imported = true
      @imports[name] = true
      return
    end

    unless name.match?(/\A[A-Za-z][A-Za-z0-9_-]*\z/)
      raise SyntaxError, "Invalid package name #{name}"
    end

    directories = [Dir.pwd]
    directories.unshift(File.dirname(@source_file)) if @source_file

    paths = directories.uniq.flat_map do |directory|
      [
        File.join(directory, ".rublang", "packages", "#{name}.lang"),
        File.join(directory, ".rublang", "packages", name, "main.lang"),
        File.join(directory, "#{name}.lang")
      ]
    end

    path = paths.find { |candidate| File.file?(candidate) }

    unless path
      raise LoadError, "Package not installed: #{name}. Run ruby pkg.rb install ."
    end

    @imports[name] = true

    begin
      run(File.read(path))
    rescue Exception
      @imports.delete(name)
      raise
    end
  end

  # ==========================================================
  # COMMENTS
  # ==========================================================

  def comment_line?(line)
    line.start_with?("#", "//", "---")
  end

  def remove_comments(code)
    result = []
    in_comment = false

    code.each_line do |line|
      stripped = line.strip

      if in_comment
        if stripped.include?("+++")
          in_comment = false
          rest = stripped.split("+++", 2)[1].to_s
          result << rest + "\n"
        else
          result << "\n"
        end
        next
      end

      if stripped.start_with?("---")
        if stripped.include?("+++")
          rest = stripped.split("+++", 2)[1].to_s
          result << rest + "\n"
        else
          in_comment = true
          result << "\n"
        end
      elsif stripped.start_with?("#", "//")
        result << "\n"
      else
        result << line
      end
    end

    result.join
  end

  # ==========================================================
  # BLOCKS
  # ==========================================================

  def block_start?(line)
    return true if line.match?(/\A(?:if|while|def|namespace|class)\s+/)
    return true if line.match?(/\Atimes\s*\(.+\)\s+as\s+\w+\s*\{\s*\z/)
    return true if line.match?(/\Akeyword\s*\(.+\)\s*\{\s*\z/)
    return true if line.match?(/\Aext\s+extension\s+.+(?:\{)?\s*\z/)

    false
  end

  def extract_block(lines, start_index)
    depth = 1
    middle = nil
    index = start_index + 1

    while index < lines.length
      text = lines[index][:text]
      if lines[start_index][:text].start_with?("ext extension ")
        return [lines[(start_index + 1)...index], index, nil] if text == "end"
        index += 1
        next
      end

      depth += 1 if block_start?(text)

      if text == "end" || text == "}"
        depth -= 1

        if depth == 0
          body = lines[(start_index + 1)...index]
          return [body, index, middle]
        end

      elsif text == "else" && depth == 1
        middle = index
      end

      index += 1
    end

    number = lines[start_index][:number]

    raise SyntaxError, "Missing block ending at line #{number}"
  end

  # ==========================================================
  # TIMES LOOPS
  # ==========================================================

  def execute_times(count_source, variable, body, in_function)
    count = evaluate(count_source)

    unless count.is_a?(Integer)
      raise TypeError, "times expects an integer"
    end

    if count < 0 || count > 1_000_000
      raise RangeError, "times count must be 0..1000000"
    end

    previous = @variables[variable]

    begin
      count.times do |i|
        @variables[variable] = {
          type: "vi",
          value: i
        }

        execute(body, in_function)
      end
    ensure
      if previous
        @variables[variable] = previous
      else
        @variables.delete(variable)
      end
    end
  end

  # ==========================================================
  # RUBY KEYWORDS
  # ==========================================================

  def execute_keyword(name, body)
    ruby_code = body.map { |entry| entry[:raw] }.join("\n")

    @keywords[name] = ruby_code

    # Runs Ruby supplied in the .lang file.
    # Ruby output is inherited by Rublang.
    eval(ruby_code, TOPLEVEL_BINDING, "(rublang keyword #{name})")
  end

  # ==========================================================
  # EXTENSIONS: RUBY, C, C++
  # ==========================================================

  def execute_extension_languages(names, body)
    languages = names.split(",").map(&:strip)
    supported = ["Ruby", "Ruby Glimmer", "C", "C++"]

    languages.each do |lang|
      unless supported.include?(lang)
        raise ArgumentError, "Unknown extension: #{lang}"
      end
    end

    sections = {}
    languages.each { |lang| sections[lang] = [] }
    current = languages.first

    body.each do |entry|
      raw = entry[:raw]
      stripped = raw.strip

      if stripped.end_with?(":")
        label = stripped.delete_suffix(":")
        if languages.include?(label)
          current = label
          next
        end
      end

      sections[current] << raw
    end

    languages.each do |lang|
      source = sections[lang].join("\n")
      next if source.strip.empty?

      case lang
      when "Ruby"
        execute_ruby_extension(source, false)
      when "Ruby Glimmer"
        execute_ruby_extension(source, true)
      when "C"
        compile_extension(source, "gcc", ".c")
      when "C++"
        compile_extension(source, "g++", ".cpp")
      end
    end
  end

  def execute_ruby_extension(source, glimmer = false)
    Dir.mktmpdir("rublang-ruby-") do |dir|
      path = File.join(dir, "extension.rb")

      if glimmer
        source = "require 'glimmer-dsl-libui'\ninclude Glimmer\n" + source
      end

      File.write(path, source)

      success = system("ruby", path)

      unless success
        raise RuntimeError, "Ruby extension failed"
      end
    end
  end

  def compile_extension(source, compiler, suffix)
    unless system("which", compiler, out: File::NULL, err: File::NULL)
      raise LoadError, "#{compiler} not installed"
    end

    Dir.mktmpdir("rublang-ext-") do |directory|
      source_path = File.join(directory, "extension#{suffix}")
      output_path = File.join(directory, "extension")

      File.write(source_path, source)

      stdout, stderr, status = Open3.capture3(
        compiler, source_path, "-o", output_path
      )

      unless status.success?
        raise RuntimeError, "#{compiler} compilation failed:\n#{stderr}"
      end

      stdout, stderr, status = Open3.capture3(output_path)

      print stdout
      warn stderr unless stderr.empty?

      unless status.success?
        raise RuntimeError, "Extension exited with status #{status.exitstatus}"
      end
    end
  end

  # ==========================================================
  # SOUND
  # ==========================================================

  def play_sound(frequency, volume)
    frequency = numeric(frequency)
    volume = numeric(volume)

    unless frequency.between?(20, 20_000)
      raise RangeError, "Frequency must be 20..20000"
    end

    unless volume.between?(0, 1)
      raise RangeError, "Volume must be 0..1"
    end

    rate = 44_100

    samples = Array.new(rate / 2) do |i|
      sample = Math.sin(2 * Math::PI * frequency * i / rate) * [1.0, i/(rate*0.01), (rate/2-i)/(rate*0.02)].min.clamp(0,1)
      (128 + sample * 127 * volume).round.clamp(0, 255)
    end.pack("C*")

    if system("which", "aplay", out: File::NULL, err: File::NULL)
      IO.popen(
        ["aplay", "-q", "-t", "raw", "-r", rate.to_s, "-f", "U8"],
        "w"
      ) do |io|
        io.write(samples)
      end
    else
      warn "Sound unavailable: install alsa-utils"
    end
  end

  # ==========================================================
  # FILES AND SYSTEM
  # ==========================================================

  def split_args(source)
    return [] if source.strip.empty?

    result = []
    depth = 0
    quote = nil
    escaped = false
    start = 0

    source.each_char.with_index do |char, index|
      if escaped
        escaped = false
        next
      end

      if quote
        if char == "\\"
          escaped = true
        elsif char == quote
          quote = nil
        end
        next
      end

      if char == '"' || char == "'"
        quote = char
        next
      end

      case char
      when "(", "["
        depth += 1
      when ")", "]"
        depth -= 1
      when ","
        if depth == 0
          result << source[start...index].strip
          start = index + 1
        end
      end
    end

    result << source[start..].strip
    result
  end

  def execute_file_command(command, source)
    args = split_args(source)

    case command
    when "write", "append"
      check_args("File.#{command}", args, 2)

      filename = display_value(args[0]).to_s
      content = display_value(args[1]).to_s

      if command == "write"
        File.write(filename, content)
      else
        File.open(filename, "a") do |file|
          file.write(content)
        end
      end

    when "read"
      check_args("File.read", args, 1)
      puts File.read(evaluate(args[0]).to_s)

    when "delete"
      check_args("File.delete", args, 1)
      File.delete(evaluate(args[0]).to_s)

    when "exists"
      check_args("File.exists", args, 1)
      puts File.exist?(evaluate(args[0]).to_s)

    else
      raise NameError, "Unknown File command #{command}"
    end
  end

  def execute_system(source)
    command = display_value(source).to_s
    system(command)
  end

  # ==========================================================
  # ERRORS
  # ==========================================================

  def report_error(error, number)
    @error_count += 1

    prefix =
      case error
      when ZeroDivisionError
        "RublangError"
      when RangeError
        "RublangOverflow"
      when SyntaxError
        "RublangSyntaxError"
      else
        "RublangError"
      end

    warn "#{prefix} [line #{number}]: #{error.message}"
  end

  # ==========================================================
  # MAIN INTERPRETER
  # ==========================================================

  def execute(lines, in_function = false)
    index = 0

    while index < lines.length
      line = lines[index][:text]
      number = lines[index][:number]

      index += 1

      next if line.empty?
      next if comment_line?(line)

      begin
        case line

        # -----------------------
        # IMPORT
        # -----------------------

        when /\Aimport\s+([A-Za-z][A-Za-z0-9_-]*)\z/
          import_package(Regexp.last_match(1))

        # -----------------------
        # TIMES
        # -----------------------

        when /\Atimes\s*\((.+)\)\s+as\s+([A-Za-z_]\w*)\s*\{\s*\z/
          count_source, variable = Regexp.last_match.captures

          body, last, middle = extract_block(lines, index - 1)
          raise SyntaxError, "Unexpected else" if middle

          execute_times(count_source, variable, body, in_function)
          index = last + 1

        # -----------------------
        # KEYWORD
        # -----------------------

        when /\Akeyword\s*\((.+)\)\s*\{\s*\z/
          name = evaluate(Regexp.last_match(1)).to_s

          body, last, middle = extract_block(lines, index - 1)
          raise SyntaxError, "Unexpected else" if middle

          execute_keyword(name, body)
          index = last + 1

        # -----------------------
        # EXTENSION
        # -----------------------

        when /\Aext\s+extension\s+"([^"]+)"\s*\{?\s*\z/
          languages = Regexp.last_match(1)

          body, last, middle = extract_block(lines, index - 1)
          raise SyntaxError, "Unexpected else" if middle

          execute_extension_languages(languages, body)
          index = last + 1

        # -----------------------
        # STANDARD BLOCKS
        # -----------------------

        when /\A(?:if|while|def|namespace|class)\s+/
          body, last, middle = extract_block(lines, index - 1)

          if line.start_with?("namespace ", "class ")
            kind, name = line.split(/\s+/, 2)

            unless name.match?(/\A[A-Za-z_]\w*\z/)
              raise SyntaxError, "Invalid scope name"
            end

            define_scope(kind, name, body)

          elsif line.start_with?("if ")
            condition = truthy?(evaluate(line[3..]))

            chosen =
              if condition
                middle ? lines[index...middle] : body
              else
                middle ? lines[(middle + 1)...last] : []
              end

            execute(chosen, in_function)

          elsif line.start_with?("while ")
            iterations = 0
            condition_source = line[6..]

            while truthy?(evaluate(condition_source))
              iterations += 1

              if iterations > 1_000_000
                raise RangeError, "Loop limit reached"
              end

              execute(body, in_function)
            end

          else
            match = /\Adef\s+([A-Za-z_]\w*)\s*\(([^()]*)\)\s*\z/.match(line)

            unless match
              raise SyntaxError, "Expected def name(args)"
            end

            raise SyntaxError, "Unexpected else" if middle

            @functions[match[1]] = {
              params: parameters(match[2]),
              body: body
            }
          end

          index = last + 1

        # -----------------------
        # BLOCK ENDINGS
        # -----------------------

        when "end", "}", "else"
          raise SyntaxError, "Unexpected #{line}"

        # -----------------------
        # RETURN
        # -----------------------

        when /\Areturn(?:\s+(.+))?\z/
          unless in_function
            raise SyntaxError, "Return outside function"
          end

          source = Regexp.last_match(1)
          value = source ? evaluate(source) : nil

          raise ReturnSignal.new(value)

        # -----------------------
        # OUTPUT
        # -----------------------

        when /\Astdout::c\s*<<\s*(.+)\z/
          puts display_value(Regexp.last_match(1))

        when /\Astdout::print\s*<<\s*(.+)\z/
          print display_value(Regexp.last_match(1))
          STDOUT.flush

        # -----------------------
        # INPUT
        # -----------------------

        when /\Astdin::c\s*>>\s*([A-Za-z_]\w*)\z/
          name = Regexp.last_match(1)
          type = @variables.dig(name, :type) || "vs"

          value = convert_input(read_input("> "), type)
          assign(name, value, type)

        # -----------------------
        # SOUND
        # -----------------------

        when /\Asound::play\s*\((.*)\)\z/
          parts = split_args(Regexp.last_match(1))
          check_args("sound::play", parts, 2)

          frequency = evaluate(parts[0])
          volume = evaluate(parts[1])

          play_sound(frequency, volume)

        # -----------------------
        # FILE COMMANDS
        # -----------------------

        when /\AFile\.(write|append|read|delete|exists)\s+(.+)\z/
          command, source = Regexp.last_match.captures
          execute_file_command(command, source)

        # -----------------------
        # SYSTEM
        # -----------------------

        when /\Asystem\s+(.+)\z/
          execute_system(Regexp.last_match(1))

        # -----------------------
        # VARIABLES
        # -----------------------

        when /\A(vll|vs|vf|vi|vb|vl|va)\s+([A-Za-z_]\w*)\s*=\s*(.+)\z/
          type, name, source = Regexp.last_match.captures

          value = assignment_value(source, type)
          assign(name, value, type)

        # -----------------------
        # ARRAY ITEM ASSIGNMENT
        # -----------------------

        when /\A([A-Za-z_]\w*)\s*\[(.+)\]\s*=\s*(.+)\z/
          name, index_source, source = Regexp.last_match.captures

          array_index = evaluate(index_source)
          value = evaluate(source)

          set_array_item(name, array_index, value)

        # -----------------------
        # EXISTING VARIABLE
        # -----------------------

        when /\A([A-Za-z_]\w*)\s*=\s*(.+)\z/
          name, source = Regexp.last_match.captures

          unless @variables.key?(name)
            raise NameError, "Unknown variable #{name}"
          end

          type = @variables[name][:type]
          value = assignment_value(source, type)

          assign(name, value)

        # -----------------------
        # FUNCTION CALL
        # -----------------------

        when /\A[A-Za-z_]\w*(?:(?:\.|::)[A-Za-z_]\w*)?\s*\(.*\)\z/
          evaluate(line)

        else
          raise SyntaxError, "Unknown command: #{line}"
        end

      rescue ReturnSignal
        raise

      rescue ZeroDivisionError, RangeError, SyntaxError,
             StandardError, LoadError => error
        report_error(error, number)
      end
    end

    nil
  end

  # ==========================================================
  # RUN
  # ==========================================================

  def run(code)
    # Keep original source for raw Ruby/C/C++ blocks.
    original = code.each_line.to_a

    # Mask comments without changing line numbers.
    cleaned = remove_comments(code).each_line.to_a

    lines = cleaned.each_with_index.map do |line, index|
      {
        text: line.strip,
        raw: original[index].to_s.chomp,
        number: index + 1
      }
    end

    execute(lines)
  end

  def run_file(path)
    unless File.file?(path)
      raise LoadError, "File not found: #{path}"
    end

    previous = @source_file
    @source_file = File.expand_path(path)

    begin
      run(File.read(@source_file))
    ensure
      @source_file = previous
    end
  end

  def errors
    @error_count
  end
end

# ==========================================================
# ENTRY POINT
# ==========================================================

if __FILE__ == $PROGRAM_NAME
  begin
    unless ARGV.length == 1
      warn "Usage: ruby app.rb file.lang"
      exit 1
    end

    language = Language.new
    language.run_file(ARGV[0])

    exit(language.errors.zero? ? 0 : 1)

  rescue Interrupt
    puts "\nRublang interrupted."
    exit 130

  rescue ZeroDivisionError => error
    warn "RublangError: #{error.message}"
    exit 1

  rescue RangeError => error
    warn "RublangOverflow: #{error.message}"
    exit 1

  rescue SyntaxError => error
    warn "RublangSyntaxError: #{error.message}"
    exit 1

  rescue StandardError, LoadError => error
    warn "RublangError: #{error.message}"
    exit 1
  end
end
