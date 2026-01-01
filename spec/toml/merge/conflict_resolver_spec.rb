# frozen_string_literal: true

RSpec.describe Toml::Merge::ConflictResolver do
  # ConflictResolver requires real FileAnalysis objects with parsed content
  # These tests document the expected interface

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

    describe "#add_node_to_result" do
      it "logs unknown node types instead of raising" do
        unknown = Object.new

        allow(Toml::Merge::DebugLogger).to receive(:debug)

        resolver.send(
          :add_node_to_result,
          unknown,
          result,
          :destination,
          Toml::Merge::MergeResult::DECISION_KEPT_DEST,
          dest_analysis,
        )

        expect(Toml::Merge::DebugLogger).to have_received(:debug).with(
          "Unknown node type",
          {node_type: "Object"},
        )
      end
    end

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

    describe "#merge_matched_nodes" do
      it "keeps destination leaf when preference is :destination" do
        # Use real NodeWrapper instances with minimal tree-sitter nodes
        # to ensure is_a? checks pass and the full add_node flow works
        template_toml = "host = \"staging\""
        dest_toml = "host = \"production\""

        template_analysis_real = Toml::Merge::FileAnalysis.new(template_toml)
        dest_analysis_real = Toml::Merge::FileAnalysis.new(dest_toml)

        template_node = template_analysis_real.statements.first
        dest_node = dest_analysis_real.statements.first

        resolver_with_real = described_class.new(
          template_analysis_real,
          dest_analysis_real,
          preference: :destination,
          add_template_only_nodes: false,
        )

        resolver_with_real.send(
          :merge_matched_nodes,
          template_node,
          dest_node,
          template_analysis_real,
          dest_analysis_real,
          result,
        )

        expect(result.content).to include("host = \"production\"")
      end

      it "keeps template leaf when preference is :template" do
        template_toml = "host = \"template\""
        dest_toml = "host = \"dest\""

        template_analysis_real = Toml::Merge::FileAnalysis.new(template_toml)
        dest_analysis_real = Toml::Merge::FileAnalysis.new(dest_toml)

        template_node = template_analysis_real.statements.first
        dest_node = dest_analysis_real.statements.first

        resolver_with_real = described_class.new(
          template_analysis_real,
          dest_analysis_real,
          preference: :template,
          add_template_only_nodes: false,
        )

        resolver_with_real.send(
          :merge_matched_nodes,
          template_node,
          dest_node,
          template_analysis_real,
          dest_analysis_real,
          result,
        )

        expect(result.content).to include("host = \"template\"")
      end
    end
  end
end
