require "./spec_helper"
require "yaml"

describe Jrsl do
  describe ".parse_slides" do
    it "parses a simple presentation" do
      content = <<-YAML
        ---
        title: My Talk
        author: Roberto
        ---
        title: Slide 1
        ---
        * Point 1
        * Point 2
        ---
        title: Slide 2
        ---
        * Point A
        * Point B
        YAML

      slides, metadata = Jrsl.parse_slides(content)

      slides.size.should eq(2)
      slides[0].title.should eq("Slide 1")
      slides[0].content.should eq("* Point 1\n* Point 2\n")
      slides[1].title.should eq("Slide 2")
      slides[1].content.should eq("* Point A\n* Point B\n")

      metadata.title.should eq("My Talk")
      metadata.author.should eq("Roberto")
    end

    it "parses slides with blank lines between them" do
      content = <<-YAML
        ---
        title: Talk
        ---
        title: First Slide
        ---
        Content here

        ---
        title: Second Slide
        ---
        More content
        YAML

      slides, metadata = Jrsl.parse_slides(content)

      slides.size.should eq(2)
      slides[0].title.should eq("First Slide")
      slides[1].title.should eq("Second Slide")
    end

    it "handles slides with empty content" do
      content = <<-YAML
        ---
        title: Talk
        ---
        title: Title Only
        ---
        ---
        title: With Content
        ---
        Some content
        YAML

      slides, _metadata = Jrsl.parse_slides(content)

      slides.size.should eq(2)
      slides[0].title.should eq("Title Only")
      slides[0].content.should eq("")
      slides[1].title.should eq("With Content")
    end

    it "handles single slide" do
      content = <<-YAML
        ---
        title: Only Talk
        ---
        title: Only Slide
        ---
        Only content
        YAML

      slides, metadata = Jrsl.parse_slides(content)

      slides.size.should eq(1)
      slides[0].title.should eq("Only Slide")
      slides[0].content.should eq("Only content\n")
      metadata.title.should eq("Only Talk")
    end

    it "parses presentation with event and location" do
      content = <<-YAML
        ---
        title: My Talk
        author: Roberto
        event: JRSL 2024
        location: Santa Fe
        ---
        title: Slide 1
        ---
        Content
        YAML

      slides, metadata = Jrsl.parse_slides(content)

      metadata.title.should eq("My Talk")
      metadata.author.should eq("Roberto")
      metadata.event.should eq("JRSL 2024")
      metadata.location.should eq("Santa Fe")
    end

    it "keeps --- inside fenced code blocks within the same slide" do
      content = <<-YAML
        ---
        title: Talk
        ---
        title: Code Slide
        ---
        ```crystal
        if a > b
          puts "bigger"
        end
        ---
        this is still the slide
        ```
        ---
        title: Next Slide
        ---
        After
        YAML

      slides, _metadata = Jrsl.parse_slides(content)

      slides.size.should eq(2)
      slides[0].content.should eq(<<-CONTENT)
        ```crystal
        if a > b
          puts "bigger"
        end
        ---
        this is still the slide
        ```

        CONTENT
      slides[1].title.should eq("Next Slide")
    end

    it "supports tilde fences too" do
      content = <<-YAML
        ---
        title: Talk
        ---
        title: Tilde Slide
        ---
        ~~~
        text with ---
        inside
        ~~~
        ---
        title: Next
        ---
        After
        YAML

      slides, _metadata = Jrsl.parse_slides(content)

      slides.size.should eq(2)
      slides[0].content.should contain("text with ---")
      slides[1].title.should eq("Next")
    end

    it "splits on --- again after a fence closes" do
      content = <<-YAML
        ---
        title: Talk
        ---
        title: One
        ---
        ```
        fenced
        ```
        ---
        title: Two
        ---
        plain text
        YAML

      slides, _metadata = Jrsl.parse_slides(content)

      slides.size.should eq(2)
      slides[0].content.should eq("```\nfenced\n```\n")
      slides[1].content.should eq("plain text\n")
    end

    it "treats non-fence backtick lines as content" do
      content = <<-YAML
        ---
        title: Talk
        ---
        title: Inline
        ---
        inline `code` and --- text
        YAML

      slides, _metadata = Jrsl.parse_slides(content)

      slides.size.should eq(1)
      slides[0].content.should eq("inline `code` and --- text\n")
    end

    it "parses image metadata with position and height" do
      content = <<-YAML
        ---
        title: Talk
        ---
        title: With Image
        image: photo.jpg
        image_position: bottom
        image_h_position: right
        image_height: 12
        ---
        Content
        YAML

      slides, _metadata = Jrsl.parse_slides(content)

      slides.size.should eq(1)
      slides[0].image_path.should eq("photo.jpg")
      slides[0].image_position.should eq("bottom")
      slides[0].image_h_position.should eq("right")
      slides[0].image_max_height.should eq(12)
    end

    it "defaults image position values when not specified" do
      content = <<-YAML
        ---
        title: Talk
        ---
        title: Plain Slide
        ---
        Content
        YAML

      slides, _metadata = Jrsl.parse_slides(content)

      slides[0].image_path.should be_nil
      slides[0].image_position.should eq("center")
      slides[0].image_h_position.should eq("left")
      slides[0].image_max_height.should be_nil
    end
  end

  describe ".normalize_for_figlet" do
    it "replaces accented lowercase vowels" do
      Jrsl.normalize_for_figlet("áéíóú").should eq("aeiou")
    end

    it "replaces accented uppercase vowels" do
      Jrsl.normalize_for_figlet("ÁÉÍÓÚ").should eq("AEIOU")
    end

    it "replaces ñ and ç" do
      Jrsl.normalize_for_figlet("España").should eq("Espana")
      Jrsl.normalize_for_figlet("Ç").should eq("C")
    end

    it "expands ß to ss" do
      Jrsl.normalize_for_figlet("Straße").should eq("Strasse")
    end

    it "leaves plain ASCII untouched" do
      Jrsl.normalize_for_figlet("Hello World 123").should eq("Hello World 123")
    end
  end

  describe ".calculate_image_max_height" do
    it "uses full height for side-by-side layouts" do
      result = Jrsl.calculate_image_max_height(10, 30, "center", "left")
      result.should eq(30)
      result = Jrsl.calculate_image_max_height(10, 30, "center", "right")
      result.should eq(30)
    end

    it "reserves markdown rows plus gap for top layout" do
      Jrsl.calculate_image_max_height(5, 30, "top", "center").should eq(24)
    end

    it "reserves markdown rows plus gap for bottom layout" do
      Jrsl.calculate_image_max_height(5, 30, "bottom", "center").should eq(24)
    end

    it "reserves twice the markdown rows for centered layout" do
      Jrsl.calculate_image_max_height(5, 30, "center", "center").should eq(18)
    end

    it "never returns less than one row" do
      Jrsl.calculate_image_max_height(50, 30, "top", "center").should eq(1)
    end
  end

  describe ".render_image_to_string" do
    it "renders actual presentation image without crashing" do
      image_path = "#{__DIR__}/../charla/ralsina.jpg"
      result = Jrsl.render_image_to_string(image_path, 119, 14)

      # Should return a tuple with rendered string, line count, and width
      rendered, line_count, width = result || fail("expected a rendered image")
      rendered.should be_a(String)
      rendered.size.should be > 0
      line_count.should be > 0
      line_count.should be <= 14
      width.should be > 0
      width.should be <= 119
    end

    it "returns nil for non-existent image" do
      result = Jrsl.render_image_to_string("/nonexistent/image.jpg", 50, 10)
      result.should be_nil
    end

    it "returns correct width that doesn't include ANSI codes" do
      image_path = "#{__DIR__}/../charla/ralsina.jpg"
      result = Jrsl.render_image_to_string(image_path, 119, 14)

      rendered, line_count, width = result || fail("expected a rendered image")

      # Width should be much smaller than the string size (which includes ANSI codes)
      width.should be < rendered.size
    end
  end
end
