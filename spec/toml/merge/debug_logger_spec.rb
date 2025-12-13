# frozen_string_literal: true

RSpec.describe Toml::Merge::DebugLogger do
  describe ".debug" do
    context "when TOML_MERGE_DEBUG is not set" do
      before do
        stub_env("TOML_MERGE_DEBUG" => nil)
      end

      it "does not output anything" do
        expect { described_class.debug("test message") }.not_to output.to_stderr
      end
    end

    context "when TOML_MERGE_DEBUG is set" do
      before do
        stub_env("TOML_MERGE_DEBUG" => "1")
      end

      it "outputs debug information to stderr" do
        expect { described_class.debug("test message") }.to output(/test message/).to_stderr
      end

      it "includes context data when provided" do
        expect {
          described_class.debug("test", {key: "value"})
        }.to output(/key.*value/).to_stderr
      end
    end
  end

  describe ".enabled?" do
    it "returns false when TOML_MERGE_DEBUG is not set" do
      stub_env("TOML_MERGE_DEBUG" => nil)
      expect(described_class.enabled?).to be false
    end

    it "returns true when TOML_MERGE_DEBUG is set" do
      stub_env("TOML_MERGE_DEBUG" => "1")
      expect(described_class.enabled?).to be true
    end
  end

  describe ".log_node" do
    context "when disabled" do
      before do
        stub_env("TOML_MERGE_DEBUG" => nil)
      end

      it "does nothing (no output)" do
        node = instance_double(Toml::Merge::NodeWrapper, type: :pair, start_line: 1, end_line: 2)
        expect { described_class.log_node(node, label: "Test") }.not_to output.to_stderr
      end
    end

    context "when enabled" do
      before do
        stub_env("TOML_MERGE_DEBUG" => "1")
      end

      it "prints info for NodeWrapper instances" do
        toml = "port = 8080"
        node = parse_toml(toml, node_type: "pair")
        expect { described_class.log_node(node, label: "Wrapper") }
          .to output(/\[Toml::Merge\].*Wrapper/).to_stderr
      end

      it "falls back to extract_node_info for other objects" do
        other = Object.new
        # Don't stub extract_node_info to ensure the else branch is actually executed
        expect { described_class.log_node(other, label: "Other") }
          .to output(/\[Toml::Merge\].*Other/).to_stderr
      end
    end
  end

  describe ".time" do
    it "yields and returns the block result without output when disabled" do
      stub_env("TOML_MERGE_DEBUG" => nil)
      val = nil
      expect { val = described_class.time("block") { 42 } }.not_to output.to_stderr
      expect(val).to eq(42)
    end

    it "yields and prints timing when enabled" do
      stub_env("TOML_MERGE_DEBUG" => "1")
      expect { described_class.time("block") { :ok } }.to output(/block/).to_stderr
    end
  end
end
