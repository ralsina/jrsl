# JRSL to Termisu Port Plan

## Overview

This document outlines the plan for porting JRSL from `tput.cr` to `Termisu`.

## Key Differences

### tput.cr (Current)
- **Immediate-mode rendering**: Draw directly to terminal
- **Simple API**: `cursor_pos`, `echo`, `clear`
- **Callback-based input**: `tput.listen { |char, key, _| ... }`
- **Direct terminal control**

### Termisu (Target)
- **Retained-mode rendering**: Draw to cell buffer, then `render()`
- **Cell-based API**: `set_cell(x, y, char, fg, bg, attr)`
- **Event loop API**: `poll_event`, `each_event` with structured events
- **Double-buffered diff rendering**

## Required Changes

### 1. Main Loop Restructuring

**Current (tput.cr):**
```crystal
loop do
  tput.alternate
  tput.clear
  tput.civis

  # Draw slide content
  print_md(tput, markdown, x, y, h, theme, theme_name)
  print_figlet(tput, text, x, y, theme)
  print_image(tput, path, x, y)

  tput.listen do |char, key, _|
    # Handle input
  end
end
```

**New (Termisu):**
```crystal
termisu = Termisu.new
begin
  loop do
    if event = termisu.poll_event(50)
      case event
      when Termisu::Event::Key
        break if event.key.escape?
        handle_navigation(event.key)
      when Termisu::Event::Resize
        termisu.sync
      end
    end

    # Draw slide content
    draw_slide(termisu, current_slide)

    termisu.render
  end
ensure
  termisu.close
end
```

### 2. Rendering Functions

All rendering functions need to be rewritten to use `set_cell`:

**Current:**
```crystal
def print_figlet(tput, text, x, y, theme)
  output = `figlet -f smbraille.tlf #{text}`
  lines = output.split("\n")
  lines.each do |line|
    tput.cursor_pos y, x
    tput.echo(line.colorize(...))
    y += 1
  end
end
```

**New:**
```crystal
def print_figlet(termisu, text, x, y, theme)
  output = `figlet -f smbraille.tlf #{text}`
  lines = output.split("\n")
  lines.each_with_index do |line, idx|
    line.each_char_with_index do |char, cidx|
      termisu.set_cell(x + cidx, y + idx, char, fg: ..., bg: ...)
    end
  end
end
```

### 3. Text Rendering

Need to convert colorized strings to individual cell operations.

**Challenge:** JRSL currently uses `Colorize` module which produces ANSI strings.
**Solution:** Parse ANSI codes or rework color handling to use Termisu::Color directly.

### 4. Image Display

Images are currently displayed as ANSI art or Kitty protocol. For Termisu:

- **ASCII art**: Render using `set_cell` with appropriate colors
- **Kitty protocol**: Still output escape sequences directly (bypass cell buffer)

### 5. Footer Display

**Current:**
```crystal
footer = build_footer(...)
tput.cursor_pos height, 0
tput.echo(footer)
```

**New:**
```crystal
footer = build_footer(...)
footer.each_char_with_index do |char, idx|
  termisu.set_cell(idx, height, char, fg: ..., bg: ...)
end
```

## Migration Steps

### Phase 1: Skeleton (Proof of Concept)
1. Create `jrsl-termisu.cr` with basic Termisu setup
2. Implement main event loop
3. Display a simple "Hello World" slide
4. Basic navigation (Left/Right arrows)

### Phase 2: Core Features
1. Port `print_figlet` to Termisu
2. Port markdown rendering
3. Add footer display
4. Implement slide transitions

### Phase 3: Images
1. Port ASCII art image rendering
2. Port Kitty protocol rendering
3. Handle image positioning (top/center/bottom, left/center/right)

### Phase 4: Polish
1. Theme support (convert sixteen colors to Termisu::Color)
2. Resize handling
3. Scrolling for long content
4. Testing and bug fixes

### Phase 5: Replace Main Binary
1. Update `src/main.cr` to use Termisu version
2. Run full test suite
3. Performance comparison
4. Documentation updates

## Challenges

### 1. Color System Conversion

**Problem:** JRSL uses `Sixteen` color theme + `Colorize` module.
**Solution:** Create helper functions to convert `Sixteen::Color` to `Termisu::Color`.

```crystal
def to_termisu_color(color : Sixteen::Color) : Termisu::Color
  Termisu::Color.rgb(color.r >> 8, color.g >> 8, color.b >> 8)
end
```

### 2. String Rendering

**Problem:** Current code renders pre-formatted strings (with ANSI codes).
**Solution:** Either:
- Parse ANSI codes and convert to cells (complex)
- Store raw text and style info, render with Termisu colors (cleaner)
- For kitty images, still output escape sequences directly

### 3. Kitty Graphics Protocol

**Problem:** Kitty protocol uses terminal escape sequences that bypass cell rendering.
**Solution:** Output these directly to terminal before/after `render()`, ensuring proper cursor positioning.

### 4. Performance

**Risk:** Cell-by-cell rendering may be slower than direct string output.
**Mitigation:** Termisu's diff-based rendering should compensate, but needs benchmarking.

## Estimated Effort

- Phase 1: 2-3 hours
- Phase 2: 4-6 hours
- Phase 3: 3-4 hours
- Phase 4: 2-3 hours
- Phase 5: 2-3 hours

**Total: 13-19 hours**

## Recommendation

Given the complexity, I recommend:

1. **Start with Phase 1** as a proof-of-concept to validate the approach
2. **Create a parallel implementation** in `src/jrsl_termisu.cr` rather than replacing the current code
3. **Compare performance and UX** before committing to the full port
4. **Consider a hybrid approach** where Termisu handles the event loop and terminal management, but rendering still uses direct output for complex content

Would you like me to proceed with Phase 1 (skeleton implementation)?
