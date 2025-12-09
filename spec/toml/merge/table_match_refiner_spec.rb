# frozen_string_literal: true

RSpec.describe Toml::Merge::TableMatchRefiner do
  describe "#initialize" do
    it "accepts a threshold" do
      refiner = described_class.new(threshold: 0.6)
      expect(refiner.threshold).to eq(0.6)
    end

    it "accepts custom weights" do
      refiner = described_class.new(weights: {name_match: 0.7})
      expect(refiner.weights[:name_match]).to eq(0.7)
    end

    it "uses default threshold when not specified" do
      refiner = described_class.new
      expect(refiner.threshold).to eq(Ast::Merge::MatchRefinerBase::DEFAULT_THRESHOLD)
    end
  end

  describe "#call" do
    subject(:refiner) { described_class.new(threshold: 0.5) }

    it "returns an array" do
      result = refiner.call([], [])
      expect(result).to be_an(Array)
    end

    it "returns empty array when no tables provided" do
      result = refiner.call([], [])
      expect(result).to be_empty
    end

    # Full matching tests require actual NodeWrapper objects
    # These document the expected behavior

    context "with similar table names" do
      it "matches tables with similar names" do
        pending "Requires tree-sitter TOML parser for real NodeWrapper objects"
        raise "Not implemented"
      end
    end

    context "with different table names" do
      it "does not match tables below threshold" do
        pending "Requires tree-sitter TOML parser for real NodeWrapper objects"
        raise "Not implemented"
      end
    end
  end

  describe "Levenshtein distance" do
    subject(:refiner) { described_class.new }

    # We test the private method indirectly through similarity scoring
    it "considers 'server' and 'servers' as similar" do
      # This would be tested via actual table matching
      pending "Requires tree-sitter TOML parser"
      raise "Not implemented"
    end
  end
end
