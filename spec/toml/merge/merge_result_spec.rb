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
      result.add_line('title = "Test"', decision: :kept_template, source: :template)
      expect(result.content).to include('title = "Test"')
    end

    it "increments line count" do
      result.add_line("line 1", decision: :kept_template, source: :template)
      result.add_line("line 2", decision: :kept_destination, source: :destination)
      expect(result.line_count).to eq(2)
    end

    it "tracks source information" do
      result.add_line("line", decision: :kept_template, source: :template)
      expect(result.statistics[:template_lines]).to eq(1)
    end

    it "tracks original line number" do
      result.add_line("line", decision: :kept_template, source: :template, original_line: 5)
      # The line should be added successfully
      expect(result.line_count).to eq(1)
    end
  end

  describe "#add_lines" do
    it "adds multiple lines" do
      lines = ["line1", "line2", "line3"]
      result.add_lines(lines, decision: :kept_template, source: :template)
      expect(result.line_count).to eq(3)
    end

    it "tracks starting line number" do
      lines = ["line1", "line2"]
      result.add_lines(lines, decision: :kept_destination, source: :destination, start_line: 10)
      expect(result.line_count).to eq(2)
    end

    it "handles empty array" do
      result.add_lines([], decision: :kept_template, source: :template)
      expect(result.line_count).to eq(0)
    end

    it "tracks statistics" do
      lines = ["line 1", "line 2"]
      result.add_lines(lines, decision: :kept_destination, source: :destination, start_line: nil)

      expect(result.line_count).to eq(2)
      expect(result.statistics[:dest_lines]).to eq(2)
    end
  end

  describe "#add_blank_line" do
    it "adds an empty line" do
      result.add_blank_line
      # The content method returns empty string for single empty line
      # since to_toml joins with \n and adds trailing newline
      expect(result.line_count).to eq(1)
    end

    it "adds blank line in between content" do
      result.add_line("line1", decision: :kept_template, source: :template)
      result.add_blank_line
      result.add_line("line2", decision: :kept_template, source: :template)
      expect(result.content).to include("\n\n")
    end

    it "accepts decision and source" do
      result.add_blank_line(decision: :added, source: :merged)
      expect(result.line_count).to eq(1)
    end

    it "adds a blank line with default decision/source" do
      expect { result.add_blank_line }.to change(result, :line_count).by(1)
      # A single blank line is tracked internally but renders as empty content
      expect(result.content).to eq("")
      # merged_lines should increment by default branch
      expect(result.statistics[:merged_lines]).to eq(1)
    end
  end

  describe "#add_node", :toml_parsing do
    let(:toml_source) do
      <<~TOML
        [server]
        host = "localhost"
        port = 8080
      TOML
    end
    let(:analysis) { Toml::Merge::FileAnalysis.new(toml_source) }

    it "adds content from a node wrapper" do
      node = analysis.tables.first
      result.add_node(node, decision: :kept_destination, source: :destination, analysis: analysis)
      expect(result.content).to include("[server]")
      expect(result.content).to include("host")
    end

    it "handles nodes without start_line" do
      mock_node = double("NodeWrapper", start_line: nil, end_line: nil)
      result.add_node(mock_node, decision: :kept_destination, source: :destination, analysis: analysis)
      expect(result.line_count).to eq(0)
    end

    it "handles nodes without end_line" do
      mock_node = double("NodeWrapper", start_line: 1, end_line: nil)
      result.add_node(mock_node, decision: :kept_destination, source: :destination, analysis: analysis)
      expect(result.line_count).to eq(0)
    end

    it "skips nil lines from analysis" do
      analysis = instance_double(Toml::Merge::FileAnalysis)
      allow(analysis).to receive(:line_at).with(1).and_return("line 1")
      allow(analysis).to receive(:line_at).with(2).and_return(nil) # nil line
      allow(analysis).to receive(:line_at).with(3).and_return("line 3")

      node = instance_double(Toml::Merge::NodeWrapper, start_line: 1, end_line: 3)

      result.add_node(node, decision: described_class::DECISION_KEPT_DEST, source: :destination, analysis: analysis)

      expect(result.line_count).to eq(2) # only non-nil lines added
      expect(result.content).to eq("line 1\nline 3\n")
    end
  end

  describe "#content" do
    it "returns the accumulated TOML content" do
      result.add_line("[server]", decision: :kept_destination, source: :destination)
      result.add_line('host = "localhost"', decision: :kept_destination, source: :destination)
      result.add_line("port = 8080", decision: :kept_destination, source: :destination)

      expect(result.content).to eq("[server]\nhost = \"localhost\"\nport = 8080\n")
    end

    it "ensures trailing newline" do
      result.add_line("test = 1", decision: :kept_template, source: :template)
      expect(result.content).to end_with("\n")
    end

    it "handles empty content" do
      expect(result.content).to eq("")
    end
  end

  describe "#to_toml" do
    it "is an alias for content" do
      result.add_line("test = 1", decision: :kept_template, source: :template)
      expect(result.to_toml).to eq(result.content)
    end

    it "ensures a trailing newline only when non-empty" do
      expect(result.to_toml).to eq("")
      result.add_line("x = 1", decision: :kept_template, source: :template)
      expect(result.to_toml.end_with?("\n")).to be true
    end
  end

  describe "#statistics" do
    it "returns a hash with source counts" do
      result.add_line("line1", decision: :kept_template, source: :template)
      result.add_line("line2", decision: :kept_destination, source: :destination)
      result.add_line("line3", decision: :kept_template, source: :template)

      stats = result.statistics
      expect(stats[:template_lines]).to eq(2)
      expect(stats[:dest_lines]).to eq(1)
    end

    it "tracks merged lines" do
      result.add_line("line1", decision: :merged, source: :merged)
      stats = result.statistics
      expect(stats[:merged_lines]).to eq(1)
    end
  end

  describe "decision constants" do
    it "defines DECISION_KEPT_DEST" do
      expect(described_class::DECISION_KEPT_DEST).not_to be_nil
    end

    it "defines DECISION_KEPT_TEMPLATE" do
      expect(described_class::DECISION_KEPT_TEMPLATE).not_to be_nil
    end

    it "defines DECISION_ADDED" do
      expect(described_class::DECISION_ADDED).not_to be_nil
    end

    it "defines DECISION_MERGED" do
      expect(described_class::DECISION_MERGED).not_to be_nil
    end

    it "defines DECISION_FREEZE_BLOCK" do
      expect(described_class::DECISION_FREEZE_BLOCK).not_to be_nil
    end
  end
end
