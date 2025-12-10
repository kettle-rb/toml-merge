# frozen_string_literal: true

RSpec.describe Toml::Merge::DebugLogger do
  describe ".debug" do
    context "when TOML_MERGE_DEBUG is not set" do
      before do
        allow(ENV).to receive(:[]).with("TOML_MERGE_DEBUG").and_return(nil)
      end

      it "does not output anything" do
        expect { described_class.debug("test message") }.not_to output.to_stderr
      end
    end

    context "when TOML_MERGE_DEBUG is set" do
      before do
        allow(ENV).to receive(:[]).with("TOML_MERGE_DEBUG").and_return("1")
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
      allow(ENV).to receive(:[]).with("TOML_MERGE_DEBUG").and_return(nil)
      expect(described_class.enabled?).to be false
    end

    it "returns true when TOML_MERGE_DEBUG is set" do
      allow(ENV).to receive(:[]).with("TOML_MERGE_DEBUG").and_return("1")
      expect(described_class.enabled?).to be true
    end
  end
end
