require "markterm"
require "colorize"
require "yaml"
require "docopt"
require "sixteen"
require "crimage"
require "termisu"

module Jrsl
  VERSION = "0.3.0"

  # Slide classes (reuse existing)
  class MarkdownElement
    property markdown_text : String
    property rendered : String
    property rows : Int32
    property cols : Int32

    def initialize(@markdown_text : String, @rendered : String, @rows : Int32, @cols : Int32)
    end
  end

  class Slide
    property title : String
    property content : String
    property image_path : String?
    property image_position : String = "center"
    property image_h_position : String = "left"
    property image_max_height : Int32?
    property rendered_image : Tuple(String, Int32, Int32)?
    property kitty_image : Tuple(String, Int32, Int32)?
    property markdown_element : MarkdownElement?

    def initialize(@title : String, @content : String = "")
      @image_path = nil
      @image_max_height = nil
      @rendered_image = nil
      @kitty_image = nil
      @markdown_element = nil
    end
  end

  class SlideMetadata
    include YAML::Serializable

    property title : String
    property image : String?
    property image_position : String = "center"
    property image_h_position : String = "left"
    property image_height : Int32?
  end

  class PresentationMetadata
    include YAML::Serializable

    property title : String?
    property author : String?
    property event : String?
    property location : String?

    def initialize
      @title = ""
      @author = ""
      @event = ""
      @location = ""
    end
  end

  # Reuse existing parsing functions
  # ameba:disable Metrics/CyclomaticComplexity
  def self.parse_slides(content : String) : Tuple(Array(Slide), PresentationMetadata)
    slides = [] of Slide
    metadata = PresentationMetadata.new
    lines = content.lines

    i = 0
    if i < lines.size && lines[i] == "---"
      i += 1
      metadata_lines = [] of String
      while i < lines.size && lines[i] != "---"
        metadata_lines << lines[i]
        i += 1
      end
      i += 1 if i < lines.size

      unless metadata_lines.empty?
        begin
          metadata = PresentationMetadata.from_yaml(metadata_lines.join("\n"))
        rescue
        end
      end
    end

    while i < lines.size
      while i < lines.size && lines[i].blank?
        i += 1
      end
      break if i >= lines.size

      yaml_lines = [] of String
      while i < lines.size && lines[i] != "---" && !lines[i].blank?
        yaml_lines << lines[i]
        i += 1
      end

      if yaml_lines.empty?
        i += 1
        next
      end

      slide_metadata = SlideMetadata.from_yaml(yaml_lines.join("\n"))
      title = slide_metadata.title

      i += 1 if i < lines.size && lines[i] == "---"

      content_lines = [] of String
      while i < lines.size && lines[i] != "---"
        content_lines << lines[i]
        i += 1
      end

      content = content_lines.join("\n")
      content += "\n" unless content.lines.empty?

      slide = Slide.new(title, content)
      slide.image_path = slide_metadata.image
      slide.image_position = slide_metadata.image_position
      slide.image_h_position = slide_metadata.image_h_position
      slide.image_max_height = slide_metadata.image_height
      slides << slide
    end

    {slides, metadata}
  end

  def self.render_markdown_to_element(markdown : String, max_width : Int32) : MarkdownElement
    rendered = Markd.to_term(markdown, max_width: max_width)
    lines = rendered.split("\n")

    rows = lines.size
    cols = lines.max_of?(&.size) || 0

    MarkdownElement.new(markdown, rendered, rows, cols)
  end

  # Termisu-specific rendering helpers
  def self.set_string(termisu : Termisu, x : Int32, y : Int32, text : String,
                      fg : Termisu::Color = Termisu::Color.white,
                      bg : Termisu::Color = Termisu::Color.default,
                      attr : Termisu::Attribute = Termisu::Attribute::None) : Nil
    text.each_char_with_index do |char, idx|
      termisu.set_cell(x + idx, y, char, fg: fg, bg: bg, attr: attr)
    end
  end

  # Convert Sixteen color to Termisu color
  def self.to_termisu_color(color : Sixteen::Color) : Termisu::Color
    r = (color.r >> 8).to_i
    g = (color.g >> 8).to_i
    b = (color.b >> 8).to_i
    Termisu::Color.rgb(r, g, b)
  end

  # Simple figlet rendering
  def self.print_figlet(termisu : Termisu, text : String, x : Int32, y : Int32,
                        theme : Sixteen::Theme?) : Int32
    # Normalize text for figlet (reuse existing normalization)
    normalized = text.gsub(/[áéíóúàèìòùäëïöüâêîôûãñõÁÉÍÓÚÀÈÌÒÙÄËÏÖÜÂÊÎÔÛÃÑÕçÇß]/,
                              { 'á' => "a", 'é' => "e", 'í' => "i", 'ó' => "o", 'ú' => "u",
                                'à' => "a", 'è' => "e", 'ì' => "i", 'ò' => "o", 'ù' => "u",
                                'ä' => "a", 'ë' => "e", 'ï' => "i", 'ö' => "o", 'ü' => "u",
                                'â' => "a", 'ê' => "e", 'î' => "i", 'ô' => "o", 'û' => "u",
                                'ã' => "a", 'ñ' => "n", 'õ' => "o",
                                'Á' => "A", 'É' => "E", 'Í' => "I", 'Ó' => "O", 'Ú' => "U",
                                'À' => "A", 'È' => "E", 'Ì' => "I", 'Ò' => "O", 'Ù' => "U",
                                'Ä' => "A", 'Ë' => "E", 'Ï' => "I", 'Ö' => "O", 'Ü' => "U",
                                'Â' => "A", 'Ê' => "E", 'Î' => "I", 'Ô' => "O", 'Û' => "U",
                                'Ã' => "A", 'Ñ' => "N", 'Õ' => "O",
                                'ç' => "c", 'Ç' => "C",
                                'ß' => "ss" })

    output = `figlet -f smbraille.tlf #{normalized}`

    if theme
      bg_color = to_termisu_color(theme["01"])
      fg_color = to_termisu_color(theme["05"])
    else
      bg_color = Termisu::Color.white
      fg_color = Termisu::Color.black
    end

    lines = output.split("\n").map(&.rstrip).reject(&.empty?)
    max_length = lines.max_of(&.size)

    lines.each_with_index do |line, idx|
      # Right-pad and center
      padded = line.ljust(max_length).rjust(termisu.size[0])
      padded.each_char_with_index do |char, cidx|
        termisu.set_cell(cidx, y + idx, char, fg: fg_color, bg: bg_color,
                        attr: Termisu::Attribute::Bold)
      end
    end

    lines.size
  end
