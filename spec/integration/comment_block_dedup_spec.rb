# frozen_string_literal: true

require "spec_helper"

RSpec.describe "TOML bidirectional comment block deduplication" do
  describe Toml::Merge::SmartMerger do
    context "when a floating comment block is attached to different nodes in template vs destination" do
      # Simulates: a positional comment block (gap-separated) gets greedily
      # attached to different nodes because dest has an extra key between
      # the comment and the key the template attaches it to.
      let(:template) do
        <<~TOML
          [server]
          host = "localhost"

          # NOTE: Development-only settings below.
          # Adjust these for your local environment.
          debug = true
        TOML
      end

      let(:destination) do
        <<~TOML
          [server]
          host = "localhost"

          # NOTE: Development-only settings below.
          # Adjust these for your local environment.
          port = 8080
          debug = true
        TOML
      end

      it "does not duplicate the floating comment block" do
        merged = described_class.new(template, destination).merge
        occurrences = merged.scan("NOTE: Development-only settings below.").size
        expect(occurrences).to eq(1), "Expected 1 occurrence of floating comment block, got #{occurrences}.\nMerged output:\n#{merged}"
      end

      it "does not duplicate with preference: :template" do
        merged = described_class.new(template, destination, preference: :template).merge
        occurrences = merged.scan("NOTE: Development-only settings below.").size
        expect(occurrences).to eq(1), "Expected 1 occurrence of floating comment block, got #{occurrences}.\nMerged output:\n#{merged}"
      end

      it "does not duplicate with preference: :destination" do
        merged = described_class.new(template, destination, preference: :destination).merge
        occurrences = merged.scan("NOTE: Development-only settings below.").size
        expect(occurrences).to eq(1), "Expected 1 occurrence of floating comment block, got #{occurrences}.\nMerged output:\n#{merged}"
      end

      it "preserves all data keys from both sources" do
        merged = described_class.new(template, destination).merge
        expect(merged).to include("host")
        expect(merged).to include("port")
        expect(merged).to include("debug")
      end
    end

    context "when both template and dest have identical leading comments on the same matched key" do
      let(:template) do
        <<~TOML
          # Database configuration
          [database]
          url = "postgres://localhost/dev"
        TOML
      end

      let(:destination) do
        <<~TOML
          # Database configuration
          [database]
          url = "postgres://localhost/prod"
          pool = 10
        TOML
      end

      it "emits the comment only once" do
        merged = described_class.new(template, destination).merge
        occurrences = merged.scan("# Database configuration").size
        expect(occurrences).to eq(1), "Expected 1 occurrence of '# Database configuration', got #{occurrences}.\nMerged output:\n#{merged}"
      end
    end
  end
end
