# frozen_string_literal: true

RSpec.describe Toml::Merge::MergeResult do
  subject(:result) { described_class.new }

  describe "#initialize" do
    it "creates an empty result" do
      expect(result.content).to eq("")
      expect(result.line_count).to eq(0)
    end
  end

  describe "#add_line" do
    it "adds a line to the result" do
      result.add_line('title = "Test"')
      expect(result.content).to include('title = "Test"')
    end

    it "increments line count" do
      result.add_line("line 1")
      result.add_line("line 2")
      expect(result.line_count).to eq(2)
    end

    it "tracks source information" do
      result.add_line("line", source: :template)
      expect(result.statistics[:template]).to eq(1)
    end
  end

  describe "#add_node" do
    # This requires a real NodeWrapper, so we test the interface
    it "responds to add_node" do
      expect(result).to respond_to(:add_node)
    end
  end

  describe "#content" do
    it "returns the accumulated TOML content" do
      result.add_line('[server]')
      result.add_line('host = "localhost"')
      result.add_line('port = 8080')

      expect(result.content).to eq("[server]\nhost = \"localhost\"\nport = 8080\n")
    end
  end

  describe "#to_toml" do
    it "is an alias for content" do
      result.add_line("test = 1")
      expect(result.to_toml).to eq(result.content)
    end
  end

  describe "#statistics" do
    it "returns a hash with source counts" do
      result.add_line("line1", source: :template)
      result.add_line("line2", source: :destination)
      result.add_line("line3", source: :template)

      stats = result.statistics
      expect(stats[:template]).to eq(2)
      expect(stats[:destination]).to eq(1)
    end
  end
end