end

# Main application using Termisu
def main
  doc = <<-DOC
  JRSL - Terminal-based presentation program

  Usage:
    jrsl-termisu [-t <theme>] [--kitty] [<file>]
    jrsl-termisu -h | --help
    jrsl-termisu --version

  Options:
    -h --help       Show this help message
    --version       Show version
    -t <theme>      Color theme to use
    --kitty         Use Kitty graphics protocol for images

  Arguments:
    <file>          Presentation file to open [default: charla/charla.md]
  DOC

  args = Docopt.docopt(doc)

  if args["--version"]
    puts "JRSL version #{Jrsl::VERSION} (Termisu)"
    exit 0
  end

  slides_file = if args["<file>"].is_a?(String)
                  args["<file>"].as(String)
                else
                  "charla/charla.md"
                end

  theme_name = if args["-t"].is_a?(String)
                 args["-t"].as(String).downcase
               else
                 nil
               end

  theme = nil
  if theme_name
    begin
      theme = Sixteen.theme_with_fallback(theme_name)
    rescue e : Exception
      STDERR.puts "Warning: Theme '#{theme_name}' not found, using default colors"
    end
  end

  slides, metadata = if File.exists?(slides_file)
                       Jrsl.parse_slides(File.read(slides_file))
                     else
                       STDERR.puts "Error: File not found: #{slides_file}"
                       exit 1
                     end

  use_kitty = args["--kitty"] == true

  # Pre-render markdown
  terminal_size = Term::Screen.size || {24, 80}
  _, terminal_width = terminal_size
  md_width = terminal_width // 2 - 2
  slides.each do |slide|
    unless slide.content.empty?
      slide.markdown_element = Jrsl.render_markdown_to_element(slide.content, md_width)
    end
  end

  # Initialize Termisu
  termisu = Termisu.new
  termisu.hide_cursor

  current_slide = 0
  y_offset = 0

  begin
    loop do
      # Event handling with timeout
      if event = termisu.poll_event(50)
        case event
        when Termisu::Event::Key
          key = event.key

          # Handle navigation
          case key
          when .escape?
            break
          when .left?
            if current_slide > 0
              current_slide -= 1
              y_offset = 0
            end
          when .right?
            if current_slide < slides.size - 1
              current_slide += 1
              y_offset = 0
            end
          when .up?
            if y_offset > 0
              y_offset -= 1
            end
          when .down?
            y_offset += 1
          end
        when Termisu::Event::Resize
          termisu.sync
        end
      end

      # Clear and render current slide
      termisu.clear
      slide = slides[current_slide]?

      if slide
        current_y = 0

        # Print title if present
        unless slide.title.empty?
          current_y += Jrsl.print_figlet(termisu, slide.title, 0, current_y, theme)
          current_y += 1
        end

        # TODO: Render markdown, images, footer
        # For now, just show a message
        Jrsl.set_string(termisu, 0, current_y, "Slide #{current_slide + 1}/#{slides.size}",
                        fg: Termisu::Color.white)

        if md_element = slide.markdown_element
          current_y += 2
          lines = md_element.rendered.split("\n")
          lines.each_with_index do |line, idx|
            Jrsl.set_string(termisu, 0, current_y + idx, line, fg: Termisu::Color.white)
          end
        end

        # Footer
        width = termisu.size[0]
        footer_parts = [] of String
        if event_val = metadata.event
          footer_parts << event_val
        end
        if location_val = metadata.location
          footer_parts << location_val
        end
        if author_val = metadata.author
          footer_parts << author_val
        end
        footer_text = footer_parts.join(" / ")
        footer_text += " / " unless footer_text.empty?
        footer_text += "#{current_slide + 1}/#{slides.size}"
        footer_text = footer_text.center(width)

        if theme
          fg_color = Jrsl.to_termisu_color(theme["05"])
          bg_color = Jrsl.to_termisu_color(theme["01"])
        else
          fg_color = Termisu::Color.black
          bg_color = Termisu::Color.green
        end

        Jrsl.set_string(termisu, 0, termisu.size[1] - 1, footer_text,
                        fg: fg_color, bg: bg_color)
      end

      # Apply all changes
      termisu.render
    end
  ensure
    termisu.show_cursor
    termisu.close
  end
end

main
