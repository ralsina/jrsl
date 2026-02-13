require "markterm"
require "tput"
require "colorize"
require "yaml"
require "docopt"
require "sixteen"
require "crimage"

module Jrsl
  VERSION = "0.2.0"

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

  def self.query_cell_size : Tuple(Int16, Int16)
    thing = LibC::Winsize.new
    LibC.ioctl(STDOUT.fd, LibC::TIOCGWINSZ, pointerof(thing))
    {(thing.ws_ypixel / thing.ws_row).to_i16, (thing.ws_xpixel / thing.ws_col).to_i16}
  end

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

      # Create slide and set image properties
      slide = Slide.new(title, content)
      slide.image_path = slide_metadata.image
      slide.image_position = slide_metadata.image_position
      slide.image_h_position = slide_metadata.image_h_position
      slide.image_max_height = slide_metadata.image_height
      slides << slide
    end

    {slides, metadata}
  end

  def self.load_image(path : String) : CrImage::Image?
    unless File.exists?(path)
      return nil
    end
    CrImage.read(path)
  rescue e : Exception
    nil
  end

  # Pre-render an image to a string before TUI initialization
  # Uses half-block characters (▀) for 2x1 vertical resolution per cell
  # Returns {rendered_string, line_count, width_in_chars} or nil if loading fails
  def self.render_image_to_string(path : String, max_width : Int32, max_height : Int32) : Tuple(String, Int32, Int32)?
    image = load_image(path)
    return nil unless image

    img_width = image.bounds.width.to_i64
    img_height = image.bounds.height.to_i64

    if img_width == 0 || img_height == 0
      return nil
    end

    # Each character cell represents 2 vertical pixels
    target_pixel_width = max_width.to_i64
    target_pixel_height = max_height.to_i64 * 2

    scale_x = target_pixel_width.to_f64 / img_width.to_f64
    scale_y = target_pixel_height.to_f64 / img_height.to_f64
    scale = Math.min(Math.min(scale_x, scale_y), 1.0) # Only downscale

    scaled_width = (img_width.to_f64 * scale).to_i
    scaled_height = (img_height.to_f64 * scale).to_i

    # Clamp scaled dimensions to be safe
    scaled_width = Math.min(scaled_width, target_pixel_width)
    scaled_height = Math.min(scaled_height, target_pixel_height)

    # Make sure height is even (pairs of pixels)
    scaled_height = scaled_height - (scaled_height % 2)

    # Build output line by line
    output_lines = [] of String

    (0...scaled_height // 2).each do |line_y|
      line = String.build do |str|
        (0...scaled_width).each do |cell_x|
          # Top pixel for this cell
          top_img_x = (cell_x.to_f64 * img_width.to_f64 / scaled_width.to_f64).to_i64.clamp(0, img_width - 1)
          top_img_y = ((line_y * 2).to_f64 * img_height.to_f64 / scaled_height.to_f64).to_i64.clamp(0, img_height - 1)

          # Bottom pixel for this cell
          bot_img_x = (cell_x.to_f64 * img_width.to_f64 / scaled_width.to_f64).to_i64.clamp(0, img_width - 1)
          bot_img_y = ((line_y * 2 + 1).to_f64 * img_height.to_f64 / scaled_height.to_f64).to_i64.clamp(0, img_height - 1)

          top_color = image[top_img_x.to_i32, top_img_y.to_i32]
          bot_color = image[bot_img_x.to_i32, bot_img_y.to_i32]

          tr, tg, tb, ta = top_color.rgba
          br, bg, bb, ba = bot_color.rgba

          # Skip transparent pixels (use background color)
          if ta == 0 && ba == 0
            str << " "
          elsif ta == 0
            # Only bottom visible
            str << " ".colorize.back(Colorize::ColorRGB.new((br >> 8).to_u8, (bg >> 8).to_u8, (bb >> 8).to_u8))
          elsif ba == 0
            # Only top visible
            str << " ".colorize.back(Colorize::ColorRGB.new((tr >> 8).to_u8, (tg >> 8).to_u8, (tb >> 8).to_u8))
          else
            # Both visible - use upper half block with fg=bottom, bg=top
            fg_color = Colorize::ColorRGB.new((br >> 8).to_u8, (bg >> 8).to_u8, (bb >> 8).to_u8)
            bg_color = Colorize::ColorRGB.new((tr >> 8).to_u8, (tg >> 8).to_u8, (tb >> 8).to_u8)
            str << "▀".colorize(fg_color).back(bg_color)
          end
        end
      end
      output_lines << line
    end

    {output_lines.join("\n"), output_lines.size, scaled_width.to_i32}
  rescue e : Exception
    nil
  end

  # Render image using Kitty graphics protocol
  # Returns the escape sequence string to display the image
  def self.render_image_kitty(path : String, max_width : Int32, max_height : Int32) : Tuple(String, Int32, Int32)?
    image = load_image(path)
    return nil unless image

    img_width = image.bounds.width.to_i32
    img_height = image.bounds.height.to_i32

    if img_width == 0 || img_height == 0
      return nil
    end

    # Calculate scale to fit within max dimensions
    # max_width is terminal cells, max_height is terminal rows

    cell_pixel_height, cell_pixel_width = query_cell_size()

    target_pixel_width = max_width * cell_pixel_width
    target_pixel_height = max_height * cell_pixel_height

    scale_width = target_pixel_width.to_f64 / img_width.to_f64
    scale_height = target_pixel_height.to_f64 / img_height.to_f64
    scale = Math.min(Math.min(scale_width, scale_height), 1.0)

    new_width = (img_width * scale).to_i32
    new_height = (img_height * scale).to_i32

    # Resize the image
    resized = image.resize(new_width, new_height)

    # Encode to PNG bytes
    png_io = IO::Memory.new
    CrImage.write(png_io, resized, ".png")
    png_bytes = png_io.to_slice

    # Base64 encode
    b64_data = Base64.strict_encode(png_bytes)

    # Chunk size for Kitty protocol (4096 bytes per chunk is typical)
    chunk_size = 4096

    # Build escape sequence with chunking
    control_parts = [] of String

    # Generate unique image ID
    image_id = rand(1000000..9999999)

    offset = 0
    while offset < b64_data.size
      chunk = b64_data[offset, Math.min(chunk_size, b64_data.size - offset)]
      is_final = (offset + chunk.size >= b64_data.size)

      if is_final
        # Final chunk: m=0
        control_parts << "\e_Ga=T,i=#{image_id},q=2,f=100,m=0;#{chunk}\e\\"
      else
        # Intermediate chunk: m=1
        control_parts << "\e_Ga=T,i=#{image_id},q=2,f=100,m=1;#{chunk}\e\\"
      end

      offset += chunk.size
    end

    # Return terminal row height (round up) and column width
    terminal_rows = (new_height.to_f64 / cell_pixel_height).ceil.to_i32
    terminal_cols = (new_width.to_f64 / cell_pixel_width).ceil.to_i32
    {control_parts.join, terminal_rows, terminal_cols}
  rescue e : Exception
    nil
  end

  # Render markdown to a MarkdownElement with measured dimensions
  def self.render_markdown_to_element(markdown : String, max_width : Int32) : MarkdownElement
    rendered = Markd.to_term(markdown)
    lines = rendered.split("\n")

    rows = lines.size
    cols = lines.max_of?(&.size) || 0

    MarkdownElement.new(markdown, rendered, rows, cols)
  end

  # Calculate available height for image based on markdown size and position
  def self.calculate_image_max_height(md_rows : Int32, content_area_height : Int32, image_position : String) : Int32
    gap = 1 # One line gap between image and markdown

    if image_position == "bottom"
      # Markdown goes at top, image below
      available_height = content_area_height - md_rows - gap
      available_height = 1 if available_height < 1
      available_height
    elsif image_position == "center"
      # Image centered - need md_rows below, and equal space above so midpoint is centered
      available_height = content_area_height - (2 * md_rows) - (2 * gap)
      available_height = 1 if available_height < 1
      available_height
    else
      # "top": image at top, markdown below
      available_height = content_area_height - md_rows - gap
      available_height = 1 if available_height < 1
      available_height
    end
  end
end

def print_md(tput, markdown, x, y, h, theme, theme_name, y_offset = 0)
  rendered = if theme && theme_name
               Markd.to_term(markdown, theme: theme_name)
             else
               Markd.to_term(markdown)
             end
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

  {lines, y}
end

def print_figlet(tput, text, x, y, theme)
  normalized_text = Jrsl.normalize_for_figlet(text)
  output = `figlet -f smbraille.tlf #{normalized_text}`
  lines = output.split("\n").map(&.rstrip).reject &.empty?

  # Find the maximum line length
  max_length = lines.max_of &.size

  # Use base16 colors: base01 for background, base05 for foreground
  if theme
    bg_rgb = theme["01"]
    fg_rgb = theme["05"]
  else
    bg_rgb = Sixteen::Color.new(255, 255, 255)
    fg_rgb = Sixteen::Color.new(0, 0, 0)
  end

  # Right-pad all lines to the same length, then rjust to screen width
  lines.each do |line|
    line = line.ljust(max_length).rjust(tput.screen.width)
    tput.cursor_pos y, x
    tput.echo(line.colorize(fg_rgb.colorize).back(bg_rgb.colorize).mode(:bold))
    y += 1
  end
end

def build_footer(metadata : Jrsl::PresentationMetadata, slide_num : Int32, total_slides : Int32, width : Int32, theme)
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

  footer_text = parts.join(" / ")
  footer_text += " / " unless footer_text.empty? || slide_num < 0
  footer_text += "#{slide_num + 1}/#{total_slides}" if slide_num >= 0

  footer_text = footer_text.center(width)

  # Use base16 colors: base01 for background, base05 for foreground
  if theme
    bg_rgb = theme["01"]
    fg_rgb = theme["05"]
  else
    bg_rgb = Sixteen::Color.new(0, 128, 0)
    fg_rgb = Sixteen::Color.new(0, 0, 0)
  end

  footer_text.colorize(fg_rgb.colorize).back(bg_rgb.colorize)
end

def main
  doc = <<-DOC
  JRSL - Terminal-based presentation program

  Usage:
    jrsl [-t <theme>] [--kitty] [<file>]
    jrsl -h | --help
    jrsl --version
    jrsl --list-themes

  Options:
    -h --help       Show this help message
    --version       Show version
    --list-themes    List available color themes
    -t <theme>      Color theme to use
    --kitty         Use Kitty graphics protocol for images

  Arguments:
    <file>          Presentation file to open [default: charla/charla.md]
  DOC

  args = Docopt.docopt(doc)

  if args["--version"]
    puts "JRSL version #{Jrsl::VERSION}"
    exit 0
  end

  if args["--list-themes"]
    puts "Available color themes:"
    Sixteen.available_themes.each do |theme|
      puts "  #{theme}"
    end
    exit 0
  end

  slides_file = if args["<file>"].is_a?(String)
                  args["<file>"].as(String)
                else
                  "charla/charla.md"
                end

  # Get theme
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
      theme = nil
    end
  end

  terminfo = Unibilium::Terminfo.from_env
  tput = Tput.new terminfo

  tput.alternate

  # Parse slides from the specified file
  slides_file = if args["<file>"].is_a?(String)
                  args["<file>"].as(String)
                else
                  "charla/charla.md"
                end

  # Get the directory containing the presentation file
  presentation_dir = File.dirname(slides_file)

  slides, metadata = if File.exists?(slides_file)
                       Jrsl.parse_slides(File.read(slides_file))
                     else
                       STDERR.puts "Error: File not found: #{slides_file}"
                       tput.cursor_reset
                       exit 1
                     end

  # Check if kitty mode is enabled
  use_kitty = args["--kitty"] == true

  # Pre-render markdown before entering TUI
  # Images will be rendered on-the-fly based on actual screen dimensions
  slides.each do |slide|
    unless slide.content.empty?
      slide.markdown_element = Jrsl.render_markdown_to_element(slide.content, 119)
    end
  end

  y_offset = 0
  slide = 0
  loop do
    tput.alternate
    tput.clear
    tput.civis

    # Clear any previous Kitty graphics images and wait for it to complete
    print "\e_Ga=d,d=A\e\\"
    STDOUT.flush

    # Small delay to ensure Kitty processes the delete command
    ::sleep(Time::Span.new(nanoseconds: 1_000_000))

    # Build and print footer using metadata
    footer = build_footer(metadata, slide, slides.size, tput.screen.width, theme)
    tput.cursor_pos tput.screen.height, 0
    tput.echo(footer)

    if slide < slides.size
      current = slides[slide]
      current_y = 0

      # Print title if present
      unless current.title.empty?
        print_figlet(tput, current.title, 0, current_y, theme)
        current_y += 3
      end

      # Content area dimensions
      content_area_start = current_y
      content_area_height = tput.screen.height - content_area_start - 1
      screen_width = tput.screen.width

      # Get markdown dimensions (0x0 if none)
      md_rows = 0
      md_cols = 0
      md_lines = [] of String
      if md_element = current.markdown_element
        md_rows = md_element.rows
        md_cols = md_element.cols
        md_lines = md_element.rendered.split("\n")
      end

      # Render image with appropriate size based on markdown and screen dimensions
      img_rows = 0
      img_cols = 0
      if path = current.image_path
        # Calculate max height for image based on available space
        calculated_max_h = Jrsl.calculate_image_max_height(md_rows, content_area_height, current.image_position)
        # Use the smaller of calculated height or user-specified height
        max_h = if user_h = current.image_max_height
                     [user_h, calculated_max_h].min
                   else
                     calculated_max_h
                   end

        if use_kitty
          kitty_result = Jrsl.render_image_kitty(path, 119, max_h)
          if kitty_result
            _, img_rows, img_cols = kitty_result
            current.kitty_image = kitty_result
          end
        else
          ascii_result = Jrsl.render_image_to_string(path, 119, max_h)
          if ascii_result
            rendered_str, img_rows, img_cols = ascii_result
            current.rendered_image = ascii_result
          end
        end
      end

      # Calculate horizontal position for image
      image_x = case current.image_h_position
                when "left"
                  0
                when "right"
                  (screen_width - img_cols).clamp(0, screen_width)
                else # "center" (default)
                  ((screen_width - img_cols) // 2).clamp(0, screen_width)
                end

      # Layout based on horizontal position first
      if current.image_h_position == "left" || current.image_h_position == "right"
        # Side-by-side layout: image and markdown share vertical space
        gap = 2 # Columns between image and markdown

        if current.image_h_position == "left"
          image_x = 0
          md_x = img_cols + gap
          md_max_width = screen_width - md_x
        else # "right"
          md_x = 0
          md_max_width = screen_width - img_cols - gap
          image_x = md_max_width + gap
        end

        # Both image and markdown start at content_area_start vertically
        img_y = content_area_start
        md_y = content_area_start

        # Display image
        if kitty_img = current.kitty_image
          kitty_str, _, _ = kitty_img
          print "\e[#{img_y + 1};#{image_x}H"
          STDOUT.flush
          print kitty_str
          STDOUT.flush
          print " "
          STDOUT.flush
        elsif rendered_img = current.rendered_image
          rendered_str, _, _ = rendered_img
          rendered_str.split("\n").each_with_index do |line, line_y|
            tput.cursor_pos img_y + line_y, image_x
            tput.echo(line)
          end
        end

        # Display markdown alongside image
        visible_md_rows = [md_rows, content_area_height].min
        if visible_md_rows > 0 && md_element
          start_row = y_offset
          end_row = [start_row + visible_md_rows, md_lines.size].min
          visible_lines = md_lines[start_row...end_row] || [] of String

          visible_lines.each_with_index do |line, idx|
            tput.cursor_pos md_y + idx, md_x
            tput.echo(line)
          end
        end
      else
        # Stacked layout (center): image and markdown stacked vertically
        # Calculate horizontal position for markdown block
        md_x = ((screen_width - md_cols) // 2).clamp(0, screen_width)

        if current.image_position == "top"
          # Image at top of content area, markdown below
          img_y = content_area_start
          md_y = img_y + img_rows + 1

          # Display image
          if kitty_img = current.kitty_image
            kitty_str, _, _ = kitty_img
            print "\e[#{img_y + 1};#{image_x}H"
            STDOUT.flush
            print kitty_str
            STDOUT.flush
            print " "
            STDOUT.flush
          elsif rendered_img = current.rendered_image
            rendered_str, _, _ = rendered_img
            rendered_str.split("\n").each_with_index do |line, line_y|
              tput.cursor_pos img_y + line_y, image_x
              tput.echo(line)
            end
          end

          # Display markdown (truncated to fit remaining space)
          available_md_height = content_area_height - img_rows - 1
          available_md_height = 0 if available_md_height < 0
          visible_md_rows = [md_rows, available_md_height].min
          if visible_md_rows > 0 && md_element
            start_row = y_offset
            end_row = [start_row + visible_md_rows, md_lines.size].min
            visible_lines = md_lines[start_row...end_row] || [] of String

            visible_lines.each_with_index do |line, idx|
              tput.cursor_pos md_y + idx, md_x
              tput.echo(line)
            end
          end
        elsif current.image_position == "center"
          # Image centered vertically in space above markdown
          available_for_image = content_area_height - md_rows - 1
          img_y = content_area_start + (available_for_image - img_rows) // 2
          img_y = content_area_start if img_y < content_area_start
          md_y = content_area_start + content_area_height - md_rows

          # Display image
          if kitty_img = current.kitty_image
            kitty_str, _, _ = kitty_img
            print "\e[#{img_y + 1};#{image_x}H"
            STDOUT.flush
            print kitty_str
            STDOUT.flush
            print " "
            STDOUT.flush
          elsif rendered_img = current.rendered_image
            rendered_str, _, _ = rendered_img
            rendered_str.split("\n").each_with_index do |line, line_y|
              tput.cursor_pos img_y + line_y, image_x
              tput.echo(line)
            end
          end

          # Display markdown centered horizontally
          available_md_height = content_area_start + content_area_height - md_y
          available_md_height = 0 if available_md_height < 0
          visible_md_rows = [md_rows, available_md_height].min
          if visible_md_rows > 0 && md_element
            start_row = y_offset
            end_row = [start_row + visible_md_rows, md_lines.size].min
            visible_lines = md_lines[start_row...end_row] || [] of String

            visible_lines.each_with_index do |line, idx|
              tput.cursor_pos md_y + idx, md_x
              tput.echo(line)
            end
          end
        else # "bottom"
          # Image at bottom of content area, markdown above
          img_y = content_area_start + content_area_height - img_rows
          img_y = content_area_start if img_rows > content_area_height

          # Display markdown above image
          md_y = content_area_start
          available_md_height = [img_y - md_y, content_area_height].min
          available_md_height = 0 if available_md_height < 0
          visible_md_rows = [md_rows, available_md_height].min
          if visible_md_rows > 0 && md_element
            start_row = y_offset
            end_row = [start_row + visible_md_rows, md_lines.size].min
            visible_lines = md_lines[start_row...end_row] || [] of String

            visible_lines.each_with_index do |line, idx|
              tput.cursor_pos md_y + idx, md_x
              tput.echo(line)
            end
          end

          # Display image at bottom
          if kitty_img = current.kitty_image
            kitty_str, _, _ = kitty_img
            print "\e[#{img_y + 1};#{image_x}H"
            STDOUT.flush
            print kitty_str
            STDOUT.flush
            print " "
            STDOUT.flush
          elsif rendered_img = current.rendered_image
            rendered_str, _, _ = rendered_img
            rendered_str.split("\n").each_with_index do |line, line_y|
              tput.cursor_pos img_y + line_y, image_x
              tput.echo(line)
            end
          end
        end
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
