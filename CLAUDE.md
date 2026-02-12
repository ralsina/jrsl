# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

JRSL is a terminal-based presentation program written in Crystal. It displays presentations from the `charla/` directory with markdown content, ASCII art titles (via figlet), and optional images (via timg).

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

### Static Builds
- `./build_static.sh` - Build static binaries using Docker (AMD64/ARM64)

## Code Structure

### Entry Point
- `src/jrsl.cr` - Single-file application containing all main logic

### Key Functions (in src/jrsl.cr)
- `print_md` - Renders markdown content using Markd.to_term
- `print_figlet` - Displays ASCII art titles using figlet (smbraille font)
- `print_footer` - Shows presentation footer with title and navigation hints
- `print_image` - Displays images using timg
- `main` - Main application loop with keyboard handling

### Dependencies (from shard.yml)
- `drawille-cr` - Terminal graphics
- `tput` - Terminal control (keyboard input, screen management)
- `stumpy_jpeg` - JPEG image processing
- `markterm` - Terminal markdown rendering (maintainer's fork)

### Presentation Structure
Presentations live in `charla/` directory with numbered subdirectories:
```
charla/
  0-title/
    slide.md    # Markdown content
    title.txt   # Optional ASCII art title
    image.jpg   # Optional image
```

### External Commands Used
The application shells out to external commands:
- `figlet -f smbraille.tlf` - For ASCII art titles
- `timg` - For image display in terminal

## Code Style
- Follow `.editorconfig`: 2-space indentation, LF line endings, UTF-8 encoding
- No trailing whitespace
- No `not_nil!` usage (per user's global instructions)
- Prefer descriptive names for block parameters over single letters
