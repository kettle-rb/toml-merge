# frozen_string_literal: true

RSpec.describe Toml::Merge::NodeTypeNormalizer do
  describe ".canonical_type" do
    context "with tree-sitter-toml types" do
      it "normalizes table_array_element to array_of_tables" do
        expect(described_class.canonical_type(:table_array_element, :tree_sitter_toml)).to eq(:array_of_tables)
        expect(described_class.canonical_type("table_array_element", :tree_sitter_toml)).to eq(:array_of_tables)
      end

      it "preserves table type" do
        expect(described_class.canonical_type(:table, :tree_sitter_toml)).to eq(:table)
      end

      it "normalizes all string types to :string" do
        expect(described_class.canonical_type(:basic_string, :tree_sitter_toml)).to eq(:string)
        expect(described_class.canonical_type(:literal_string, :tree_sitter_toml)).to eq(:string)
        expect(described_class.canonical_type(:multiline_basic_string, :tree_sitter_toml)).to eq(:string)
        expect(described_class.canonical_type(:multiline_literal_string, :tree_sitter_toml)).to eq(:string)
      end

      it "normalizes datetime types to :datetime" do
        expect(described_class.canonical_type(:offset_date_time, :tree_sitter_toml)).to eq(:datetime)
        expect(described_class.canonical_type(:local_date_time, :tree_sitter_toml)).to eq(:datetime)
        expect(described_class.canonical_type(:local_date, :tree_sitter_toml)).to eq(:datetime)
        expect(described_class.canonical_type(:local_time, :tree_sitter_toml)).to eq(:datetime)
      end

      it "preserves other types" do
        expect(described_class.canonical_type(:pair, :tree_sitter_toml)).to eq(:pair)
        expect(described_class.canonical_type(:integer, :tree_sitter_toml)).to eq(:integer)
        expect(described_class.canonical_type(:float, :tree_sitter_toml)).to eq(:float)
        expect(described_class.canonical_type(:boolean, :tree_sitter_toml)).to eq(:boolean)
        expect(described_class.canonical_type(:array, :tree_sitter_toml)).to eq(:array)
        expect(described_class.canonical_type(:inline_table, :tree_sitter_toml)).to eq(:inline_table)
      end

      it "passes through unknown types" do
        expect(described_class.canonical_type(:unknown_type, :tree_sitter_toml)).to eq(:unknown_type)
      end
    end

    context "with citrus_toml types" do
      it "normalizes table_array_element to array_of_tables" do
        expect(described_class.canonical_type(:table_array_element, :citrus_toml)).to eq(:array_of_tables)
      end

      it "preserves common types" do
        expect(described_class.canonical_type(:table, :citrus_toml)).to eq(:table)
        expect(described_class.canonical_type(:pair, :citrus_toml)).to eq(:pair)
        expect(described_class.canonical_type(:string, :citrus_toml)).to eq(:string)
        expect(described_class.canonical_type(:integer, :citrus_toml)).to eq(:integer)
      end
    end

    context "with nil input" do
      it "returns nil" do
        expect(described_class.canonical_type(nil)).to be_nil
      end
    end

    context "with default backend" do
      it "uses tree_sitter_toml as default" do
        expect(described_class.canonical_type(:table_array_element)).to eq(:array_of_tables)
      end
    end
  end

  describe ".table_type?" do
    it "returns true for table types" do
      expect(described_class.table_type?(:table)).to be true
      expect(described_class.table_type?(:array_of_tables)).to be true
    end

    it "returns false for non-table types" do
      expect(described_class.table_type?(:pair)).to be false
      expect(described_class.table_type?(:string)).to be false
      expect(described_class.table_type?(:document)).to be false
    end
  end

  describe ".value_type?" do
    it "returns true for value types" do
      expect(described_class.value_type?(:string)).to be true
      expect(described_class.value_type?(:integer)).to be true
      expect(described_class.value_type?(:float)).to be true
      expect(described_class.value_type?(:boolean)).to be true
      expect(described_class.value_type?(:array)).to be true
      expect(described_class.value_type?(:inline_table)).to be true
      expect(described_class.value_type?(:datetime)).to be true
    end

    it "returns false for non-value types" do
      expect(described_class.value_type?(:table)).to be false
      expect(described_class.value_type?(:pair)).to be false
      expect(described_class.value_type?(:document)).to be false
    end
  end

  describe ".key_type?" do
    it "returns true for key types" do
      expect(described_class.key_type?(:bare_key)).to be true
      expect(described_class.key_type?(:quoted_key)).to be true
      expect(described_class.key_type?(:dotted_key)).to be true
    end

    it "returns false for non-key types" do
      expect(described_class.key_type?(:pair)).to be false
      expect(described_class.key_type?(:string)).to be false
    end
  end

  describe ".container_type?" do
    it "returns true for container types" do
      expect(described_class.container_type?(:document)).to be true
      expect(described_class.container_type?(:table)).to be true
      expect(described_class.container_type?(:array_of_tables)).to be true
      expect(described_class.container_type?(:array)).to be true
      expect(described_class.container_type?(:inline_table)).to be true
    end

    it "returns false for non-container types" do
      expect(described_class.container_type?(:pair)).to be false
      expect(described_class.container_type?(:string)).to be false
      expect(described_class.container_type?(:integer)).to be false
    end
  end

  describe ".registered_backends" do
    it "includes tree_sitter_toml and citrus_toml" do
      expect(described_class.registered_backends).to include(:tree_sitter_toml)
      expect(described_class.registered_backends).to include(:citrus_toml)
    end
  end

  describe ".backend_registered?" do
    it "returns true for registered backends" do
      expect(described_class.backend_registered?(:tree_sitter_toml)).to be true
      expect(described_class.backend_registered?(:citrus_toml)).to be true
    end

    it "returns false for unregistered backends" do
      expect(described_class.backend_registered?(:unknown_backend)).to be false
    end
  end

  describe ".register_backend" do
    after do
      # Clean up the test backend registration
      # Note: In real code, you might want a way to unregister backends
    end

    it "allows registering new backends" do
      described_class.register_backend(:test_backend, {
        my_table: :table,
        my_pair: :pair,
      })

      expect(described_class.backend_registered?(:test_backend)).to be true
      expect(described_class.canonical_type(:my_table, :test_backend)).to eq(:table)
      expect(described_class.canonical_type(:my_pair, :test_backend)).to eq(:pair)
    end
  end

  describe ".mappings_for" do
    it "returns mappings for registered backends" do
      mappings = described_class.mappings_for(:tree_sitter_toml)
      expect(mappings).to be_a(Hash)
      expect(mappings[:table_array_element]).to eq(:array_of_tables)
    end

    it "returns nil for unregistered backends" do
      expect(described_class.mappings_for(:unknown_backend)).to be_nil
    end
  end

  describe ".canonical_types" do
    it "returns all unique canonical types" do
      types = described_class.canonical_types
      expect(types).to include(:document)
      expect(types).to include(:table)
      expect(types).to include(:array_of_tables)
      expect(types).to include(:pair)
      expect(types).to include(:string)
      expect(types).to include(:integer)
      expect(types).to include(:float)
      expect(types).to include(:boolean)
      expect(types).to include(:array)
      expect(types).to include(:inline_table)
      expect(types).to include(:datetime)
      expect(types).to include(:comment)
    end
  end

  describe ".wrap", :toml_backend do
    let(:toml_source) { "[[servers]]\nname = \"alpha\"" }
    let(:analysis) { Toml::Merge::FileAnalysis.new(toml_source) }

    it "wraps a node with canonical merge_type" do
      # Get a table_array_element node
      tables = analysis.tables
      next if tables.empty?

      table_node = tables.first.node
      wrapped = described_class.wrap(table_node)

      expect(wrapped).to respond_to(:merge_type)
      expect(wrapped.merge_type).to eq(:array_of_tables)
      expect(wrapped).to respond_to(:unwrap)
    end
  end
end

