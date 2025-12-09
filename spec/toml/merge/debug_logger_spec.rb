# frozen_string_literal: true

RSpec.describe Toml::Merge::DebugLogger do
  describe ".debug" do
    context "when DEBUG_TOML_MERGE is not set" do
      before do
        allow(ENV).to receive(:fetch).with("DEBUG_TOML_MERGE", nil).and_return(nil)
      end

      it "does not output anything" do
        expect { described_class.debug("test message") }.not_to output.to_stderr
      end
    end

    context "when DEBUG_TOML_MERGE is set" do
      before do
        allow(ENV).to receive(:fetch).with("DEBUG_TOML_MERGE", nil).and_return("1")
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
    it "returns false when DEBUG_TOML_MERGE is not set" do
      allow(ENV).to receive(:fetch).with("DEBUG_TOML_MERGE", nil).and_return(nil)
      expect(described_class.enabled?).to be false
    end

    it "returns true when DEBUG_TOML_MERGE is set" do
      allow(ENV).to receive(:fetch).with("DEBUG_TOML_MERGE", nil).and_return("1")
      expect(described_class.enabled?).to be true
    end
  end
end
