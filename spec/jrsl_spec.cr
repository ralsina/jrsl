require "./spec_helper"
require "yaml"

# Inline parsing logic for testing
module Jrsl
  class Slide
    property title : String
    property content : String
    property image_path : String?
    property image_position : String
    property image_max_height : Int32?

    def initialize(@title : String, @content : String = "")
      @image_path = nil
      @image_position = "center"
      @image_max_height = nil
    end
  end

  class SlideMetadata
    include YAML::Serializable

    property title : String
    property image : String?
    property image_position : String?
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
      slide.image_position = slide_metadata.image_position || "center"
      slide.image_max_height = slide_metadata.image_height
      slides << slide
    end

    {slides, metadata}
  end
end

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
  end

  describe ".render_image_to_string" do
    it "renders actual presentation image without crashing" do
      image_path = "#{__DIR__}/../charla/ralsina.jpg"
      result = Jrsl.render_image_to_string(image_path, 119, 14)

      # Should return a tuple with rendered string, line count, and width
      result.should_not be_nil
      rendered, line_count, width = result.not_nil!
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

      result.should_not be_nil
      rendered, line_count, width = result.not_nil!

      # Width should be much smaller than the string size (which includes ANSI codes)
      width.should be < rendered.size
    end
  end
end
