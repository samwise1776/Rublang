
# gui.rb
# Rublang native desktop GUI using Glimmer DSL for LibUI

require "glimmer-dsl-libui"

module RublangGUI
  extend self
  include Glimmer

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

  raise "Expected 100 components" unless COMPONENTS.size == 100

  VERTICAL = %w[
    div card panel group column stack container section article
    main aside header footer nav form fieldset grid tabs accordion
    details dialog ul ol table tbody thead tr datalist optgroup
  ].freeze

  HORIZONTAL = %w[
    row toolbar menu breadcrumb pagination
  ].freeze

  TEXTUAL = %w[
    label text heading paragraph span strong italic small code
    pre quote link legend option th td li summary badge alert
    toast tooltip menu_item avatar chip tag output icon
  ].freeze

  INPUTS = %w[
    input password email number search textarea checkbox radio
    switch slider range select dropdown file date time datetime
    week month telephone url color calendar hidden reset submit
  ].freeze

  def reset
    @title = "Rublang GUI"
    @width = 900
    @height = 650
    @theme = "dark"
    @elements = []
    @stack = []
    @events = {}
    @values = {}
    @window = nil
    nil
  end

  reset

  def call(method, args = [])
    method = method.to_s
    args = Array(args)

    case method
    when "window"
      @title = args.fetch(0, "Rublang GUI").to_s
      @width = Integer(args.fetch(1, 900)).clamp(300, 3000)
      @height = Integer(args.fetch(2, 650)).clamp(200, 3000)

    when "theme"
      value = args.fetch(0, "dark").to_s
      unless %w[dark light].include?(value)
        raise ArgumentError, "Theme must be dark or light"
      end
      @theme = value

    when "clear"
      @elements.clear
      @stack.clear
      @values.clear

    when "start"
      name = args.fetch(0).to_s
      validate_component(name)

      node = make_node(name, args.drop(1))
      append_node(node)
      @stack << node

    when "finish"
      raise ArgumentError, "No open component" if @stack.empty?
      @stack.pop

    when "newline"
      append_node(make_node("spacer", [8]))

    when "show"
      show

    when "count"
      COMPONENTS.size

    when "get"
      @values[args.fetch(0).to_s]

    when "set"
      @values[args.fetch(0).to_s] = args[1]

    else
      validate_component(method)
      append_node(make_node(method, args))
    end

    nil
  end

  def validate_component(name)
    return if COMPONENTS.include?(name)

    raise NameError, "Unknown GUI component #{name}"
  end

  def make_node(name, args)
    {
      name: name,
      args: args,
      children: []
    }
  end

  def append_node(node)
    if @stack.empty?
      @elements << node
    else
      @stack.last[:children] << node
    end
    node
  end

  def on(name, &block)
    @events[name.to_s] = block
  end

  def fire(name, value = nil)
    event = @events[name.to_s]
    event.call(value) if event
  end

  def show
    # Build the Glimmer interface before starting
    # its native event loop.
    app = self

    @window = window(@title, @width, @height) {
      margined true

      vertical_box {
        app.render_all
      }
    }

    @window.show
    nil
  end

  def render_all
    if @elements.empty?
      label("Empty Rublang window")
    else
      @elements.each do |node|
        render(node)
      end
    end
  end

  def render(node)
    name = node[:name]
    args = node[:args]
    children = node[:children]

    value = args.fetch(0, "")
    text = value.to_s

    if HORIZONTAL.include?(name)
      horizontal_box {
        children.each { |child| render(child) }
      }
      return
    end

    if VERTICAL.include?(name)
      if %w[group card panel fieldset].include?(name)
        title = text.empty? ? name.capitalize : text

        group(title) {
          margined true
          vertical_box {
            children.each { |child| render(child) }
          }
        }
      else
        vertical_box {
          children.each { |child| render(child) }
        }
      end
      return
    end

    case name
    when "heading"
      label(text.upcase)

    when *TEXTUAL
      label(text)

    when "button", "submit", "reset", "menu_item"
      caption = text.empty? ? name.capitalize : text

      button(caption) {
        on_clicked do
          fire(caption)
        end
      }

    when "input", "email", "telephone", "url"
      key = args.fetch(1, name).to_s

      entry {
        text value.to_s
        on_changed do |control|
          @values[key] = control.text
        end
      }

    when "search"
      key = args.fetch(1, "search").to_s

      search_entry {
        text value.to_s
        on_changed do |control|
          @values[key] = control.text
        end
      }

    when "password"
      key = args.fetch(1, "password").to_s

      password_entry {
        on_changed do |control|
          @values[key] = control.text
        end
      }

    when "number"
      key = args.fetch(1, "number").to_s

      spinbox(0, 1_000_000) {
        value value.to_i

        on_changed do |control|
          @values[key] = control.value
        end
      }

    when "textarea"
      key = args.fetch(1, "textarea").to_s

      multiline_entry {
        text value.to_s

        on_changed do |control|
          @values[key] = control.text
        end
      }

    when "checkbox", "switch"
      caption = value == true || value == false ?
        name.capitalize : text

      checkbox(caption) {
        checked(value == true)

        on_toggled do |control|
          @values[caption] = control.checked
          fire(caption, control.checked)
        end
      }

    when "radio"
      radio_buttons {
        items(text.split("|").map(&:strip))
      }

    when "slider", "range"
      key = args.fetch(1, name).to_s

      slider(0, 100) {
        value value.to_i.clamp(0, 100)

        on_changed do |control|
          @values[key] = control.value
          fire(key, control.value)
        end
      }

    when "progress", "meter"
      progress_bar {
        value value.to_i.clamp(0, 100)
      }

    when "select", "dropdown"
      key = args.fetch(1, name).to_s
      options = text.split("|").map(&:strip)

      combobox {
        items(options)

        on_selected do |control|
          @values[key] = options[control.selected]
          fire(key, @values[key])
        end
      }

    when "date", "calendar"
      date_picker

    when "time"
      time_picker

    when "datetime"
      date_time_picker

    when "color"
      color_button

    when "separator"
      horizontal_separator

    when "spacer"
      label(" ")

    when "file"
      button(text.empty? ? "Choose file" : text) {
        on_clicked do
          selected = open_file
          @values["file"] = selected if selected
          fire("file", selected)
        end
      }

    when "spinner"
      progress_bar {
        value(-1)
      }

    when "image"
      label("Image: #{text}")

    when "canvas"
      label("Canvas")

    when "video", "audio"
      label("#{name.capitalize}: #{text}")

    when "hidden"
      @values["hidden"] = value

    when "week", "month"
      entry {
        text value.to_s
      }

    when "skeleton"
      progress_bar {
        value(-1)
      }

    else
      label(text.empty? ? name.capitalize : text)
    end
  end

  def component_names
    COMPONENTS.dup
  end

  def count
    COMPONENTS.size
  end
end

# Standalone demonstration:
if __FILE__ == $PROGRAM_NAME
  gui = RublangGUI

  gui.call("window", ["Rublang Native GUI", 750, 550])
  gui.call("theme", ["dark"])

  gui.call("heading", ["Welcome to Rublang"])
  gui.call("label", ["Native GUI powered by Glimmer"])

  gui.call("start", ["group", "User Information"])

  gui.call("label", ["Username"])
  gui.call("input", ["Enter username", "username"])

  gui.call("label", ["Password"])
  gui.call("password", ["", "password"])

  gui.call("checkbox", ["Enable settings"])
  gui.call("slider", [50, "volume"])

  gui.call("finish")

  gui.call("start", ["row"])
  gui.call("button", ["Hello"])
  gui.call("button", ["About"])
  gui.call("finish")

  gui.on("Hello") do
    puts "Hello from Rublang!"
  end

  gui.on("About") do
    puts "Rublang GUI uses Glimmer DSL for LibUI"
  end

  gui.call("progress", [65])
  gui.call("show", [])
end
