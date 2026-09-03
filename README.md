# jrsl

jrsl is a terminal-based presentation program written in Crystal.

## Features

- Display presentations from markdown files
- ASCII art titles via figlet (using the bundled `smbraille.tlf` braille font)
- Images rendered in-process as colored half-block characters, or natively
  through the Kitty graphics protocol with `--kitty`
- Syntax highlighting via [markterm](https://github.com/ralsina/markterm)
- [Base16](https://base16.net) color theme support (using the [sixteen](https://github.com/ralsina/sixteen) library)

## Installation

Requirements: [Crystal](https://crystal-lang.org) >= 1.14 and
[figlet](https://github.com/cmatsuoka/figlet) (with its `figlet` binary on
your `PATH`).

```sh
git clone https://github.com/ralsina/jrsl.git
cd jrsl
shards install
shards build
```

## Usage

### Running a presentation

```sh
# Run the default presentation (charla/charla.md)
./bin/jrsl

# Run a specific presentation file
./bin/jrsl path/to/presentation.md

# Use a specific base16 color theme
./bin/jrsl -t monokai

# Use the Kitty graphics protocol for images (Kitty and some other terminals)
./bin/jrsl --kitty

# List available themes
./bin/jrsl --list-themes
```

### Controls

- `Left`/`Right` - Navigate between slides
- `Up`/`Down` - Scroll within a slide
- `q` - Quit

## Presentation Format

Presentations are written as markdown files with YAML metadata blocks. The
file consists of:

1. **Global metadata** (optional) - Metadata at the top of the file for the entire presentation
2. **Slides** - Each slide has a title (YAML) and content (markdown)

### Example

```markdown
---
title: My Presentation
author: Jane Doe
event: Conference 2024
location: Buenos Aires
---
title: Welcome to My Talk
---
* First bullet point
* Second bullet point
* Third bullet point
---
title: Code Example
image: screenshots/demo.png
image_h_position: right
---
Here is some code:

```crystal
def hello
  puts "Hello, World!"
end
```
---
title: Questions?
---
* Thanks for listening!
* Email: jane@example.com
```

A line containing only `---` separates slides. `---` lines inside fenced
code blocks (``` or ~~~) do not split slides.

### Global Metadata

The global metadata (first YAML block) supports:

- `title` - Presentation title (used in footer)
- `author` - Author name (shown in footer)
- `event` - Event name (shown in footer)
- `location` - Location (shown in footer)

### Slide Metadata

Each slide starts with a small YAML block containing:

- `title` - Slide title, rendered as braille ASCII art via figlet (required)
- `image` - Path to an image file to show on this slide (optional)
- `image_position` - Vertical placement of the image: `top`, `center` (default) or `bottom`
- `image_h_position` - Horizontal placement of the image: `left`, `right` or `center` (default). `left`/`right` place the image side-by-side with the content.
- `image_height` - Maximum height of the image in terminal rows (optional; by default the image uses the available space)

## Development

```sh
# Run tests
crystal spec

# Run linter
ameba
# Auto-fix linting issues
ameba --fix

# Build
shards build
```

## Contributing

1. Fork it (<https://github.com/ralsina/jrsl/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Roberto Alsina](https://github.com/ralsina) - creator and maintainer
