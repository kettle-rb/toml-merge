# frozen_string_literal: true

require "spec_helper"

RSpec.describe Toml::Merge::NodeTypeNormalizer do
  describe ".canonical_type" do
    # These tests only use the mapping hash - no actual parsing needed
    context "with default backend (tree_sitter)" do
      it "uses tree_sitter when no backend specified" do
        # table_array_element is mapped in tree_sitter, so this proves default is used
        expect(described_class.canonical_type(:table_array_element)).to eq(:array_of_tables)
      end

      it "normalizes table_array_element to array_of_tables" do
        expect(described_class.canonical_type(:table_array_element)).to eq(:array_of_tables)
        expect(described_class.canonical_type("table_array_element")).to eq(:array_of_tables)
      end

      it "preserves table type" do
        expect(described_class.canonical_type(:table)).to eq(:table)
      end

      it "normalizes all string types to :string" do
        expect(described_class.canonical_type(:basic_string)).to eq(:string)
        expect(described_class.canonical_type(:literal_string)).to eq(:string)
        expect(described_class.canonical_type(:multiline_basic_string)).to eq(:string)
        expect(described_class.canonical_type(:multiline_literal_string)).to eq(:string)
      end

      it "normalizes datetime types to :datetime" do
        expect(described_class.canonical_type(:offset_date_time)).to eq(:datetime)
        expect(described_class.canonical_type(:local_date_time)).to eq(:datetime)
        expect(described_class.canonical_type(:local_date)).to eq(:datetime)
        expect(described_class.canonical_type(:local_time)).to eq(:datetime)
      end

      it "preserves other types" do
        expect(described_class.canonical_type(:pair)).to eq(:pair)
        expect(described_class.canonical_type(:integer)).to eq(:integer)
        expect(described_class.canonical_type(:float)).to eq(:float)
        expect(described_class.canonical_type(:boolean)).to eq(:boolean)
        expect(described_class.canonical_type(:array)).to eq(:array)
        expect(described_class.canonical_type(:inline_table)).to eq(:inline_table)
      end

      it "passes through unknown types" do
        expect(described_class.canonical_type(:unknown_type)).to eq(:unknown_type)
      end
    end

    context "with explicit tree_sitter backend" do
      it "normalizes table_array_element to array_of_tables" do
        expect(described_class.canonical_type(:table_array_element, :tree_sitter)).to eq(:array_of_tables)
        expect(described_class.canonical_type("table_array_element", :tree_sitter)).to eq(:array_of_tables)
      end

      it "preserves table type" do
        expect(described_class.canonical_type(:table, :tree_sitter)).to eq(:table)
      end

      it "normalizes all string types to :string" do
        expect(described_class.canonical_type(:basic_string, :tree_sitter)).to eq(:string)
        expect(described_class.canonical_type(:literal_string, :tree_sitter)).to eq(:string)
        expect(described_class.canonical_type(:multiline_basic_string, :tree_sitter)).to eq(:string)
        expect(described_class.canonical_type(:multiline_literal_string, :tree_sitter)).to eq(:string)
      end

      it "normalizes datetime types to :datetime" do
        expect(described_class.canonical_type(:offset_date_time, :tree_sitter)).to eq(:datetime)
        expect(described_class.canonical_type(:local_date_time, :tree_sitter)).to eq(:datetime)
        expect(described_class.canonical_type(:local_date, :tree_sitter)).to eq(:datetime)
        expect(described_class.canonical_type(:local_time, :tree_sitter)).to eq(:datetime)
      end

      it "preserves other types" do
        expect(described_class.canonical_type(:pair, :tree_sitter)).to eq(:pair)
        expect(described_class.canonical_type(:integer, :tree_sitter)).to eq(:integer)
        expect(described_class.canonical_type(:float, :tree_sitter)).to eq(:float)
        expect(described_class.canonical_type(:boolean, :tree_sitter)).to eq(:boolean)
        expect(described_class.canonical_type(:array, :tree_sitter)).to eq(:array)
        expect(described_class.canonical_type(:inline_table, :tree_sitter)).to eq(:inline_table)
      end

      it "passes through unknown types" do
        expect(described_class.canonical_type(:unknown_type, :tree_sitter)).to eq(:unknown_type)
      end
    end

    context "with citrus backend (non-default)" do
      it "normalizes table_array to array_of_tables" do
        # Citrus produces :table_array, not :table_array_element
        expect(described_class.canonical_type(:table_array, :citrus)).to eq(:array_of_tables)
      end

      it "normalizes keyvalue to pair" do
        # Citrus produces :keyvalue, not :pair
        expect(described_class.canonical_type(:keyvalue, :citrus)).to eq(:pair)
      end

      it "preserves table type" do
        expect(described_class.canonical_type(:table, :citrus)).to eq(:table)
      end

      it "normalizes all string types to :string" do
        expect(described_class.canonical_type(:string, :citrus)).to eq(:string)
        expect(described_class.canonical_type(:basic_string, :citrus)).to eq(:string)
        expect(described_class.canonical_type(:literal_string, :citrus)).to eq(:string)
        expect(described_class.canonical_type(:multiline_string, :citrus)).to eq(:string)
        expect(described_class.canonical_type(:multiline_literal, :citrus)).to eq(:string)
      end

      it "normalizes all integer types to :integer" do
        expect(described_class.canonical_type(:integer, :citrus)).to eq(:integer)
        expect(described_class.canonical_type(:decimal_integer, :citrus)).to eq(:integer)
        expect(described_class.canonical_type(:hexadecimal_integer, :citrus)).to eq(:integer)
        expect(described_class.canonical_type(:octal_integer, :citrus)).to eq(:integer)
        expect(described_class.canonical_type(:binary_integer, :citrus)).to eq(:integer)
      end

      it "normalizes float types to :float" do
        expect(described_class.canonical_type(:float, :citrus)).to eq(:float)
        expect(described_class.canonical_type(:fractional_float, :citrus)).to eq(:float)
      end

      it "normalizes boolean types to :boolean" do
        expect(described_class.canonical_type(:boolean, :citrus)).to eq(:boolean)
        expect(described_class.canonical_type(:true, :citrus)).to eq(:boolean)
        expect(described_class.canonical_type(:false, :citrus)).to eq(:boolean)
      end

      it "normalizes datetime types to :datetime" do
        expect(described_class.canonical_type(:datetime, :citrus)).to eq(:datetime)
        expect(described_class.canonical_type(:date, :citrus)).to eq(:datetime)
        expect(described_class.canonical_type(:time, :citrus)).to eq(:datetime)
        expect(described_class.canonical_type(:local_date, :citrus)).to eq(:datetime)
        expect(described_class.canonical_type(:local_time, :citrus)).to eq(:datetime)
        expect(described_class.canonical_type(:local_datetime, :citrus)).to eq(:datetime)
        expect(described_class.canonical_type(:offset_datetime, :citrus)).to eq(:datetime)
      end

      it "preserves other types" do
        expect(described_class.canonical_type(:pair, :citrus)).to eq(:pair)
        expect(described_class.canonical_type(:array, :citrus)).to eq(:array)
        expect(described_class.canonical_type(:inline_table, :citrus)).to eq(:inline_table)
      end

      it "passes through unknown types" do
        expect(described_class.canonical_type(:unknown_type, :citrus)).to eq(:unknown_type)
      end
    end

    context "with nil input" do
      it "returns nil with default backend" do
        expect(described_class.canonical_type(nil)).to be_nil
      end

      it "returns nil with explicit tree_sitter backend" do
        expect(described_class.canonical_type(nil, :tree_sitter)).to be_nil
      end

      it "returns nil with citrus backend" do
        expect(described_class.canonical_type(nil, :citrus)).to be_nil
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

    it "accepts string input" do
      expect(described_class.table_type?("table")).to be true
      expect(described_class.table_type?("array_of_tables")).to be true
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

    it "accepts string input" do
      expect(described_class.value_type?("string")).to be true
      expect(described_class.value_type?("integer")).to be true
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

    it "accepts string input" do
      expect(described_class.key_type?("bare_key")).to be true
      expect(described_class.key_type?("quoted_key")).to be true
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

    it "accepts string input" do
      expect(described_class.container_type?("document")).to be true
      expect(described_class.container_type?("table")).to be true
    end
  end

  describe ".registered_backends" do
    it "includes tree_sitter and citrus" do
      expect(described_class.registered_backends).to include(:tree_sitter)
      expect(described_class.registered_backends).to include(:citrus)
    end
  end

  describe ".backend_registered?" do
    it "returns true for registered backends" do
      expect(described_class.backend_registered?(:tree_sitter)).to be true
      expect(described_class.backend_registered?(:citrus)).to be true
    end

    it "returns false for unregistered backends" do
      expect(described_class.backend_registered?(:unknown_backend)).to be false
    end

    it "accepts string input" do
      expect(described_class.backend_registered?("tree_sitter")).to be true
      expect(described_class.backend_registered?("citrus")).to be true
    end
  end

  describe ".register_backend" do
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
    it "returns mappings for tree_sitter backend" do
      mappings = described_class.mappings_for(:tree_sitter)
      expect(mappings).to be_a(Hash)
      expect(mappings[:table_array_element]).to eq(:array_of_tables)
      expect(mappings[:basic_string]).to eq(:string)
      expect(mappings[:local_date]).to eq(:datetime)
    end

    it "returns mappings for citrus backend" do
      mappings = described_class.mappings_for(:citrus)
      expect(mappings).to be_a(Hash)
      # Citrus uses :table_array, not :table_array_element
      expect(mappings[:table_array]).to eq(:array_of_tables)
      # Citrus uses :keyvalue, not :pair
      expect(mappings[:keyvalue]).to eq(:pair)
      expect(mappings[:date]).to eq(:datetime)
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

  describe ".wrap" do
    # Tests with mock nodes don't need any tags - pure Ruby logic
    let(:mock_node) { double("Node", type: :table_array_element) }

    context "with default backend" do
      it "wraps a node with canonical merge_type using default backend" do
        wrapped = described_class.wrap(mock_node)

        expect(wrapped).to respond_to(:merge_type)
        expect(wrapped.merge_type).to eq(:array_of_tables)
        expect(wrapped).to respond_to(:unwrap)
        expect(wrapped.unwrap).to eq(mock_node)
      end
    end

    context "with explicit tree_sitter backend" do
      it "wraps a node with canonical merge_type" do
        wrapped = described_class.wrap(mock_node, :tree_sitter)

        expect(wrapped.merge_type).to eq(:array_of_tables)
      end
    end

    context "with citrus backend" do
      # Citrus uses :table_array, not :table_array_element
      let(:citrus_node) { double("CitrusNode", type: :table_array) }

      it "wraps a node with canonical merge_type using citrus backend" do
        wrapped = described_class.wrap(citrus_node, :citrus)

        expect(wrapped.merge_type).to eq(:array_of_tables)
        expect(wrapped.unwrap).to eq(citrus_node)
      end

      it "handles citrus-specific keyvalue type" do
        keyvalue_node = double("KeyvalueNode", type: :keyvalue)
        wrapped = described_class.wrap(keyvalue_node, :citrus)

        expect(wrapped.merge_type).to eq(:pair)
      end

      it "handles citrus-specific datetime type" do
        date_node = double("DateNode", type: :date)
        wrapped = described_class.wrap(date_node, :citrus)

        expect(wrapped.merge_type).to eq(:datetime)
      end
    end

    # This test requires actual TOML parsing - use :toml_parsing tag
    context "with real parsed nodes", :toml_parsing do
      let(:toml_source) { "[[servers]]\nname = \"alpha\"" }
      let(:analysis) { Toml::Merge::FileAnalysis.new(toml_source) }

      it "wraps a parsed node with canonical merge_type" do
        tables = analysis.tables
        skip "No tables parsed (parser may not support array of tables)" if tables.empty?

        table_node = tables.first.node
        # Pass the backend from analysis to get correct type mapping
        wrapped = described_class.wrap(table_node, analysis.backend)

        expect(wrapped).to respond_to(:merge_type)
        expect(wrapped.merge_type).to eq(:array_of_tables)
      end
    end
  end
end
