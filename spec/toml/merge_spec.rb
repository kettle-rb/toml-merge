# frozen_string_literal: true

RSpec.describe Toml::Merge do
  it "has a version number" do
    expect(Toml::Merge::VERSION).not_to be_nil
  end

  describe "error classes" do
    it "defines Error inheriting from Ast::Merge::Error" do
      expect(Toml::Merge::Error.ancestors).to include(Ast::Merge::Error)
    end

    it "defines ParseError inheriting from Ast::Merge::ParseError" do
      expect(Toml::Merge::ParseError.ancestors).to include(Ast::Merge::ParseError)
    end

    it "defines TemplateParseError inheriting from ParseError" do
      expect(Toml::Merge::TemplateParseError.ancestors).to include(Toml::Merge::ParseError)
    end

    it "defines DestinationParseError inheriting from ParseError" do
      expect(Toml::Merge::DestinationParseError.ancestors).to include(Toml::Merge::ParseError)
    end
  end

  describe "ParseError" do
    it "can be instantiated without arguments" do
      error = Toml::Merge::ParseError.new
      expect(error).to be_a(Toml::Merge::ParseError)
    end

    it "can be instantiated with message only" do
      error = Toml::Merge::ParseError.new("Test error")
      expect(error.message).to eq("Test error")
    end

    it "can be instantiated with keyword arguments" do
      error = Toml::Merge::ParseError.new(content: "bad toml", errors: ["error1"])
      expect(error.content).to eq("bad toml")
      expect(error.errors).to eq(["error1"])
    end

    it "can be instantiated with all arguments" do
      error = Toml::Merge::ParseError.new("Error message", content: "bad", errors: ["e1"])
      expect(error.message).to eq("Error message")
      expect(error.content).to eq("bad")
      expect(error.errors).to eq(["e1"])
    end
  end

  describe "autoloaded classes" do
    it "autoloads DebugLogger" do
      expect(Toml::Merge::DebugLogger).to be_a(Module)
    end

    it "autoloads FileAnalysis" do
      expect(Toml::Merge::FileAnalysis).to be_a(Class)
    end

    it "autoloads MergeResult" do
      expect(Toml::Merge::MergeResult).to be_a(Class)
    end

    it "autoloads NodeWrapper" do
      expect(Toml::Merge::NodeWrapper).to be_a(Class)
    end

    it "autoloads ConflictResolver" do
      expect(Toml::Merge::ConflictResolver).to be_a(Class)
    end

    it "autoloads SmartMerger" do
      expect(Toml::Merge::SmartMerger).to be_a(Class)
    end

    it "autoloads TableMatchRefiner" do
      expect(Toml::Merge::TableMatchRefiner).to be_a(Class)
    end
  end
end
