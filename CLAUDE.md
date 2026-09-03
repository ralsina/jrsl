# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

JRSL is a terminal-based presentation program written in Crystal. It displays presentations from markdown files with braille ASCII art titles (via figlet), terminal-rendered markdown, and images (rendered in-process as half-block characters, or via the Kitty graphics protocol).

## Build and Development Commands

### Building
- `shards build` - Build the main binary
- `shards install` - Install dependencies
- **Do NOT use `--release` flag** (per user's global instructions)

### Testing
- `crystal spec` - Run all tests

### Linting
- `ameba` - Run the linter
- `ameba --fix` - Auto-fix linting issues (preferred method)
- `crystal tool format` - Format the source

### Static Builds
- `./build_static.sh` - Build static binaries using Docker (AMD64/ARM64)

## Code Structure

Everything lives in `src/jrsl.cr`:

### Parsing (in the `Jrsl` module)
- `parse_slides` - Entry point: splits a presentation file into `Slide` objects plus `PresentationMetadata`
- `parse_global_metadata` - Reads the optional first YAML block
- `parse_slide_blocks` / `read_slide_metadata` / `read_slide_content` - Read the alternating slide metadata (YAML) / content (markdown) blocks; `---` inside fenced code blocks does not split slides
- `SlideMetadata`, `PresentationMetadata` - YAML::Serializable metadata models

### Rendering helpers (in the `Jrsl` module)
- `render_markdown_to_element` - Pre-renders markdown via `Markd.to_term` into a `MarkdownElement` with measured rows/cols
- `render_image_to_string` - Renders an image as colored half-block characters (2 pixels per cell)
- `render_image_kitty` - Encodes an image as a chunked Kitty graphics protocol escape sequence
- `calculate_image_max_height`, `side_by_side_layout`, `stacked_layout`, `image_x_position`, `center_x` - Pure layout math (unit-tested)

### Drawing and app flow (top-level defs)
- `figlet_lines` / `print_figlet` - Braille ASCII art titles via `Process.run("figlet", ...)`
- `build_footer` - Footer with event/location/author and slide counter
- `draw_image` / `draw_markdown` - Draw one slide's image and markdown at given coordinates
- `render_slide` - Computes layout for one slide and draws it
- `read_action` / `apply_action` - Keyboard handling (`InputAction` enum): arrows navigate/scroll, `q` quits
- `main` - CLI (docopt), setup, main loop

### Dependencies (from shard.yml)
- `tput` - Terminal control (keyboard input, screen management)
- `markterm`/`markd` - Terminal markdown rendering (maintainer's fork)
- `crimage` - Image loading/resizing (has its own JPEG decoder)
- `sixteen` - Base16 color themes
- `docopt` - CLI parsing (maintainer's fork)

figlet is an external runtime dependency; the `smbraille.tlf` font ships in the repo root.

### Presentation Format
Single markdown file, slides separated by `---` lines. First YAML block is
global metadata (title, author, event, location). Each slide starts with a
YAML block (`title`, optional `image`, `image_position` top/center/bottom,
`image_h_position` left/right/center, `image_height`), a `---`, then the
slide's markdown content. See README.md for details and examples.

Presentations used by the maintainer live in `charla/`.

## Code Style
- Follow `.editorconfig`: 2-space indentation, LF line endings, UTF-8 encoding
- No trailing whitespace
- No `not_nil!` usage (per user's global instructions)
- Prefer descriptive names for block parameters over single letters
