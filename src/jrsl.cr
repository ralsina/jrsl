require "markterm"
require "tput"
require "colorize"

module Jrsl
  VERSION = "0.1.0"
end

def print_md(tput, markdown, x, y, h, y_offset = 0)
  rendered = Markd.to_term(markdown)
  lines = rendered.split("\n")[y_offset..-1]
  max_y = y + h

  if lines.size < h
    y += h//2 - lines.size//2
  end

  lines.each do |line|
    tput.cursor_pos y, x
    tput.echo line
    y += 1
    break if y > max_y
  end
end

def print_figlet(tput, text, x, y)
  tput.cursor_pos y, x
  lines = `figlet -f smbraille.tlf #{text}`.strip.split("\n")
  lines.each do |line|
    line = line.rjust(tput.screen.width)
    line = line.colorize(:black).back(:white).mode(:bold)
    tput.cursor_pos y, x
    tput.echo line
    y += 1
  end
end

def print_footer(tput, text)
  text = text.colorize(:black).back(:green)
  tput.cursor_pos tput.screen.height, 0
  tput.echo(text)
end

def print_image(tput, image, x, y, w, h)
  data = `timg -U #{image} -g#{w}x#{h}`.strip
  tput.cursor_pos y, x
  tput.echo data
end

def main
  terminfo = Unibilium::Terminfo.from_env
  tput = Tput.new terminfo

  tput.alternate

  y_offset = 0
  slide = 0
  loop do
    tput.clear
    tput.civis

    # Al justificar el string hay que sacar 1 char por cada corazón porque unicode
    print_footer tput, "JRSL 2024 💗 Santa Fe 💗 Haciendo Cosas Raras Para Gente Normal".center(tput.screen.width - 2)

    md_path = "charla/#{slide}/slide.md"
    image_path = "charla/#{slide}/image.jpg"
    title_path = "charla/#{slide}/title.txt"

    if File.exists? title_path
      title = File.read(title_path).strip
      print_figlet(tput, title, 0, 0)
    end

    if File.exists? image_path
      print_image(tput, image_path, tput.screen.width - 30, 2, 30, 30)
    end

    if File.exists? md_path
      print_md(tput, File.read(md_path), 0, 3, tput.screen.height - 6, y_offset)
    end

    tput.listen do |char, key, sequence|
      if char == 'q'
        tput.cursor_reset
        exit 0
      else
        case key
        when Tput::Key::Up
          y_offset -= 1 if y_offset > 0
          break
        when Tput::Key::Down
          y_offset += 1
          break
        when Tput::Key::Left
          slide -= 1 if slide > 0
          break
        when Tput::Key::Right
          slide += 1 if File.exists? "charla/#{slide + 1}"
          break
        end
      end
    end
  end
end

main
