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

    context "when a TOML file preamble should stay singular during destination-preference merging" do
      let(:template) do
        <<~TOML
          # Shared development environment for this gem.
          # Local overrides belong in .env.local (loaded via dotenvy through mise).

          [env]
          K_SOUP_COV_MIN_BRANCH = "76"
          K_SOUP_COV_MIN_LINE = "92"
        TOML
      end

      let(:destination) do
        <<~TOML
          # Shared development environment for ast-merge.
          # Local overrides belong in .env.local (loaded via dotenvy through mise).
          [env]
          K_SOUP_COV_MIN_BRANCH = "81"
          K_SOUP_COV_MIN_LINE = "91"
        TOML
      end

      %i[mri citrus parslet].each do |backend|
        it "keeps one preamble and one env table for #{backend}", :"#{backend}_backend" do
          TreeHaver.with_backend(backend) do
            merged = described_class.new(
              template,
              destination,
              preference: :destination,
              add_template_only_nodes: true,
            ).merge

            expect(merged.scan(/^# Shared development environment/).size).to eq(1), <<~MSG
              Expected a single file preamble for #{backend}, got:
              #{merged}
            MSG
            expect(merged.scan(/^\[env\]/).size).to eq(1), <<~MSG
              Expected a single [env] table for #{backend}, got:
              #{merged}
            MSG
            expect(merged.scan(/^K_SOUP_COV_MIN_BRANCH = /).size).to eq(1), <<~MSG
              Expected one K_SOUP_COV_MIN_BRANCH assignment for #{backend}, got:
              #{merged}
            MSG
            expect(merged.scan(/^K_SOUP_COV_MIN_LINE = /).size).to eq(1), <<~MSG
              Expected one K_SOUP_COV_MIN_LINE assignment for #{backend}, got:
              #{merged}
            MSG
          end
        end
      end
    end

    context "when template and destination disagree only about the blank line after a file preamble" do
      let(:template) do
        <<~TOML
          # tsdl configuration - tree-sitter grammar versions
          # https://github.com/stackmystack/tsdl
          #
          # Run: tsdl build --out-dir /usr/local/lib
          # Or let .devcontainer/scripts/setup-tree-sitter.sh handle it.

          out-dir = "/usr/local/lib"

          [parsers]
          json = "v0.24.8"
        TOML
      end

      let(:destination) do
        <<~TOML
          # tsdl configuration - tree-sitter grammar versions
          # https://github.com/stackmystack/tsdl
          #
          # Run: tsdl build --out-dir /usr/local/lib
          # Or let .devcontainer/scripts/setup-tree-sitter.sh handle it.
          out-dir = "/usr/local/lib"

          [parsers]
          json = "v0.24.8"
        TOML
      end

      %i[mri citrus parslet].each do |backend|
        it "keeps the preamble singular for #{backend}", :"#{backend}_backend" do
          TreeHaver.with_backend(backend) do
            merged = described_class.new(
              template,
              destination,
              preference: :template,
              add_template_only_nodes: true,
            ).merge

            expect(merged.scan(/^# tsdl configuration - tree-sitter grammar versions$/).size).to eq(1), <<~MSG
              Expected a single file preamble for #{backend}, got:
              #{merged}
            MSG
            expect(merged.scan(/^# https:\/\/github.com\/stackmystack\/tsdl$/).size).to eq(1), <<~MSG
              Expected a single tsdl URL comment for #{backend}, got:
              #{merged}
            MSG
            expect(merged.scan(/^out-dir = /).size).to eq(1), <<~MSG
              Expected a single out-dir assignment for #{backend}, got:
              #{merged}
            MSG
          end
        end
      end
    end

    context "when destination preamble begins with duplicated copies of the template preamble" do
      let(:template) do
        <<~TOML
          # Shared development environment for this gem.
          # Local overrides belong in .env.local (loaded via dotenvy through mise).

          [env]
          K_SOUP_COV_MIN_BRANCH = "76"
          K_SOUP_COV_MIN_LINE = "92"
        TOML
      end

      let(:destination) do
        <<~TOML
          # Shared development environment for this gem.
          # Local overrides belong in .env.local (loaded via dotenvy through mise).
          # Shared development environment for this gem.
          # Local overrides belong in .env.local (loaded via dotenvy through mise).
          # Shared development environment for tree_haver.
          # Local overrides belong in .env.local (loaded via dotenvy through mise).
          [env]
          K_SOUP_COV_MIN_BRANCH = "76"
          K_SOUP_COV_MIN_LINE = "92"
        TOML
      end

      %i[mri citrus parslet].each do |backend|
        it "removes the duplicated template preamble prefix for #{backend}", :"#{backend}_backend" do
          TreeHaver.with_backend(backend) do
            merged = described_class.new(
              template,
              destination,
              preference: :destination,
              add_template_only_nodes: true,
            ).merge

            expect(merged.scan(/^# Shared development environment for this gem\.$/).size).to eq(0), <<~MSG
              Expected duplicated template preambles to be removed for #{backend}, got:
              #{merged}
            MSG
            expect(merged.scan(/^# Shared development environment for tree_haver\.$/).size).to eq(1), <<~MSG
              Expected the destination-specific preamble to remain singular for #{backend}, got:
              #{merged}
            MSG
          end
        end
      end
    end

    context "when a floating comment block loses its separating gap under template preference" do
      let(:template) do
        <<~TOML
          [server]
          host = "localhost"
          # NOTE: Development-only settings below.
          debug = true
        TOML
      end

      let(:destination) do
        <<~TOML
          [server]
          host = "localhost"

          # NOTE: Development-only settings below.
          debug = false
        TOML
      end

      %i[mri citrus parslet].each do |backend|
        it "attaches the comment to the chosen node for #{backend}", :"#{backend}_backend" do
          TreeHaver.with_backend(backend) do
            merged = described_class.new(
              template,
              destination,
              preference: :template,
              add_template_only_nodes: true,
            ).merge

            expect(merged).to include("# NOTE: Development-only settings below.\ndebug = true"), <<~MSG
              Expected the floating comment block to become attached when the separating gap disappears for #{backend}, got:
              #{merged}
            MSG
            expect(merged).not_to include("host = \"localhost\"\n\n# NOTE: Development-only settings below."), <<~MSG
              Expected the blank-line gap before the comment block to collapse for #{backend}, got:
              #{merged}
            MSG
          end
        end
      end
    end

    context "when a floating comment block loses its owner but keeps its separating gap" do
      let(:template) do
        <<~TOML
          [server]
          host = "localhost"
          port = 8080
        TOML
      end

      let(:destination) do
        <<~TOML
          [server]
          host = "localhost"

          # NOTE: Development-only settings below.
          debug = false

          port = 8080
        TOML
      end

      %i[mri citrus parslet].each do |backend|
        it "keeps the comment block floating for #{backend}", :"#{backend}_backend" do
          TreeHaver.with_backend(backend) do
            merged = described_class.new(
              template,
              destination,
              preference: :destination,
              add_template_only_nodes: true,
              remove_template_missing_nodes: true,
            ).merge

            expect(merged).to include("host = \"localhost\"\n\n# NOTE: Development-only settings below.\n\nport = 8080"), <<~MSG
              Expected the floating comment block to remain positional when its owner disappears but the gap remains for #{backend}, got:
              #{merged}
            MSG
          end
        end
      end
    end

    context "when a floating comment block loses its owner and the gap collapses" do
      let(:template) do
        <<~TOML
          [server]
          host = "localhost"
          # NOTE: runtime port
          port = 8080
        TOML
      end

      let(:destination) do
        <<~TOML
          [server]
          host = "localhost"

          # NOTE: Development-only settings below.
          debug = false
          port = 8080
        TOML
      end

      %i[mri citrus parslet].each do |backend|
        it "reattaches the comment block to the surviving node for #{backend}", :"#{backend}_backend" do
          TreeHaver.with_backend(backend) do
            merged = described_class.new(
              template,
              destination,
              preference: :template,
              add_template_only_nodes: true,
              remove_template_missing_nodes: true,
            ).merge

            expect(merged).to include("# NOTE: Development-only settings below.\n# NOTE: runtime port\nport = 8080"), <<~MSG
              Expected the floating comment block to reattach to the surviving node when the gap collapses for #{backend}, got:
              #{merged}
            MSG
          end
        end
      end
    end
  end
end
