# frozen_string_literal: true

RSpec.describe "CONTRIBUTING template sync" do
  it "keeps kettle-test guidance unique while preserving the coverage workflow notes" do
    content = File.read(File.expand_path("../../CONTRIBUTING.md", __dir__))

    expect(content.scan("Run tests via `kettle-test`").size).to eq(1)
    expect(content).to include("### Coverage-focused workflow (recommended when improving tests)")
    expect(content).to include("After the standard `kettle-test` workflow above passes")
  end
end
