require "markterm"
require "tput"
require "colorize"
require "yaml"
require "docopt"
require "sixteen"
require "crimage"

module Jrsl
  VERSION = "0.3.0"

  # Maximum width in terminal columns for rendered images
  IMAGE_MAX_WIDTH = 119

  # Effective maximum image width in cells: never wider than the screen
  def self.effective_image_width(screen_width : Int32) : Int32
    Math.min(IMAGE_MAX_WIDTH, screen_width)
  end

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

  # Returns {cell_height_px, cell_width_px}, or nil when the terminal does not
  # report pixel dimensions (very common outside graphical terminals).
  def self.query_cell_size : Tuple(Int16, Int16)?
    thing = LibC::Winsize.new
    LibC.ioctl(STDOUT.fd, LibC::TIOCGWINSZ, pointerof(thing))
    return if thing.ws_row <= 0 || thing.ws_col <= 0
    return if thing.ws_ypixel <= 0 || thing.ws_xpixel <= 0

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
    # Dimensions the current rendered_image/kitty_image was rendered for;
    # a mismatch (terminal resize) triggers re-rendering
    property image_cache_key : Tuple(Int32, Int32)?

    def initialize(@title : String, @content : String = "")
      @image_path = nil
      @image_max_height = nil
      @rendered_image = nil
      @kitty_image = nil
      @markdown_element = nil
      @image_cache_key = nil
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

  # Parse the optional global YAML metadata block at the top of the file.
  # Returns the metadata and the line index where slide parsing starts.
  def self.parse_global_metadata(lines : Array(String)) : Tuple(PresentationMetadata, Int32)
    metadata = PresentationMetadata.new
    i = 0
    return {metadata, i} unless i < lines.size && lines[i] == "---"

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

    {metadata, i}
  end

  # Read the slide metadata (YAML) lines starting at index i.
  # Returns the parsed metadata and the index after any "---" delimiter.
  def self.read_slide_metadata(lines : Array(String), i : Int32) : Tuple(SlideMetadata, Int32)
    yaml_lines = [] of String
    while i < lines.size && lines[i] != "---" && !lines[i].blank?
      yaml_lines << lines[i]
      i += 1
    end

    i += 1 if i < lines.size && lines[i] == "---" # Skip the delimiter between metadata and content

    {SlideMetadata.from_yaml(yaml_lines.join("\n")), i}
  end

  # Return "```" or "~~~" when the line opens a fenced code block: at least
  # 3 marker characters, optionally indented, optionally followed by an
  # info string (CommonMark allows no info string on closing fences)
  def self.fence_open_marker(line : String) : String?
    stripped = line.lstrip
    return "```" if stripped.starts_with?("```")
    return "~~~" if stripped.starts_with?("~~~")
    nil
  end

  # Return "```" or "~~~" when the line consists solely of fence marker
  # characters, i.e. it can close a fenced code block
  def self.fence_close_marker(line : String) : String?
    stripped = line.strip
    return "```" if stripped.size >= 3 && stripped.chars.all? { |character| character == '`' }
    return "~~~" if stripped.size >= 3 && stripped.chars.all? { |character| character == '~' }
    nil
  end

  # Read the slide content (markdown) lines starting at index i, until the
  # next "---" delimiter or end of file. "---" lines inside fenced code
  # blocks do not count as delimiters.
  # Returns the content lines and the index of the delimiter (or lines.size).
  def self.read_slide_content(lines : Array(String), i : Int32) : Tuple(Array(String), Int32)
    content_lines = [] of String
    open_fence : String? = nil
    while i < lines.size
      line = lines[i]
      if fence = open_fence
        content_lines << line
        open_fence = nil if fence_close_marker(line) == fence
      elsif line == "---"
        break
      else
        content_lines << line
        open_fence = fence_open_marker(line)
      end
      i += 1
    end
    {content_lines, i}
  end

  # Parse alternating blocks starting at start_index: slide metadata (YAML)
  # followed by content (markdown), separated by "---" lines
  def self.parse_slide_blocks(lines : Array(String), start_index : Int32) : Array(Slide)
    slides = [] of Slide
    i = start_index

    while i < lines.size
      # Skip any blank lines before metadata
      while i < lines.size && lines[i].blank?
        i += 1
      end
      break if i >= lines.size

      # Slide metadata is directly after "---", no additional "---" wrapper
      yaml_lines_empty = lines[i] == "---" || lines[i].blank?
      if yaml_lines_empty
        i += 1
        next
      end

      slide_metadata, i = read_slide_metadata(lines, i)

      # Create slide with title and content, preserving trailing newline if present
      content_lines, i = read_slide_content(lines, i)
      content = content_lines.join("\n")
      content += "\n" unless content.lines.empty?

      # Create slide and set image properties
      slide = Slide.new(slide_metadata.title, content)
      slide.image_path = slide_metadata.image
      slide.image_position = slide_metadata.image_position
      slide.image_h_position = slide_metadata.image_h_position
      slide.image_max_height = slide_metadata.image_height
      slides << slide
    end

    slides
  end

  def self.parse_slides(content : String) : Tuple(Array(Slide), PresentationMetadata)
    lines = content.lines
    metadata, i = parse_global_metadata(lines)
    slides = parse_slide_blocks(lines, i)
    {slides, metadata}
  end

  def self.load_image(path : String) : CrImage::Image?
    unless File.exists?(path)
      return
    end
    CrImage.read(path)
  rescue Exception
    nil
  end

  # Pre-render an image to a string before TUI initialization
  # Uses half-block characters (▀) for 2x1 vertical resolution per cell
  # Returns {rendered_string, line_count, width_in_chars} or nil if loading fails
  def self.render_image_to_string(path : String, max_width : Int32, max_height : Int32) : Tuple(String, Int32, Int32)?
    image = load_image(path)
    return unless image

    img_width = image.bounds.width.to_i64
    img_height = image.bounds.height.to_i64

    if img_width == 0 || img_height == 0
      return
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
  rescue Exception
    nil
  end

  # Render image using Kitty graphics protocol
  # Returns the escape sequence string to display the image
  def self.render_image_kitty(path : String, max_width : Int32, max_height : Int32) : Tuple(String, Int32, Int32)?
    image = load_image(path)
    return unless image

    img_width = image.bounds.width.to_i32
    img_height = image.bounds.height.to_i32

    if img_width == 0 || img_height == 0
      return
    end

    # Calculate scale to fit within max dimensions
    # max_width is terminal cells, max_height is terminal rows

    cell_size = query_cell_size()
    return unless cell_size
    cell_pixel_height, cell_pixel_width = cell_size

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
  rescue Exception
    nil
  end

  # Render markdown to a MarkdownElement with measured dimensions
  def self.render_markdown_to_element(markdown : String, max_width : Int32) : MarkdownElement
    rendered = Markd.to_term(markdown, max_width: max_width)
    lines = rendered.split("\n")

    rows = lines.size
    cols = lines.max_of?(&.size) || 0

    MarkdownElement.new(markdown, rendered, rows, cols)
  end

  # Calculate available height for image based on markdown size and position
  def self.calculate_image_max_height(md_rows : Int32, content_area_height : Int32, image_position : String, image_h_position : String) : Int32
    gap = 1 # One line gap between image and markdown

    # Side-by-side layouts: image uses full height
    if image_h_position == "left" || image_h_position == "right"
      return content_area_height
    end

    # Stacked layouts: reserve space for markdown
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

  # Column where a block of content_cols cells starts to be centered on a
  # screen of screen_width columns
  def self.center_x(screen_width : Int32, content_cols : Int32) : Int32
    ((screen_width - content_cols) // 2).clamp(0, screen_width)
  end

  # Column where the image starts given its horizontal placement setting
  def self.image_x_position(h_position : String, screen_width : Int32, img_cols : Int32) : Int32
    x = case h_position
        when "left"
          0
        when "right"
          screen_width - img_cols
        else # "center" (default)
          center_x(screen_width, img_cols)
        end
    x.clamp(0, screen_width)
  end

  # Side-by-side layout columns: Returns {image_x, md_x}
  def self.side_by_side_layout(h_position : String, screen_width : Int32, img_cols : Int32) : Tuple(Int32, Int32)
    gap = 2 # Columns between image and markdown

    if h_position == "right"
      md_x = 0
      image_x = screen_width - img_cols
      {image_x, md_x}
    else # "left"
      image_x = 0
      md_x = img_cols + gap
      {image_x, md_x}
    end
  end

  # Vertical positions for stacked layouts.
  # Returns {img_y, md_y, available_md_height}
  def self.stacked_layout(position : String, content_area_start : Int32, content_area_height : Int32, img_rows : Int32, md_rows : Int32) : Tuple(Int32, Int32, Int32)
    if position == "top"
      # Image at top of content area, markdown below
      img_y = content_area_start
      md_y = img_y + img_rows + 1
      available_md_height = content_area_height - img_rows - 1
    elsif position == "center"
      # Image centered vertically in space above bottom-anchored markdown
      available_for_image = content_area_height - md_rows - 1
      img_y = content_area_start + (available_for_image - img_rows) // 2
      img_y = content_area_start if img_y < content_area_start
      md_y = content_area_start + content_area_height - md_rows
      available_md_height = content_area_start + content_area_height - md_y
    else # "bottom"
      # Image at bottom of content area, markdown above
      img_y = content_area_start + content_area_height - img_rows
      img_y = content_area_start if img_rows > content_area_height
      md_y = content_area_start
      available_md_height = [img_y - md_y, content_area_height].min
    end

    available_md_height = 0 if available_md_height < 0
    {img_y, md_y, available_md_height}
  end
end

def figlet_lines(text : String) : Array(String)?
  normalized_text = Jrsl.normalize_for_figlet(text)
  output = IO::Memory.new
  process = Process.new("figlet", ["-f", "smbraille.tlf", normalized_text], output: output)
  status = process.wait
  return unless status.success?

  output.rewind.gets_to_end.split("\n").map(&.rstrip).reject &.empty?
rescue File::NotFoundError
  nil
end

def print_figlet(tput, text, x, y, theme)
  # Fall back to the plain title if figlet is missing or fails
  lines = figlet_lines(text) || [text]

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

def draw_image(tput, slide : Jrsl::Slide, img_y : Int32, image_x : Int32)
  if kitty_img = slide.kitty_image
    kitty_str, _, _ = kitty_img
    print "\e[#{img_y + 1};#{image_x}H"
    STDOUT.flush
    print kitty_str
    STDOUT.flush
    print " "
    STDOUT.flush
  elsif rendered_img = slide.rendered_image
    rendered_str, _, _ = rendered_img
    rendered_str.split("\n").each_with_index do |line, line_y|
      tput.cursor_pos img_y + line_y, image_x
      tput.echo(line)
    end
  end
end

# Draw the markdown lines starting at y_offset, up to max_rows rows
def draw_markdown(tput, md_lines : Array(String), md_rows : Int32, md_x : Int32, md_y : Int32, y_offset : Int32, max_rows : Int32)
  visible_md_rows = [md_rows, max_rows].min
  return if visible_md_rows <= 0

  start_row = y_offset
  end_row = [start_row + visible_md_rows, md_lines.size].min
  visible_lines = md_lines[start_row...end_row] || [] of String

  visible_lines.each_with_index do |line, idx|
    tput.cursor_pos md_y + idx, md_x
    tput.echo(line)
  end
end

enum InputAction
  None
  Quit
  ScrollUp
  ScrollDown
  PreviousSlide
  NextSlide
end

# Wait for a meaningful keypress. Keys that would act on a boundary
# (scrolling up at the top, changing slides at the edges) keep waiting.
def read_action(tput, y_offset : Int32, slide_index : Int32, total_slides : Int32) : InputAction
  action = InputAction::None
  tput.listen do |char, key, _|
    if char == 'q'
      action = InputAction::Quit
      break
    end

    case key
    when Tput::Key::Up
      if y_offset > 0
        action = InputAction::ScrollUp
        break
      end
    when Tput::Key::Down
      action = InputAction::ScrollDown
      break
    when Tput::Key::Left
      if slide_index > 0
        action = InputAction::PreviousSlide
        break
      end
    when Tput::Key::Right
      if slide_index < total_slides - 1
        action = InputAction::NextSlide
        break
      end
    end
  end
  action
end

def load_theme(theme_name : String?)
  return unless theme_name

  begin
    Sixteen.theme_with_fallback(theme_name)
  rescue Exception
    STDERR.puts "Warning: Theme '#{theme_name}' not found, using default colors"
    nil
  end
end

# Render the slide image if needed (respecting the cache) and return its
# dimensions {rows, cols}
def ensure_image_dimensions(slide : Jrsl::Slide, use_kitty : Bool, md_rows : Int32, content_area_height : Int32, screen_width : Int32) : Tuple(Int32, Int32)
  return {0, 0} unless path = slide.image_path

  image_width = Jrsl.effective_image_width(screen_width)

  # Calculate max height for image based on available space
  calculated_max_h = Jrsl.calculate_image_max_height(md_rows, content_area_height, slide.image_position, slide.image_h_position)
  # Use the smaller of calculated height or user-specified height
  max_h = if user_h = slide.image_max_height
            [user_h, calculated_max_h].min
          else
            calculated_max_h
          end

  cache_key = {image_width, max_h}
  if slide.image_cache_key != cache_key
    slide.kitty_image = nil
    slide.rendered_image = nil

    if use_kitty
      kitty_result = Jrsl.render_image_kitty(path, image_width, max_h)
      if kitty_result
        slide.kitty_image = kitty_result
      else
        # Terminal reports no pixel size or kitty encoding failed:
        # fall back to half-block rendering
        slide.rendered_image = Jrsl.render_image_to_string(path, image_width, max_h)
      end
    else
      slide.rendered_image = Jrsl.render_image_to_string(path, image_width, max_h)
    end
    slide.image_cache_key = cache_key
  end

  if kitty_img = slide.kitty_image
    {kitty_img[1], kitty_img[2]}
  elsif rendered_img = slide.rendered_image
    {rendered_img[1], rendered_img[2]}
  else
    {0, 0}
  end
end

def render_slide(tput, slides : Array(Jrsl::Slide), slide_index : Int32, y_offset : Int32, theme, use_kitty : Bool)
  current = slides[slide_index]
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

  img_rows, img_cols = ensure_image_dimensions(current, use_kitty, md_rows, content_area_height, screen_width)

  # Layout based on horizontal position first
  if current.image_h_position == "left" || current.image_h_position == "right"
    # Side-by-side layout: image and markdown share vertical space
    image_x, md_x = Jrsl.side_by_side_layout(current.image_h_position, screen_width, img_cols)
    img_y = content_area_start
    md_y = content_area_start

    draw_image(tput, current, img_y, image_x)
    draw_markdown(tput, md_lines, md_rows, md_x, md_y, y_offset, content_area_height)
  else
    # Stacked layout: image and markdown stacked vertically
    image_x = Jrsl.image_x_position(current.image_h_position, screen_width, img_cols)
    md_x = Jrsl.center_x(screen_width, md_cols)
    img_y, md_y, available_md_height = Jrsl.stacked_layout(current.image_position, content_area_start, content_area_height, img_rows, md_rows)

    draw_image(tput, current, img_y, image_x)
    draw_markdown(tput, md_lines, md_rows, md_x, md_y, y_offset, available_md_height)
  end
end

def print_theme_list
  puts "Available color themes:"
  Sixteen.available_themes.each do |available_theme|
    puts "  #{available_theme}"
  end
end

# Handle the flags that print information and exit. Returns true if handled.
def cli_flags_handled(args) : Bool
  if args["--version"]
    puts "JRSL version #{Jrsl::VERSION}"
    return true
  end

  if args["--list-themes"]
    print_theme_list
    return true
  end

  false
end

# Pre-render the slides' markdown before entering the TUI.
# Images are rendered on-the-fly based on actual screen dimensions.
# Markdown width is half screen width for side-by-side layouts.
def prerender_markdown(slides : Array(Jrsl::Slide), terminal_width : Int32)
  md_width = terminal_width // 2 - 2 # Half screen minus gap
  slides.each do |slide|
    next if slide.content.empty?

    slide.markdown_element = Jrsl.render_markdown_to_element(slide.content, md_width)
  end
end

# Apply an input action to the (slide, y_offset) state
def apply_action(action : InputAction, slide : Int32, y_offset : Int32) : Tuple(Int32, Int32)
  case action
  when InputAction::ScrollUp
    {slide, y_offset - 1}
  when InputAction::ScrollDown
    {slide, y_offset + 1}
  when InputAction::PreviousSlide
    {slide - 1, 0}
  when InputAction::NextSlide
    {slide + 1, 0}
  else
    {slide, y_offset}
  end
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

  exit 0 if cli_flags_handled(args)

  theme = load_theme(args["-t"].as?(String).try &.downcase)

  terminfo = Unibilium::Terminfo.from_env
  tput = Tput.new terminfo

  tput.alternate

  slides_file = args["<file>"].as?(String) || "charla/charla.md"
  unless File.exists?(slides_file)
    STDERR.puts "Error: File not found: #{slides_file}"
    tput.cursor_reset
    exit 1
  end

  slides, metadata = Jrsl.parse_slides(File.read(slides_file))

  # Check if kitty mode is enabled
  use_kitty = args["--kitty"] == true

  terminal_size = Term::Screen.size || {24, 80}
  _, terminal_width = terminal_size
  prerender_markdown(slides, terminal_width)

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

    render_slide(tput, slides, slide, y_offset, theme, use_kitty) if slide < slides.size

    action = read_action(tput, y_offset, slide, slides.size)
    if action.quit?
      tput.cursor_reset
      exit 0
    end
    slide, y_offset = apply_action(action, slide, y_offset)
  end
end
