require "markterm"
require "tput"
require "colorize"
require "yaml"
require "docopt"

module Jrsl
  VERSION = "0.1.0"

  # Normalize accented characters to ASCII for figlet
  def self.normalize_for_figlet(text : String) : String
    mapping = {
      'á' => "a", 'é' => "e", 'í' => "i", 'ó' => "o", 'ú' => "u",
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
      'ß' => "ss",
    }

    result = text.dup
    mapping.each do |accented, replacement|
      result = result.gsub(accented, replacement)
    end
    result
  end

  class Slide
    property title : String
    property content : String

    def initialize(@title : String, @content : String = "")
    end
  end

  class SlideMetadata
    include YAML::Serializable

    property title : String
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

  def self.parse_slides(content : String) : Tuple(Array(Slide), PresentationMetadata)
    slides = [] of Slide
    metadata = PresentationMetadata.new
    lines = content.lines

    i = 0
    # Parse global metadata from first YAML block
    if i < lines.size && lines[i] == "---"
      i += 1
      metadata_lines = [] of String
      while i < lines.size && lines[i] != "---"
        metadata_lines << lines[i]
        i += 1
      end
      i += 1 if i < lines.size # Skip this "---" which is also the start of first slide

      unless metadata_lines.empty?
        begin
          metadata = PresentationMetadata.from_yaml(metadata_lines.join("\n"))
        rescue
          # If parsing fails, use default empty metadata
        end
      end
    end

    # Parse alternating blocks: metadata (YAML) + content (markdown)
    while i < lines.size
      # Skip any blank lines before metadata
      while i < lines.size && lines[i].blank?
        i += 1
      end
      break if i >= lines.size

      # Slide metadata is directly after "---", no additional "---" wrapper
      # Parse slide metadata (YAML) until next "---"
      yaml_lines = [] of String
      while i < lines.size && lines[i] != "---" && !lines[i].blank?
        yaml_lines << lines[i]
        i += 1
      end

      # If we didn't find any metadata, skip ahead
      if yaml_lines.empty?
        i += 1
        next
      end

      # Parse YAML to extract title
      slide_metadata = SlideMetadata.from_yaml(yaml_lines.join("\n"))
      title = slide_metadata.title

      # Skip the "---" delimiter between metadata and content
      i += 1 if i < lines.size && lines[i] == "---"

      # Parse slide content (markdown) until next "---" or end of file
      content_lines = [] of String
      while i < lines.size && lines[i] != "---"
        content_lines << lines[i]
        i += 1
      end

      # Create slide with title and content, preserving trailing newline if present
      content = content_lines.join("\n")
      content += "\n" unless content.lines.empty?
      slides << Slide.new(title, content)
    end

    {slides, metadata}
  end
end

def print_md(tput, markdown, x, y, h, y_offset = 0)
  rendered = Markd.to_term(markdown)
  lines = rendered.split("\n")[y_offset..-1]
  max_y = y + h

  if lines && lines.size < h
    y += h//2 - lines.size//2
  end

  lines ||= [] of String
  lines.each do |line|
    tput.cursor_pos y, x
    tput.echo line
    y += 1
    break if y > max_y
  end
end

def print_figlet(tput, text, x, y)
  normalized_text = Jrsl.normalize_for_figlet(text)
  output = `figlet -f smbraille.tlf #{normalized_text}`
  lines = output.split("\n").map { |line| line.rstrip }.reject &.empty?

  # Find the maximum line length
  max_length = lines.max_of &.size

  # Right-pad all lines to the same length, then rjust to screen width
  lines.each do |line|
    line = line.ljust(max_length).rjust(tput.screen.width)
    tput.cursor_pos y, x
    tput.echo(line.colorize(:black).on_white.mode(:bold))
    y += 1
  end
end

def build_footer(metadata : Jrsl::PresentationMetadata, slide_num : Int32, total_slides : Int32, width : Int32)
  parts = [] of String

  if event = metadata.event
    parts << event
  end

  if location = metadata.location
    parts << location
  end

  if author = metadata.author
    parts << author
  end

  footer_text = parts.join(" 💗 ")
  footer_text += " 💗 " unless footer_text.empty? || slide_num < 0
  footer_text += "#{slide_num + 1}/#{total_slides}" if slide_num >= 0

  footer_text = footer_text.center(width - 2)
  footer_text.colorize(:black).back(:green)
end

def main
  doc = <<-DOC
  JRSL - Terminal-based presentation program

  Usage:
    jrsl [<file>]
    jrsl -h | --help
    jrsl --version

  Options:
    -h --help       Show this help message
    --version       Show version

  Arguments:
    <file>          Presentation file to open [default: charla/charla.md]
  DOC

  args = Docopt.docopt(doc)

  if args["--version"]
    puts "JRSL version #{Jrsl::VERSION}"
    exit 0
  end

  slides_file = if args["<file>"].is_a?(String)
                      args["<file>"].as(String)
                    else
                      "charla/charla.md"
                    end

  terminfo = Unibilium::Terminfo.from_env
  tput = Tput.new terminfo

  tput.alternate

  # Parse slides from the specified file
  slides, metadata = if File.exists?(slides_file)
                        Jrsl.parse_slides(File.read(slides_file))
                      else
                        STDERR.puts "Error: File not found: #{slides_file}"
                        tput.cursor_reset
                        exit 1
                      end

  y_offset = 0
  slide = 0
  loop do
    tput.clear
    tput.civis

    # Build and print footer using metadata
    footer = build_footer(metadata, slide, slides.size, tput.screen.width)
    tput.cursor_pos tput.screen.height, 0
    tput.echo(footer)

    if slide < slides.size
      current = slides[slide]

      # Print title if present
      unless current.title.empty?
        print_figlet(tput, current.title, 0, 0)
      end

      # Print content if present
      unless current.content.empty?
        print_md(tput, current.content, 0, 3, tput.screen.height - 6, y_offset)
      end
    end

    tput.listen do |char, key, _|
      if char == 'q'
        tput.cursor_reset
        exit 0
      else
        case key
        when Tput::Key::Up
          if y_offset > 0
            y_offset -= 1
            break
          end
        when Tput::Key::Down
          y_offset += 1
          break
        when Tput::Key::Left
          if slide > 0
            slide -= 1
            y_offset = 0
            break
          end
        when Tput::Key::Right
          if slide < slides.size - 1
            slide += 1
            y_offset = 0
            break
          end
        end
      end
    end
  end
end
