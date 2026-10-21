
require "socket"
require "cgi"

module RublangGUI
  COMPONENTS = %w[
    label text heading paragraph span strong italic small code pre
    quote link button input password email number search textarea
    checkbox radio switch slider progress meter select option form
    fieldset legend file date time color range image icon video
    audio canvas table thead tbody tr th td ul ol li nav header
    footer main section article aside div card panel group row
    column grid stack tabs tab accordion details summary dialog
    badge alert toast tooltip separator spacer container toolbar
    menu menu_item dropdown breadcrumb pagination avatar chip tag
    spinner skeleton calendar datetime week month telephone url
    hidden reset submit output datalist optgroup
  ].freeze

  # Exactly 100 available component names.
  raise "Expected 100 components" unless COMPONENTS.length == 100

  INPUT_TYPES = {
    "input" => "text",
    "password" => "password",
    "email" => "email",
    "number" => "number",
    "search" => "search",
    "checkbox" => "checkbox",
    "radio" => "radio",
    "switch" => "checkbox",
    "slider" => "range",
    "file" => "file",
    "date" => "date",
    "time" => "time",
    "color" => "color",
    "range" => "range",
    "week" => "week",
    "month" => "month",
    "telephone" => "tel",
    "url" => "url",
    "hidden" => "hidden",
    "reset" => "reset",
    "submit" => "submit",
    "datetime" => "datetime-local"
  }.freeze

  ALIASES = {
    "text" => "span",
    "heading" => "h2",
    "quote" => "blockquote",
    "image" => "img",
    "icon" => "span",
    "card" => "div",
    "panel" => "div",
    "group" => "div",
    "row" => "div",
    "column" => "div",
    "grid" => "div",
    "stack" => "div",
    "tabs" => "div",
    "tab" => "button",
    "accordion" => "details",
    "badge" => "span",
    "alert" => "div",
    "toast" => "div",
    "tooltip" => "span",
    "separator" => "hr",
    "spacer" => "div",
    "container" => "div",
    "toolbar" => "div",
    "menu" => "nav",
    "menu_item" => "button",
    "dropdown" => "select",
    "breadcrumb" => "nav",
    "pagination" => "nav",
    "avatar" => "div",
    "chip" => "span",
    "tag" => "span",
    "spinner" => "span",
    "skeleton" => "div",
    "calendar" => "input"
  }.freeze

  VOID_TAGS = %w[input img hr br].freeze

  class << self
    def reset
      @title = "Rublang GUI"
      @width = 900
      @height = 650
      @elements = []
      @stack = []
      @theme = "dark"
    end

    def escape(value)
      CGI.escapeHTML(value.to_s)
    end

    def safe_url(value)
      url = value.to_s
      return url if url.match?(/\Ahttps?:\/\//i)
      return url if url.start_with?("#")
      "#"
    end

    def call(method, args)
      reset unless @elements

      case method
      when "window"
        @title = args.fetch(0, "Rublang GUI").to_s
        @width = Integer(args.fetch(1, 900)).clamp(300, 3000)
        @height = Integer(args.fetch(2, 650)).clamp(200, 3000)
        nil
      when "theme"
        theme = args.fetch(0, "dark").to_s
        raise ArgumentError, "Use dark or light" unless %w[dark light].include?(theme)
        @theme = theme
        nil
      when "clear"
        @elements.clear
        @stack.clear
        nil
      when "start"
        name = args.fetch(0).to_s
        html = component(name, args.drop(1), true)
        @elements << html
        @stack << name
        nil
      when "finish"
        name = @stack.pop
        raise ArgumentError, "No open component" unless name
        tag = tag_for(name)
        @elements << "</#{tag}>"
        nil
      when "newline"
        @elements << "<br>"
        nil
      when "show"
        show
      when "count"
        COMPONENTS.length
      else
        unless COMPONENTS.include?(method)
          raise NameError, "Unknown GUI component #{method}"
        end
        @elements << component(method, args)
        nil
      end
    end

    def tag_for(name)
      raise ArgumentError, "Unknown component #{name}" unless COMPONENTS.include?(name)
      return "input" if INPUT_TYPES.key?(name)
      ALIASES.fetch(name, name)
    end

    def component(name, args, open_only = false)
      tag = tag_for(name)
      value = args.fetch(0, "")
      second = args[1]
      css = escape(name.tr("_", "-"))

      if INPUT_TYPES.key?(name)
        type = INPUT_TYPES[name]
        type = "date" if name == "calendar"
        attr = "type='#{type}' class='#{css}'"

        case type
        when "checkbox", "radio"
          attr += " checked" if value == true
        when "range"
          number = Float(value) rescue 50.0
          attr += " min='0' max='100' value='#{number.clamp(0, 100)}'"
        when "file"
          # Native file picker.
        else
          if %w[text password email search tel url].include?(type)
            attr += " placeholder='#{escape(value)}'"
          else
            attr += " value='#{escape(value)}'"
          end
        end

        return "<input #{attr}>"
      end

      if name == "image"
        return "<img class='image' src='#{safe_url(value)}' alt='Image'>"
      end

      if name == "link"
        return "<a href='#{safe_url(second)}' target='_blank' rel='noopener noreferrer'>#{escape(value)}</a>"
      end

      if name == "progress" || name == "meter"
        number = Float(value).clamp(0, 100)
        return "<#{tag} value='#{number}' max='100'></#{tag}>"
      end

      if name == "separator"
        return "<hr>"
      end

      if name == "spacer"
        return "<div style='height:#{Integer(value).clamp(0, 500)}px'></div>"
      end

      if open_only
        return "<#{tag} class='#{css}'>"
      end

      "<#{tag} class='#{css}'>#{escape(value)}</#{tag}>"
    end

    def page
      until @stack.empty?
        name = @stack.pop
        @elements << "</#{tag_for(name)}>"
      end

      colors = if @theme == "light"
        ["#f2f4f8", "#ffffff", "#172033", "#3563e9", "#cdd4e1"]
      else
        ["#10131b", "#1b2130", "#edf1f9", "#7c83ff", "#394153"]
      end

      bg, surface, fg, accent, border = colors

      <<~HTML
      <!doctype html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>#{escape(@title)}</title>
        <style>
          * { box-sizing: border-box; }
          body {
            background: #{bg};
            color: #{fg};
            font-family: system-ui, sans-serif;
            margin: 0;
            padding: 28px;
            min-width: 280px;
          }
          #app {
            max-width: #{@width}px;
            min-height: #{@height - 80}px;
            margin: auto;
            padding: 28px;
            border: 1px solid #{border};
            border-radius: 18px;
            background: #{surface};
          }
          h1, h2, h3 { margin-top: 0; }
          button, input, select, textarea {
            padding: 10px 14px;
            margin: 5px;
            font: inherit;
            border-radius: 8px;
            border: 1px solid #{border};
          }
          button, input[type=submit], input[type=reset] {
            background: #{accent};
            color: white;
            cursor: pointer;
          }
          button:hover { filter: brightness(1.15); }
          input:not([type=checkbox]):not([type=radio]),
          select, textarea {
            background: #{bg};
            color: #{fg};
          }
          input[type=checkbox], input[type=radio] {
            accent-color: #{accent};
            width: 18px;
            height: 18px;
          }
          input[type=range] { accent-color: #{accent}; }
          progress, meter { width: 100%; height: 22px; }
          .card, .panel, .alert, .toast {
            display: block;
            padding: 16px;
            margin: 10px 0;
            border: 1px solid #{border};
            border-radius: 12px;
          }
          .row, .toolbar, .group {
            display: flex;
            align-items: center;
            gap: 10px;
            flex-wrap: wrap;
          }
          .column, .stack {
            display: flex;
            flex-direction: column;
            gap: 10px;
          }
          .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
            gap: 12px;
          }
          .badge, .chip, .tag {
            display: inline-block;
            border-radius: 20px;
            padding: 4px 12px;
            background: #{accent};
            color: white;
          }
          .spinner {
            display: inline-block;
            height: 25px;
            width: 25px;
            border-radius: 50%;
            border: 3px solid #{border};
            border-top-color: #{accent};
            animation: spin 1s linear infinite;
          }
          @keyframes spin { to { transform: rotate(360deg); } }
          .skeleton {
            height: 30px;
            border-radius: 8px;
            background: #{border};
          }
          img { max-width: 100%; }
          table { border-collapse: collapse; width: 100%; }
          td, th { border: 1px solid #{border}; padding: 8px; }
          a { color: #{accent}; }
          textarea { min-height: 90px; }
        </style>
      </head>
      <body>
        <main id="app">
          <h1>#{escape(@title)}</h1>
          #{@elements.join("\n")}
        </main>
      </body>
      </html>
      HTML
    end

    def show
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]
      html = page
      url = "http://127.0.0.1:#{port}/"

      puts "Rublang GUI: #{url}"
      puts "Press Ctrl+C to stop the GUI server."

      unless system("xdg-open", url,
                    out: File::NULL, err: File::NULL)
        warn "Open #{url} in your browser."
      end

      loop do
        client = server.accept
        begin
          request = client.gets
          next unless request

          while (line = client.gets)
            break if line == "\r\n" || line == "\n"
          end

          body = request.start_with?("GET / ") ? html : "Not found"
          status = body == html ? "200 OK" : "404 Not Found"
          mime = body == html ? "text/html" : "text/plain"

          client.write(
            "HTTP/1.1 #{status}\r\n" \
            "Content-Type: #{mime}; charset=utf-8\r\n" \
            "Content-Length: #{body.bytesize}\r\n" \
            "Connection: close\r\n\r\n"
          )
          client.write(body)
        rescue IOError, Errno::EPIPE
        ensure
          client.close
        end
      end
    rescue Interrupt
      puts "\nGUI closed."
      nil
    ensure
      server&.close
    end
  end
end
