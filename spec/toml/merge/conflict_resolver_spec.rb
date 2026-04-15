# frozen_string_literal: true

require "spec_helper"
require "ast/merge/rspec/shared_examples"

RSpec.describe Toml::Merge::ConflictResolver do
  # ConflictResolver requires real FileAnalysis objects with parsed content
  # These tests document the expected interface
  it_behaves_like "Ast::Merge::ConflictResolverBase" do
    let(:conflict_resolver_class) { described_class }
    let(:strategy) { :batch }
    let(:build_conflict_resolver) do
      ->(preference:, template_analysis:, dest_analysis:, **opts) {
        described_class.new(
          template_analysis,
          dest_analysis,
          preference: preference,
          add_template_only_nodes: opts.fetch(:add_template_only_nodes, false),
        )
      }
    end
    let(:build_mock_analysis) do
      -> { double("MockAnalysis") }
    end
  end

  it_behaves_like "Ast::Merge::ConflictResolverBase batch strategy" do
    let(:conflict_resolver_class) { described_class }
    let(:build_conflict_resolver) do
      ->(preference:, template_analysis:, dest_analysis:, **opts) {
        described_class.new(
          template_analysis,
          dest_analysis,
          preference: preference,
          add_template_only_nodes: opts.fetch(:add_template_only_nodes, false),
        )
      }
    end
    let(:build_mock_analysis) do
      -> { double("MockAnalysis") }
    end
  end

  let(:template_content) do
    <<~TOML
      [server]
      host = "localhost"
      port = 8080
    TOML
  end

  let(:dest_content) do
    <<~TOML
      [server]
      host = "production.example.com"
      port = 443
      ssl = true
    TOML
  end

  describe "#initialize" do
    it "accepts template and destination analyses" do
      template_analysis = Toml::Merge::FileAnalysis.new(template_content)
      dest_analysis = Toml::Merge::FileAnalysis.new(dest_content)

      resolver = described_class.new(
        template_analysis,
        dest_analysis,
        preference: :destination,
        add_template_only_nodes: false,
      )

      expect(resolver).to be_a(described_class)
    end

    it "accepts optional match_refiner" do
      template_analysis = Toml::Merge::FileAnalysis.new(template_content)
      dest_analysis = Toml::Merge::FileAnalysis.new(dest_content)
      refiner = Toml::Merge::TableMatchRefiner.new

      resolver = described_class.new(
        template_analysis,
        dest_analysis,
        preference: :destination,
        add_template_only_nodes: false,
        match_refiner: refiner,
      )

      expect(resolver).to be_a(described_class)
    end
  end

  describe "#resolve" do
    it "populates the result with merged content" do
      template_analysis = Toml::Merge::FileAnalysis.new(template_content)
      dest_analysis = Toml::Merge::FileAnalysis.new(dest_content)
      result = Toml::Merge::MergeResult.new

      resolver = described_class.new(
        template_analysis,
        dest_analysis,
        preference: :destination,
        add_template_only_nodes: false,
      )

      resolver.resolve(result)

      expect(result.content).not_to be_empty
    end

    it "handles preference :template" do
      template_analysis = Toml::Merge::FileAnalysis.new(template_content)
      dest_analysis = Toml::Merge::FileAnalysis.new(dest_content)
      result = Toml::Merge::MergeResult.new

      resolver = described_class.new(
        template_analysis,
        dest_analysis,
        preference: :template,
        add_template_only_nodes: false,
      )

      resolver.resolve(result)

      expect(result.content).not_to be_empty
    end

    it "preserves destination leading and inline comments for matched keys under template preference", :mri_backend, :toml_grammar do
      template_toml = <<~TOML
        [database]

        title = "template"
      TOML

      dest_toml = <<~TOML
        [database]

        # keep this title doc

        title = "destination" # keep this inline note
      TOML

      TreeHaver.with_backend(:mri) do
        template_analysis = Toml::Merge::FileAnalysis.new(template_toml)
        dest_analysis = Toml::Merge::FileAnalysis.new(dest_toml)
        result = Toml::Merge::MergeResult.new

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :template,
          add_template_only_nodes: false,
        )

        resolver.resolve(result)

        expect(result.content).to eq(<<~TOML)
          [database]

          # keep this title doc

          title = "template" # keep this inline note
        TOML
      end
    end

    it "preserves comments for removed destination-only keys when removal is enabled", :mri_backend, :toml_grammar do
      template_toml = <<~TOML
        [database]
        title = "template"
      TOML

      dest_toml = <<~TOML
        [database]
        title = "destination"
        # keep removed key doc
        legacy = "destination" # keep removed inline
      TOML

      TreeHaver.with_backend(:mri) do
        template_analysis = Toml::Merge::FileAnalysis.new(template_toml)
        dest_analysis = Toml::Merge::FileAnalysis.new(dest_toml)
        result = Toml::Merge::MergeResult.new

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :destination,
          add_template_only_nodes: false,
          remove_template_missing_nodes: true,
        )

        resolver.resolve(result)

        expect(result.content).to eq(<<~TOML)
          [database]
          title = "destination"
          # keep removed key doc
          # keep removed inline
        TOML
      end
    end

    it "raises when an inline comment exists but the shared inline region is missing", :mri_backend, :toml_grammar do
      analysis = Toml::Merge::FileAnalysis.new(<<~TOML)
        [database] # keep inline
      TOML

      skip "FileAnalysis not valid" unless analysis.valid?

      resolver = described_class.new(analysis, analysis, preference: :template)
      node = analysis.tables.first

      allow(resolver).to receive(:attachment_region).and_call_original
      allow(resolver).to receive(:attachment_region)
        .with(node, analysis, :inline_region)
        .and_return(nil)

      expect {
        resolver.send(
          :preferred_inline_comment_text,
          node,
          analysis,
          comment_source_node: nil,
          comment_analysis: analysis,
        )
      }.to raise_error(
        Toml::Merge::ConflictResolver::MissingSharedInlineRegionError,
        /Expected shared inline region/,
      )
    end

    it "preserves destination docs for adjacent matched tables under template preference", :mri_backend, :toml_grammar do
      template_toml = <<~TOML
        [one]
        a = 1

        [two]
        b = 2
      TOML

      dest_toml = <<~TOML
        [one]
        a = 10

        # keep second table docs
        [two] # keep second inline
        b = 20
      TOML

      TreeHaver.with_backend(:mri) do
        template_analysis = Toml::Merge::FileAnalysis.new(template_toml)
        dest_analysis = Toml::Merge::FileAnalysis.new(dest_toml)
        result = Toml::Merge::MergeResult.new

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :template,
          add_template_only_nodes: false,
        )

        resolver.resolve(result)

        expect(result.content).to eq(<<~TOML)
          [one]
          a = 1

          # keep second table docs
          [two] # keep second inline
          b = 2
        TOML
      end
    end

    it "keeps a destination-owned first-node preamble singular when the template models it as a root preamble", :mri_backend, :toml_grammar do
      template_toml = <<~TOML
        # Shared development environment for this gem.
        # Local overrides belong in .env.local (loaded via dotenvy through mise).

        [env]
        K_SOUP_COV_MIN_BRANCH = "65"
        K_SOUP_COV_MIN_LINE = "90"
      TOML

      dest_toml = <<~TOML
        # Shared development environment for ast-merge.
        # Local overrides belong in .env.local (loaded via dotenvy through mise).
        [env]
        K_SOUP_COV_MIN_BRANCH = "65"
        K_SOUP_COV_MIN_LINE = "90"
      TOML

      TreeHaver.with_backend(:mri) do
        template_analysis = Toml::Merge::FileAnalysis.new(template_toml)
        dest_analysis = Toml::Merge::FileAnalysis.new(dest_toml)
        result = Toml::Merge::MergeResult.new

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :destination,
          add_template_only_nodes: true,
        )

        resolver.resolve(result)

        expect(result.content).to eq(<<~TOML)
          # Shared development environment for ast-merge.
          # Local overrides belong in .env.local (loaded via dotenvy through mise).
          [env]
          K_SOUP_COV_MIN_BRANCH = "65"
          K_SOUP_COV_MIN_LINE = "90"
        TOML
      end
    end

    it "keeps a single TOML preamble when only blank-line ownership differs", :mri_backend, :toml_grammar do
      template_toml = <<~TOML
        # tsdl configuration - tree-sitter grammar versions
        # https://github.com/stackmystack/tsdl
        #
        # Run: tsdl build --out-dir /usr/local/lib
        # Or let .devcontainer/scripts/setup-tree-sitter.sh handle it.

        out-dir = "/usr/local/lib"

        [parsers]
        json = "v0.24.8"
      TOML

      dest_toml = <<~TOML
        # tsdl configuration - tree-sitter grammar versions
        # https://github.com/stackmystack/tsdl
        #
        # Run: tsdl build --out-dir /usr/local/lib
        # Or let .devcontainer/scripts/setup-tree-sitter.sh handle it.
        out-dir = "/usr/local/lib"

        [parsers]
        json = "v0.24.8"
      TOML

      TreeHaver.with_backend(:mri) do
        template_analysis = Toml::Merge::FileAnalysis.new(template_toml)
        dest_analysis = Toml::Merge::FileAnalysis.new(dest_toml)
        result = Toml::Merge::MergeResult.new

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :template,
          add_template_only_nodes: true,
        )

        resolver.resolve(result)

        expect(result.content).to eq(<<~TOML)
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
    end

    it "collapses duplicated shared preamble prefixes back to the destination-specific first-node docs", :mri_backend, :toml_grammar do
      template_toml = <<~TOML
        # Shared development environment for this gem.
        # Local overrides belong in .env.local (loaded via dotenvy through mise).

        [env]
        DEBUG = "false"
        KETTLE_DEV_DEBUG = "false"
        KETTLE_TEST_SILENT = "true"

        [tools]
        ruby = "4.0.2"
      TOML

      dest_toml = <<~TOML
        # Shared development environment for this gem.
        # Local overrides belong in .env.local (loaded via dotenvy through mise).
        # Shared development environment for this gem.
        # Local overrides belong in .env.local (loaded via dotenvy through mise).
        # Shared development environment for tree_haver.
        # Local overrides belong in .env.local (loaded via dotenvy through mise).
        [env]
        DEBUG = "false"
        KETTLE_DEV_DEBUG = "false"
        KETTLE_TEST_SILENT = "true"

        [tools]
        ruby = "4.0.2"
      TOML

      TreeHaver.with_backend(:mri) do
        template_analysis = Toml::Merge::FileAnalysis.new(template_toml)
        dest_analysis = Toml::Merge::FileAnalysis.new(dest_toml)
        result = Toml::Merge::MergeResult.new

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :destination,
          add_template_only_nodes: true,
        )

        resolver.resolve(result)

        expect(result.content).to eq(<<~TOML)
          # Shared development environment for tree_haver.
          # Local overrides belong in .env.local (loaded via dotenvy through mise).
          [env]
          DEBUG = "false"
          KETTLE_DEV_DEBUG = "false"
          KETTLE_TEST_SILENT = "true"

          [tools]
          ruby = "4.0.2"
        TOML
      end
    end

    it "preserves the duplicated shared preamble prefix when healing is skipped", :mri_backend, :toml_grammar do
      template_toml = <<~TOML
        # Shared development environment for this gem.
        # Local overrides belong in .env.local (loaded via dotenvy through mise).

        [env]
        DEBUG = "false"
      TOML

      dest_toml = <<~TOML
        # Shared development environment for this gem.
        # Local overrides belong in .env.local (loaded via dotenvy through mise).
        # Shared development environment for tree_haver.
        # Local overrides belong in .env.local (loaded via dotenvy through mise).
        [env]
        DEBUG = "false"
      TOML

      TreeHaver.with_backend(:mri) do
        template_analysis = Toml::Merge::FileAnalysis.new(template_toml)
        dest_analysis = Toml::Merge::FileAnalysis.new(dest_toml)
        result = Toml::Merge::MergeResult.new

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :destination,
          add_template_only_nodes: true,
          corruption_handling: :skip,
        )

        resolver.resolve(result)

        expect(result.content.scan(/^# Shared development environment/).size).to eq(2)
        expect(result.content).to include("# Shared development environment for this gem.")
        expect(result.content).to include("# Shared development environment for tree_haver.")
      end
    end

    it "handles add_template_only_nodes: true" do
      template_content_with_extra = <<~TOML
        [server]
        host = "localhost"
        port = 8080

        [database]
        url = "sqlite://db.sqlite"
      TOML

      dest_content_minimal = <<~TOML
        [server]
        host = "production.example.com"
      TOML

      template_analysis = Toml::Merge::FileAnalysis.new(template_content_with_extra)
      dest_analysis = Toml::Merge::FileAnalysis.new(dest_content_minimal)
      result = Toml::Merge::MergeResult.new

      resolver = described_class.new(
        template_analysis,
        dest_analysis,
        preference: :destination,
        add_template_only_nodes: true,
      )

      resolver.resolve(result)

      expect(result.content).not_to be_empty
      expect(result.content).to include("[database]")
    end

    it "merges array nodes" do
      template_with_array = <<~TOML
        items = [1, 2, 3]
      TOML

      dest_with_array = <<~TOML
        items = [4, 5, 6]
      TOML

      template_analysis = Toml::Merge::FileAnalysis.new(template_with_array)
      dest_analysis = Toml::Merge::FileAnalysis.new(dest_with_array)
      result = Toml::Merge::MergeResult.new

      resolver = described_class.new(
        template_analysis,
        dest_analysis,
        preference: :destination,
        add_template_only_nodes: false,
      )

      resolver.resolve(result)

      expect(result.content).not_to be_empty
    end

    it "merges inline table nodes" do
      template_with_inline = <<~TOML
        config = { a = 1, b = 2 }
      TOML

      dest_with_inline = <<~TOML
        config = { a = 10, c = 3 }
      TOML

      template_analysis = Toml::Merge::FileAnalysis.new(template_with_inline)
      dest_analysis = Toml::Merge::FileAnalysis.new(dest_with_inline)
      result = Toml::Merge::MergeResult.new

      resolver = described_class.new(
        template_analysis,
        dest_analysis,
        preference: :destination,
        add_template_only_nodes: false,
      )

      resolver.resolve(result)

      expect(result.content).not_to be_empty
    end

    it "handles matching node signatures" do
      # Create TOML where both have the same table name
      template_toml = <<~TOML
        [server]
        host = "template.example.com"
        port = 8080
      TOML

      dest_toml = <<~TOML
        [server]
        host = "dest.example.com"
        ssl = true
      TOML

      template_analysis = Toml::Merge::FileAnalysis.new(template_toml)
      dest_analysis = Toml::Merge::FileAnalysis.new(dest_toml)
      result = Toml::Merge::MergeResult.new

      resolver = described_class.new(
        template_analysis,
        dest_analysis,
        preference: :destination,
        add_template_only_nodes: true,
      )

      resolver.resolve(result)

      expect(result.content).to include("[server]")
      expect(result.content).to include("host = \"dest.example.com\"") # destination preferred
      expect(result.content).to include("port = 8080") # from template
      expect(result.content).to include("ssl = true") # from destination
    end

    it "merges tables with similar names using refined matching" do
      template_content = <<~TOML
        [server]
        host = "localhost"
        port = 8080
      TOML

      dest_content = <<~TOML
        [servers]
        host = "production.example.com"
        port = 443
      TOML

      template_analysis = Toml::Merge::FileAnalysis.new(template_content)
      dest_analysis = Toml::Merge::FileAnalysis.new(dest_content)
      result = Toml::Merge::MergeResult.new

      resolver = described_class.new(
        template_analysis,
        dest_analysis,
        preference: :destination,
        add_template_only_nodes: false,
        match_refiner: Toml::Merge::TableMatchRefiner.new,
      )

      resolver.resolve(result)

      expect(result.content).not_to be_empty
      expect(result.content).to include("[servers]")
      expect(result.content).to include("host = \"production.example.com\"")
      expect(result.content).to include("port = 443")
    end

    it "preserves freeze blocks from destination" do
      template_content = <<~TOML
        [server]
        host = "localhost"
      TOML

      dest_content = <<~TOML
        # freeze
        [server]
        host = "production"
      TOML

      template_analysis = Toml::Merge::FileAnalysis.new(template_content)
      dest_analysis = Toml::Merge::FileAnalysis.new(dest_content)
      result = Toml::Merge::MergeResult.new

      resolver = described_class.new(
        template_analysis,
        dest_analysis,
        preference: :destination,
        add_template_only_nodes: false,
      )

      resolver.resolve(result)

      expect(result.content).not_to be_empty
      # With a freeze decision, we should still emit the destination node's lines.
      expect(result.content).to include("[server]")
      expect(result.content).to include("host = \"production\"")
    end

    context "with preference: :destination" do
      it "preserves destination values for matching keys" do
        template_analysis = Toml::Merge::FileAnalysis.new(template_content)
        dest_analysis = Toml::Merge::FileAnalysis.new(dest_content)
        result = Toml::Merge::MergeResult.new

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :destination,
          add_template_only_nodes: false,
        )

        resolver.resolve(result)

        expect(result.content).to include("production.example.com")
        expect(result.content).to include("443")
      end

      it "preserves destination-only keys" do
        template_analysis = Toml::Merge::FileAnalysis.new(template_content)
        dest_analysis = Toml::Merge::FileAnalysis.new(dest_content)
        result = Toml::Merge::MergeResult.new

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :destination,
          add_template_only_nodes: false,
        )

        resolver.resolve(result)

        expect(result.content).to include("ssl")
      end
    end

    context "with preference: :template" do
      it "uses template values for matching keys" do
        template_analysis = Toml::Merge::FileAnalysis.new(template_content)
        dest_analysis = Toml::Merge::FileAnalysis.new(dest_content)
        result = Toml::Merge::MergeResult.new

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :template,
          add_template_only_nodes: false,
        )

        resolver.resolve(result)

        # The result should be based on template preference
        expect(result.content).not_to be_empty
      end
    end

    context "with add_template_only_nodes: true" do
      let(:template_with_extra) do
        <<~TOML
          [server]
          host = "localhost"

          [logging]
          level = "info"
        TOML
      end

      it "includes template-only sections" do
        template_analysis = Toml::Merge::FileAnalysis.new(template_with_extra)
        dest_analysis = Toml::Merge::FileAnalysis.new(dest_content)
        result = Toml::Merge::MergeResult.new

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :destination,
          add_template_only_nodes: true,
        )

        resolver.resolve(result)

        expect(result.content).to include("logging")
      end
    end

    context "with match_refiner" do
      let(:template_similar) do
        <<~TOML
          [server]
          host = "localhost"
        TOML
      end

      let(:dest_similar) do
        <<~TOML
          [servers]
          host = "production.example.com"
        TOML
      end

      it "uses refiner for fuzzy matching" do
        template_analysis = Toml::Merge::FileAnalysis.new(template_similar)
        dest_analysis = Toml::Merge::FileAnalysis.new(dest_similar)
        result = Toml::Merge::MergeResult.new
        refiner = Toml::Merge::TableMatchRefiner.new(threshold: 0.5)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :destination,
          add_template_only_nodes: false,
          match_refiner: refiner,
        )

        resolver.resolve(result)

        expect(result.content).not_to be_empty
      end
    end
  end

  describe "container merging" do
    let(:template_nested) do
      <<~TOML
        [server]
        host = "localhost"
        port = 8080

        [database]
        name = "mydb"
      TOML
    end

    let(:dest_nested) do
      <<~TOML
        [server]
        host = "prod.example.com"
        port = 443
        ssl = true

        [cache]
        enabled = true
      TOML
    end

    it "merges table contents recursively" do
      template_analysis = Toml::Merge::FileAnalysis.new(template_nested)
      dest_analysis = Toml::Merge::FileAnalysis.new(dest_nested)
      result = Toml::Merge::MergeResult.new

      resolver = described_class.new(
        template_analysis,
        dest_analysis,
        preference: :destination,
        add_template_only_nodes: true,
      )

      resolver.resolve(result)

      # Should have server section with dest values
      expect(result.content).to include("[server]")
      # Should have cache section (dest-only)
      expect(result.content).to include("[cache]")
      # Should have database section (template-only, if add_template_only_nodes)
      expect(result.content).to include("[database]")
    end
  end

  describe "template preference for leaf nodes", :toml_parsing do
    let(:template_values) do
      <<~TOML
        name = "template-name"
        version = "2.0.0"
      TOML
    end

    let(:dest_values) do
      <<~TOML
        name = "dest-name"
        version = "1.0.0"
      TOML
    end

    it "uses template values when preference is :template" do
      template_analysis = Toml::Merge::FileAnalysis.new(template_values)
      dest_analysis = Toml::Merge::FileAnalysis.new(dest_values)
      result = Toml::Merge::MergeResult.new

      resolver = described_class.new(
        template_analysis,
        dest_analysis,
        preference: :template,
        add_template_only_nodes: false,
      )

      resolver.resolve(result)

      expect(result.content).to include("template-name")
      expect(result.content).to include("2.0.0")
    end
  end

  describe "match_refiner with custom refiner", :toml_parsing do
    let(:template_with_key) do
      <<~TOML
        [old_section]
        value = "template"
      TOML
    end

    let(:dest_with_renamed) do
      <<~TOML
        [new_section]
        value = "dest"
      TOML
    end

    it "uses custom match_refiner for fuzzy matching" do
      template_analysis = Toml::Merge::FileAnalysis.new(template_with_key)
      dest_analysis = Toml::Merge::FileAnalysis.new(dest_with_renamed)
      result = Toml::Merge::MergeResult.new

      match_struct = Struct.new(:template_node, :dest_node)

      match_refiner = ->(unmatched_t, unmatched_d, _context) {
        matches = []
        unmatched_t.each do |t_node|
          next unless t_node.respond_to?(:table_name) && t_node.table_name&.include?("old_section")

          unmatched_d.each do |d_node|
            next unless d_node.respond_to?(:table_name) && d_node.table_name&.include?("new_section")

            matches << match_struct.new(t_node, d_node)
          end
        end
        matches
      }

      resolver = described_class.new(
        template_analysis,
        dest_analysis,
        preference: :destination,
        add_template_only_nodes: false,
        match_refiner: match_refiner,
      )

      resolver.resolve(result)

      expect(result.content).not_to be_empty
    end

    it "handles empty refined matches" do
      template_analysis = Toml::Merge::FileAnalysis.new(template_content)
      dest_analysis = Toml::Merge::FileAnalysis.new(dest_content)
      result = Toml::Merge::MergeResult.new

      match_refiner = ->(_t, _d, _ctx) { [] }

      resolver = described_class.new(
        template_analysis,
        dest_analysis,
        preference: :destination,
        add_template_only_nodes: false,
        match_refiner: match_refiner,
      )

      expect { resolver.resolve(result) }.not_to raise_error
    end
  end

  describe "unknown node types", :toml_parsing do
    it "handles nodes gracefully through DebugLogger" do
      template_analysis = Toml::Merge::FileAnalysis.new(template_content)
      dest_analysis = Toml::Merge::FileAnalysis.new(dest_content)
      result = Toml::Merge::MergeResult.new

      resolver = described_class.new(
        template_analysis,
        dest_analysis,
        preference: :destination,
        add_template_only_nodes: false,
      )

      # Should not raise - unknown types are logged via DebugLogger
      expect { resolver.resolve(result) }.not_to raise_error
    end
  end

  describe "private helpers" do
    subject(:resolver) do
      described_class.new(
        template_analysis,
        dest_analysis,
        preference: :destination,
        add_template_only_nodes: false,
        match_refiner: nil,
      )
    end

    let(:template_analysis) { instance_double(Toml::Merge::FileAnalysis, line_at: nil) }
    let(:dest_analysis) { instance_double(Toml::Merge::FileAnalysis, line_at: nil) }
    let(:result) { Toml::Merge::MergeResult.new }

    describe "#build_refined_matches" do
      it "returns empty hash when no match_refiner is configured" do
        matches = resolver.send(:build_refined_matches, [], [], {}, {})
        expect(matches).to eq({})
      end

      it "returns empty hash when either unmatched side is empty" do
        match_refiner = instance_double(Toml::Merge::TableMatchRefiner)
        resolver_with_refiner = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :destination,
          add_template_only_nodes: false,
          match_refiner: match_refiner,
        )

        t_node = instance_double(Toml::Merge::NodeWrapper)
        d_node = instance_double(Toml::Merge::NodeWrapper)

        # Force: template has an unmatched node; destination has none unmatched
        allow(template_analysis).to receive(:generate_signature).with(t_node).and_return([:table, "a"])
        allow(dest_analysis).to receive(:generate_signature).with(d_node).and_return([:table, "a"])

        matches = resolver_with_refiner.send(
          :build_refined_matches,
          [t_node],
          [d_node],
          {[:table, "a"] => [{node: t_node}]},
          {[:table, "a"] => [{node: d_node}]},
        )

        expect(matches).to eq({})
      end
    end
  end

  describe "dedup debug warnings" do
    it "logs when the TOML leading-comment dedup guard fires" do
      resolver = described_class.allocate
      emitter = double("emitter")
      resolver.instance_variable_set(:@emitted_leading_comment_texts, Set["duplicate"])
      resolver.instance_variable_set(:@emitter, emitter)
      resolver.instance_variable_set(:@corruption_handling, :warn)

      node = double("node")
      source_node = double("source_node", start_line: 4)
      region = double("region", normalized_content: "duplicate", start_line: 1, end_line: 2)
      analysis = double("analysis", path: "mise.toml", lines: [])

      allow(resolver).to receive(:preferred_region_with_source).and_return([region, analysis, source_node])
      allow(resolver).to receive(:emit_interstitial_blank_lines)
      allow(emitter).to receive(:emit_comment_region)
      allow(Toml::Merge::DebugLogger).to receive(:debug_warning)

      resolver.send(:emit_leading_region, node, analysis)

      expect(Toml::Merge::DebugLogger).to have_received(:debug_warning).with(
        /Suspected corruption \(comment_ownership_overlap\)/,
        hash_including(file: "mise.toml", normalized_content: "duplicate", region_lines: [1, 2]),
      )
    end

    it "raises when the TOML leading-comment dedup guard fires in error mode" do
      resolver = described_class.allocate
      resolver.instance_variable_set(:@emitted_leading_comment_texts, Set["duplicate"])
      resolver.instance_variable_set(:@emitter, double("emitter"))
      resolver.instance_variable_set(:@corruption_handling, :error)

      node = double("node")
      source_node = double("source_node", start_line: 4)
      region = double("region", normalized_content: "duplicate", start_line: 1, end_line: 2)
      analysis = double("analysis", path: "mise.toml")

      allow(resolver).to receive(:preferred_region_with_source).and_return([region, analysis, source_node])
      allow(resolver).to receive(:emit_interstitial_blank_lines)

      expect {
        resolver.send(:emit_leading_region, node, analysis)
      }.to raise_error(Toml::Merge::CorruptionDetectedError, /comment_ownership_overlap/)
    end
  end
end
