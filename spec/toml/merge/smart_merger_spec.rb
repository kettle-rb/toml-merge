require "spec_helper"

RSpec.describe Toml::Merge::SmartMerger, :mri_backend, :toml_grammar do
  around do |example|
	TreeHaver.with_backend(:mri) do
	  example.run
	end
  end

  describe "comment-preserving Slice 1 behavior" do
	it "preserves destination table-leading docs and document postlude during recursive table merges" do
	  template = <<~TOML
		[database]
		server = "template"
	  TOML

	  destination = <<~TOML
		# database docs
		[database] # keep inline
		server = "destination"

		# footer docs
	  TOML

	  merged = described_class.new(template, destination).merge

	  expect(merged).to eq(<<~TOML)
		# database docs
		[database] # keep inline
		server = "destination"

		# footer docs
	  TOML
	end

	it "preserves chosen-side table-leading and inline header comments under template preference" do
	  template = <<~TOML
		# template docs
		[database] # template inline
		server = "template"
	  TOML

	  destination = <<~TOML
		[database]
		server = "destination"
	  TOML

	  merged = described_class.new(template, destination, preference: :template).merge

	  expect(merged).to eq(template)
	end

	it "preserves comment-only destinations when no structural nodes are present" do
	  template = <<~TOML
		[database]
		server = "template"
	  TOML

	  destination = <<~TOML
		# only docs
		# still docs
	  TOML

	  merged = described_class.new(template, destination).merge

	  expect(merged).to eq(destination)
	end
  end

  describe "matched-node destination comment fallback" do
	it "preserves destination leading and inline comments when template-preferred key content wins" do
	  template = <<~TOML
		[database]

		title = "template"
	  TOML

	  destination = <<~TOML
		[database]

		# keep this title doc

		title = "destination" # keep this inline note
	  TOML

	  merged = described_class.new(template, destination, preference: :template).merge

	  expect(merged).to eq(<<~TOML)
		[database]

		# keep this title doc

		title = "template" # keep this inline note
	  TOML
	end

	it "keeps template inline comments when the template already owns the matched key comment" do
	  template = <<~TOML
		[database]
		title = "template" # template inline
	  TOML

	  destination = <<~TOML
		[database]
		title = "destination" # destination inline
	  TOML

	  merged = described_class.new(template, destination, preference: :template).merge

	  expect(merged).to eq(template)
	end
  end

  describe "removed-node comment preservation" do
	it "promotes destination-only key comments when removal is enabled" do
	  template = <<~TOML
		[database]
		title = "template"
	  TOML

	  destination = <<~TOML
		[database]
		title = "destination"
		# keep removed key doc
		legacy = "destination" # keep removed inline
	  TOML

	  merged = described_class.new(
		template,
		destination,
		remove_template_missing_nodes: true,
	  ).merge

	  expect(merged).to eq(<<~TOML)
		[database]
		title = "destination"
		# keep removed key doc
		# keep removed inline
	  TOML
	end

	it "preserves removed table documentation without keeping the removed table body" do
	  template = <<~TOML
		[database]
		title = "template"
	  TOML

	  destination = <<~TOML
		[database]
		title = "destination"

		# legacy table docs
		[legacy] # legacy inline
		# nested key docs
		key = "destination" # nested inline
	  TOML

	  merged = described_class.new(
		template,
		destination,
		remove_template_missing_nodes: true,
	  ).merge

	  expect(merged).to eq(<<~TOML)
		[database]
		title = "destination"

		# legacy table docs
		# legacy inline
		# nested key docs
		# nested inline
	  TOML
	end
  end

  describe "recursive and fixture parity" do
	it "preserves blank-line separators in qlty-style documents under template preference" do
	  template = <<~TOML
		# For a guide to configuration, visit https://qlty.sh/d/config
		# Or for a full reference, visit https://qlty.sh/d/qlty-toml
		config_version = "0"

		exclude_patterns = [
		  "**/vendor/**",
		  ".github/workflows/codeql-analysis.yml"
		]

		test_patterns = [
		  "**/test/**",
		  "**/spec/**",
		]

		[smells]
		mode = "comment"

		[smells.boolean_logic]
		threshold = 4
		enabled = true

		[smells.file_complexity]
		threshold = 55
		enabled = false
	  TOML

	  merged = described_class.new(
		template,
		template,
		preference: :template,
		add_template_only_nodes: true,
	  ).merge

	  expect(merged).to eq(template)
	end

	it "preserves destination docs for adjacent matched tables under template preference" do
	  template = <<~TOML
		[one]
		a = 1

		[two]
		b = 2
	  TOML

	  destination = <<~TOML
		[one]
		a = 10

		# keep second table docs
		[two] # keep second inline
		b = 20
	  TOML

	  merged = described_class.new(template, destination, preference: :template).merge

	  expect(merged).to eq(<<~TOML)
		[one]
		a = 1

		# keep second table docs
		[two] # keep second inline
		b = 2
	  TOML
	end

	it "preserves destination docs for matched arrays of tables under template preference" do
	  template = <<~TOML
		[[plugins]]
		name = "alpha"
	  TOML

	  destination = <<~TOML
		# keep plugin docs
		[[plugins]] # keep plugin inline
		name = "destination"
	  TOML

	  merged = described_class.new(template, destination, preference: :template).merge

	  expect(merged).to eq(<<~TOML)
		# keep plugin docs
		[[plugins]] # keep plugin inline
		name = "alpha"
	  TOML
	end
  end
end
