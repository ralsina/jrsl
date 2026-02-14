---
title: JRSL
author: Roberto Alsina
event: JRSL Demo
location: The Terminal
---
title: What is JRSL?
---
JRSL is a **terminal-based presentation tool** written in Crystal.

It displays markdown slides with:
- ASCII art titles (via figlet)
- Image support (ASCII or Kitty protocol)
- Multiple layout options
- Theme support via base16
---
title: Basic Slides
---
Each slide is separated by `---` markers.

You can use standard *markdown* **formatting** in your content.

- Bullet points work
- As do numbered lists
- And `inline code`
---
title: Slide Metadata
---
Each slide can have YAML metadata:

```yaml
title: My Slide Title
image: photo.jpg
image_position: top
image_h_position: center
```
---
title: Image Positions
image: ralsina.jpg
image_position: top
image_h_position: center
---
Images can be positioned:
- **top** - image at top, text below
- **center** - image centered vertically
- **bottom** - image at bottom, text above
---
title: Side by Side
image: ralsina.jpg
image_position: center
image_h_position: left
---
When `image_h_position` is **left** or **right**, the image and text appear side by side.

This is great for showing code examples alongside screenshots, or explaining diagrams with accompanying text.
---
title: Image on Right
image: ralsina.jpg
image_position: center
image_h_position: right
---
The same layout works with the image on the right side.

Text flows naturally in the available space and wraps to fit the terminal width.
---
title: Themes
---
JRSL supports base16 color themes via the `-t` flag:

```
jrsl -t solarized presentation.md
jrsl -t dracula presentation.md
jrsl -t nord presentation.md
```

Use `jrsl --list-themes` to see all available options.
---
title: Kitty Graphics
---
For terminals supporting the Kitty graphics protocol:

```
jrsl --kitty presentation.md
```

This renders images as actual graphics instead of ASCII art, providing much higher quality image display.
---
title: Navigation
---
Use arrow keys to navigate:

- **Left/Right** - Previous/Next slide
- **Up/Down** - Scroll long content
- **q** - Quit presentation
---
title: Getting Started
---
Install dependencies and build:

```bash
shards install
shards build
```

Run a presentation:

```bash
./bin/jrsl my-presentation.md
```
---
title: Thanks!
---
JRSL is open source and available on GitHub.

Questions? Comments? Contributions welcome!
