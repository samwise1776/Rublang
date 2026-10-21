
require "fileutils"
require "json"
require_relative "gui"

class Language
  MAX_INT = 2_147_483_647
  MAX_LONG = 9_223_372_036_854_775_807
  MAX_LONG_LONG = 10_000_000_000_000_000_000

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

  TYPES = %w[vs vf vi vb vl vll].freeze

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
    @time_imported = false
    @gui_imported = false
    @call_depth = 0
    @tokens = []
    @position = 0
    @source_file = nil
    @current_line = nil
    @error_count = 0
  end

  def tokenize(source)
    pattern = /\G\s*("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\d+(?:\.\d+)?|[A-Za-z_]\w*|::|==|!=|<=|>=|&&|\|\||[.()+*\/%!,<>-])/

    tokens = []
    offset = 0

    while offset < source.length
      match = pattern.match(source, offset)

      unless match && match.begin(0) == offset
        break if source[offset..].strip.empty?

        raise SyntaxError,
              "Invalid expression: #{source[offset..]}"
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
      raise SyntaxError,
            "Expected #{value}, got #{actual.inspect}"
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
    quote = token[0]
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

      when "-"
        -numeric(expression(7))

      when "!"
        !truthy?(expression(7))

      when "+"
        numeric(expression(7))

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
          raise SyntaxError, "Unexpected #{token}"
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

    while (operator = peek) &&
          PRECEDENCE.fetch(operator, -1) >= minimum

      priority = PRECEDENCE[operator]
      take

      right = expression(priority + 1)
      left = calculate(left, operator, right)
    end

    left
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
      if a.is_a?(String) || b.is_a?(String)
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

      unless compatible
        raise TypeError, "Incompatible comparison"
      end

      a.public_send(operator, b)

    when "&&"
      truthy?(a) && truthy?(b)

    when "||"
      truthy?(a) || truthy?(b)

    else
      raise SyntaxError, "Unknown operator #{operator}"
    end
  end

  def assign(name, value, type = nil)
    unless name.match?(/\A[A-Za-z_]\w*\z/)
      raise SyntaxError, "Invalid variable name #{name}"
    end

    if type.nil? && @variables.key?(name)
      type = @variables[name][:type]
    elsif type.nil?
      raise NameError, "Unknown variable #{name}"
    end

    case type
    when "vs"
      unless value.is_a?(String)
        raise TypeError, "Expected string for #{name}"
      end

    when "vf"
      numeric(value)
      value = value.to_f

    when "vi", "vl", "vll"
      unless value.is_a?(Integer)
        raise TypeError, "Expected integer for #{name}"
      end

      maximum = {
        "vi" => MAX_INT,
        "vl" => MAX_LONG,
        "vll" => MAX_LONG_LONG
      }.fetch(type)

      if value.abs > maximum
        raise RangeError,
              "#{type} overflow (max #{maximum})"
      end

    when "vb"
      unless value == true || value == false
        raise TypeError, "Expected boolean for #{name}"
      end

    when nil
      # Untyped function parameter.

    else
      raise TypeError, "Unknown variable type #{type}"
    end

    @variables[name] = {
      type: type,
      value: value
    }

    value
  end

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

    value = read_input(prompt)

    convert_input(value, type)
  end

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
      when "("
        depth += 1

      when ")"
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

  def play_sound(frequency, volume)
    frequency = numeric(frequency)
    volume = numeric(volume)

    unless frequency.between?(20, 20_000)
      raise RangeError, "Frequency must be 20..20000"
    end

    unless volume.between?(0, 1)
      raise RangeError, "Volume must be 0..1"
    end

    if RUBY_PLATFORM.match?(/mswin|mingw/)
      system(
        "powershell",
        "-NoProfile",
        "-Command",
        "[console]::Beep(#{frequency.to_i},500)"
      )

    elsif RUBY_PLATFORM.include?("darwin")
      system("osascript", "-e", "beep")

    else
      rate = 44_100

      bytes = Array.new(rate / 2) do |index|
        sample = Math.sin(
          2 * Math::PI * frequency * index / rate
        )

        (128 + sample * 127 * volume)
          .round
          .clamp(0, 255)
      end.pack("C*")

      if system(
        "which",
        "aplay",
        out: File::NULL,
        err: File::NULL
      )
        IO.popen(
          [
            "aplay",
            "-q",
            "-t", "raw",
            "-r", rate.to_s,
            "-f", "U8"
          ],
          "w"
        ) do |io|
          io.write(bytes)
        end
      else
        warn "Sound unavailable: install alsa-utils"
      end
    end

    nil
  end

  def extract_block(lines, start_index)
    depth = 1
    middle = nil
    index = start_index + 1

    while index < lines.length
      text = lines[index][:text]

      if text.match?(/\A(?:if|while|def|namespace|class)\s+/)
        depth += 1
      end

      if text == "end"
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

    line_number = lines[start_index][:number]

    raise SyntaxError,
          "Missing end for block at line #{line_number}"
  end

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

  def define_scope(kind, name, body)
    table = kind == "namespace" ? @namespaces : @classes

    table[name] ||= {}

    index = 0

    while index < body.length
      line = body[index][:text]

      if line.empty? || line.start_with?("#", "//")
        index += 1
        next
      end

      match = /\Adef\s+([A-Za-z_]\w*)\s*\(([^()]*)\)\z/.match(line)

      unless match
        raise SyntaxError,
              "Only methods allowed directly inside #{kind} #{name}"
      end

      method_name = match[1]
      params = parameters(match[2])

      method_body, last, middle = extract_block(body, index)

      if middle
        raise SyntaxError, "Unexpected else in method definition"
      end

      table[name][method_name] = {
        params: params,
        body: method_body
      }

      index = last + 1
    end

    nil
  end

  def scoped_call(owner, separator, method, args)
    if owner == "GUI" && separator == "::"
      unless @gui_imported
        raise NameError, "Import gui first"
      end

      unless defined?(RublangGUI)
        raise LoadError, "gui.rb does not define RublangGUI"
      end

      return RublangGUI.call(method, args)
    end

    if owner == "time" && separator == "."
      unless @time_imported
        raise NameError, "Import time first"
      end

      case method
      when "sleep"
        unless args.length == 1
          raise ArgumentError, "time.sleep expects 1 argument"
        end

        seconds = numeric(args[0])

        raise RangeError, "Negative sleep" if seconds < 0

        sleep(seconds)
        return nil
      end
    end

    table = separator == "." ? @namespaces : @classes

    scope = table[owner]

    unless scope
      kind = separator == "." ? "namespace" : "class"

      raise NameError, "Unknown #{kind} #{owner}"
    end

    function = scope[method]

    unless function
      raise NameError,
            "Unknown method #{owner}#{separator}#{method}"
    end

    invoke_function(
      function,
      args,
      "#{owner}#{separator}#{method}"
    )
  end

  def call_function(name, args)
    case name
    when "print"
      puts(*args)
      return nil

    when "str"
      raise ArgumentError, "str expects 1 argument" unless args.length == 1
      return args[0].to_s

    when "int"
      raise ArgumentError, "int expects 1 argument" unless args.length == 1
      return Integer(args[0])

    when "float"
      raise ArgumentError, "float expects 1 argument" unless args.length == 1
      return Float(args[0])

    when "len"
      raise ArgumentError, "len expects 1 argument" unless args.length == 1
      return args[0].to_s.length

    when "abs"
      raise ArgumentError, "abs expects 1 argument" unless args.length == 1
      return numeric(args[0]).abs

    when "min"
      raise ArgumentError, "min expects 2 arguments" unless args.length == 2
      return [numeric(args[0]), numeric(args[1])].min

    when "max"
      raise ArgumentError, "max expects 2 arguments" unless args.length == 2
      return [numeric(args[0]), numeric(args[1])].max

    when "round"
      raise ArgumentError, "round expects 1 argument" unless args.length == 1
      return numeric(args[0]).round
    end

    function = @functions[name]

    unless function
      raise NameError, "Unknown function #{name}"
    end

    invoke_function(function, args, name)
  end

  def invoke_function(function, args, name)
    expected = function[:params].length

    unless args.length == expected
      raise ArgumentError,
            "#{name} expects #{expected} arguments, got #{args.length}"
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

  def package_directories
    directories = []

    if @source_file
      directories << File.dirname(@source_file)
    end

    directories << Dir.pwd

    directories.uniq
  end

  def import_package(name)
    return if @imports[name]

    case name
    when "time"
      @time_imported = true
      @imports[name] = true
      return

    when "gui"
      unless defined?(RublangGUI)
        raise LoadError, "GUI engine unavailable"
      end

      @gui_imported = true
      @imports[name] = true
      return
    end

    unless name.match?(/\A[A-Za-z][A-Za-z0-9_-]*\z/)
      raise SyntaxError, "Invalid package name #{name}"
    end

    paths = []

    package_directories.each do |directory|
      paths << File.join(
        directory, ".rublang", "packages", "#{name}.lang"
      )

      paths << File.join(
        directory, ".rublang", "packages", name, "main.lang"
      )

      paths << File.join(directory, "#{name}.lang")
    end

    path = paths.find { |candidate| File.file?(candidate) }

    unless path
      raise LoadError,
            "Package not installed: #{name}. Run ruby pkg.rb install ."
    end

    @imports[name] = true

    begin
      code = File.read(path)
      run(code)

    rescue Exception
      @imports.delete(name)
      raise
    end

    nil
  end

  def report_error(error, number)
    @error_count += 1

    case error
    when ZeroDivisionError
      warn "RublangError [line #{number}]: #{error.message}"

    when RangeError
      warn "RublangOverflow [line #{number}]: #{error.message}"

    when SyntaxError
      warn "RublangSyntaxError [line #{number}]: #{error.message}"

    else
      warn "RublangError [line #{number}]: #{error.message}"
    end
  end

  def execute(lines, in_function = false)
    index = 0

    while index < lines.length
      line = lines[index][:text]
      number = lines[index][:number]

      index += 1

      next if line.empty?
      next if line.start_with?("#", "//")

      @current_line = number

      begin
        case line

        when /\Aimport\s+([A-Za-z][A-Za-z0-9_-]*)\z/
          import_package(Regexp.last_match(1))

        when /\A(?:if|while|def|namespace|class)\s+/
          block_start = index - 1
          body, last, middle = extract_block(lines, block_start)

          if line.start_with?("namespace ", "class ")
            kind, name = line.split(/\s+/, 2)

            unless name.match?(/\A[A-Za-z_]\w*\z/)
              raise SyntaxError, "Invalid scope name #{name}"
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
            match = /\Adef\s+([A-Za-z_]\w*)\s*\(([^()]*)\)\z/.match(line)

            unless match
              raise SyntaxError, "Expected def name(args)"
            end

            if middle
              raise SyntaxError, "Unexpected else"
            end

            @functions[match[1]] = {
              params: parameters(match[2]),
              body: body
            }
          end

          index = last + 1

        when "end", "else"
          raise SyntaxError, "Unexpected #{line}"

        when /\Areturn(?:\s+(.+))?\z/
          unless in_function
            raise SyntaxError, "Return outside function"
          end

          source = Regexp.last_match(1)
          value = source ? evaluate(source) : nil

          raise ReturnSignal.new(value)

        when /\Astdin::c\s*>>\s*([A-Za-z_]\w*)\z/
          name = Regexp.last_match(1)

          type = @variables.dig(name, :type) || "vs"

          value = convert_input(
            read_input("> "),
            type
          )

          assign(name, value, type)

        when /\Astdout::c\s*<<\s*(.+)\z/
          puts evaluate(Regexp.last_match(1))

        when /\Astdout::print\s*<<\s*(.+)\z/
          print evaluate(Regexp.last_match(1))
          STDOUT.flush

        when /\Asound::play\s*\((.*)\)\z/
          pieces = split_args(Regexp.last_match(1))

          unless pieces.length == 2
            raise ArgumentError,
                  "sound::play(freq, volume)"
          end

          frequency = evaluate(pieces[0])
          volume = evaluate(pieces[1])

          play_sound(frequency, volume)

        when /\A(vll|vs|vf|vi|vb|vl)\s+([A-Za-z_]\w*)\s*=\s*(.+)\z/
          type, name, source = Regexp.last_match.captures

          value = assignment_value(source, type)
          assign(name, value, type)

        when /\A([A-Za-z_]\w*)\s*=\s*(.+)\z/
          name, source = Regexp.last_match.captures

          unless @variables.key?(name)
            raise NameError, "Unknown variable #{name}"
          end

          type = @variables[name][:type]
          value = assignment_value(source, type)

          assign(name, value)

        when /\A[A-Za-z_]\w*(?:(?:\.|::)[A-Za-z_]\w*)?\s*\(.*\)\z/
          evaluate(line)

        else
          raise SyntaxError,
                "Unknown command: #{line}"
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

  def run(code)
    lines = code.each_line.with_index(1).map do |line, number|
      {
        text: line.strip,
        number: number
      }
    end

    execute(lines)
  end

  def run_file(path)
    unless File.file?(path)
      raise LoadError, "File not found: #{path}"
    end

    @source_file = File.expand_path(path)

    run(File.read(@source_file))
  end

  def errors
    @error_count
  end
end

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
