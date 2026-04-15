require "spec_helper"
require "ast/merge/rspec/shared_examples"

RSpec.describe Toml::Merge::SmartMerger, :mri_backend, :toml_grammar do
  around do |example|
    TreeHaver.with_backend(:mri) do
      example.run
    end
  end

  describe "#merge_with_debug" do
    let(:runtime_debug_merger) do
      described_class.new(
        <<~TOML,
          [database]
          server = "template"
        TOML
        <<~TOML
          [database]
          server = "destination"
        TOML
      )
    end

    it_behaves_like "Ast::Merge::RuntimeDebugContract"

    it "returns runtime-aware debug information" do
      debug_result = runtime_debug_merger.merge_with_debug

      expect(debug_result).to include(
        :content,
        :debug,
        :runtime,
        :statistics,
        :decisions,
        :template_analysis,
        :dest_analysis,
      )
      expect(debug_result.dig(:debug, :backend)).to eq(runtime_debug_merger.backend)
      expect(debug_result.dig(:runtime, :summary, :operation_count)).to eq(1)
      expect(debug_result.dig(:runtime, :operation_trees, 0, :surface, :surface_kind)).to eq(:toml_document)
      expect(debug_result.dig(:runtime, :operation_trees, 0, :delegate_name)).to eq("toml-runtime")
    end

    it "memoizes merge_result and exposes sort_keys in debug output" do
      merger = described_class.new(
        <<~TOML,
          [database]
          zebra = "template"
          alpha = "template"
        TOML
        <<~TOML,
          [database]
          zebra = "destination"
          alpha = "destination"
        TOML
        sort_keys: true,
      )

      first_result = merger.merge_result
      second_result = merger.merge_result
      debug_result = merger.merge_with_debug
      alpha_index = debug_result[:content].lines.index { |line| line.include?('alpha = "destination"') }
      zebra_index = debug_result[:content].lines.index { |line| line.include?('zebra = "destination"') }

      expect(second_result).to be(first_result)
      expect(debug_result.dig(:debug, :sort_keys)).to be(true)
      expect(alpha_index).to be < zebra_index
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

    it "preserves owned inline separator spacing and trailing spaces when template-preferred key content wins" do
      template = <<~TOML
        [database]

        title = "template"
      TOML

      destination = <<~TOML
        [database]

        title = "destination"   # keep this inline note  
      TOML

      merged = described_class.new(template, destination, preference: :template).merge
      merged_line = merged.lines.find { |line| line.include?('title = "template"') }

      expect(merged_line).to eq("title = \"template\"   # keep this inline note  \n")
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

    it "preserves a floating comment block with a single owned gap when its destination owner is removed" do
      template = <<~TOML
        [server]
        host = "localhost"
        port = 8080
      TOML

      destination = <<~TOML
        [server]
        host = "localhost"

        # NOTE: Development-only settings below.
        debug = false

        port = 8080
      TOML

      merged = described_class.new(
        template,
        destination,
        preference: :destination,
        add_template_only_nodes: true,
        remove_template_missing_nodes: true,
      ).merge

      expect(merged).to eq(<<~TOML)
        [server]
        host = "localhost"

        # NOTE: Development-only settings below.

        port = 8080
      TOML
    end
  end

  describe "multi-byte character (emoji) handling" do
    it "does not duplicate keys when destination contains emoji values" do
      template = <<~TOML
        [env]
        A = "1"
      TOML

      destination = <<~TOML
        [env]
        EMOJI = "🪙"
        A = "1"
      TOML

      merged = described_class.new(
        template,
        destination,
        preference: :destination,
        add_template_only_nodes: true,
      ).merge

      lines = merged.lines.select { |l| l.strip.start_with?("A") }
      expect(lines.size).to eq(1), "Expected A to appear once but got #{lines.size}: #{lines.inspect}"
    end

    it "does not duplicate keys when destination has multiple emoji values" do
      template = <<~TOML
        [env]
        X = "hello"
        Y = "world"
      TOML

      destination = <<~TOML
        [env]
        E1 = "🍲"
        E2 = "🪙"
        X = "hello"
        Y = "world"
      TOML

      merged = described_class.new(
        template,
        destination,
        preference: :destination,
        add_template_only_nodes: true,
      ).merge

      x_lines = merged.lines.select { |l| l.strip.start_with?("X") }
      y_lines = merged.lines.select { |l| l.strip.start_with?("Y") }
      expect(x_lines.size).to eq(1), "Expected X once, got #{x_lines.size}"
      expect(y_lines.size).to eq(1), "Expected Y once, got #{y_lines.size}"
    end

    it "preserves emoji values in destination" do
      template = <<~TOML
        [env]
        NAME = "default"
      TOML

      destination = <<~TOML
        [env]
        NAME = "🪙 Token::Resolver"
      TOML

      merged = described_class.new(
        template,
        destination,
        preference: :destination,
        add_template_only_nodes: true,
      ).merge

      expect(merged).to include('NAME = "🪙 Token::Resolver"')
    end

    it "handles CJK characters without duplicating keys" do
      template = <<~TOML
        [env]
        LANG = "en"
      TOML

      destination = <<~TOML
        [env]
        GREETING = "こんにちは"
        LANG = "ja"
      TOML

      merged = described_class.new(
        template,
        destination,
        preference: :destination,
        add_template_only_nodes: true,
      ).merge

      lang_lines = merged.lines.select { |l| l.strip.start_with?("LANG") }
      expect(lang_lines.size).to eq(1), "Expected LANG once, got #{lang_lines.size}"
      expect(merged).to include('LANG = "ja"')
      expect(merged).to include('GREETING = "こんにちは"')
    end
  end

  describe "sort_keys option" do
    it "sorts key=value pairs alphabetically within a table" do
      template = <<~TOML
        [env]
        ZEBRA = "z"
        ALPHA = "a"
        MIDDLE = "m"
      TOML

      destination = <<~TOML
        [env]
        ZEBRA = "z"
        ALPHA = "a"
        MIDDLE = "m"
      TOML

      merged = described_class.new(template, destination, sort_keys: true).merge

      keys = merged.lines.select { |l| l.match?(/\A\w+\s*=/) }.map { |l| l.split("=").first.strip }
      expect(keys).to eq(%w[ALPHA MIDDLE ZEBRA])
    end

    it "preserves gap-separated blocks independently" do
      template = <<~TOML
        [env]
        Z_FIRST_GROUP = "1"
        A_FIRST_GROUP = "2"

        Z_SECOND_GROUP = "3"
        A_SECOND_GROUP = "4"
      TOML

      destination = <<~TOML
        [env]
        Z_FIRST_GROUP = "1"
        A_FIRST_GROUP = "2"

        Z_SECOND_GROUP = "3"
        A_SECOND_GROUP = "4"
      TOML

      merged = described_class.new(template, destination, sort_keys: true).merge

      lines = merged.lines.map(&:rstrip)
      first_idx = lines.index { |l| l.include?("A_FIRST_GROUP") }
      second_idx = lines.index { |l| l.include?("Z_FIRST_GROUP") }
      gap_idx = lines.index(&:empty?)

      # Within first block: A before Z
      expect(first_idx).to be < second_idx
      # Gap separates blocks
      expect(second_idx).to be < gap_idx

      # Within second block: A before Z
      a2_idx = lines.index { |l| l.include?("A_SECOND_GROUP") }
      z2_idx = lines.index { |l| l.include?("Z_SECOND_GROUP") }
      expect(a2_idx).to be < z2_idx
    end

    it "keeps leading comments attached to their key during sort" do
      template = <<~TOML
        [env]
        # Zebra comment
        ZEBRA = "z"
        # Alpha comment
        ALPHA = "a"
      TOML

      destination = <<~TOML
        [env]
        # Zebra comment
        ZEBRA = "z"
        # Alpha comment
        ALPHA = "a"
      TOML

      merged = described_class.new(template, destination, sort_keys: true).merge

      lines = merged.lines.map(&:rstrip)
      alpha_comment_idx = lines.index { |l| l.include?("Alpha comment") }
      alpha_key_idx = lines.index { |l| l.include?("ALPHA") && l.include?("=") }
      zebra_comment_idx = lines.index { |l| l.include?("Zebra comment") }
      zebra_key_idx = lines.index { |l| l.include?("ZEBRA") && l.include?("=") }

      # Alpha before Zebra
      expect(alpha_key_idx).to be < zebra_key_idx
      # Each comment directly precedes its key
      expect(alpha_comment_idx).to eq(alpha_key_idx - 1)
      expect(zebra_comment_idx).to eq(zebra_key_idx - 1)
    end

    it "inserts destination-only keys alphabetically" do
      template = <<~TOML
        [env]
        ALPHA = "a"
        ZEBRA = "z"
      TOML

      destination = <<~TOML
        [env]
        ALPHA = "a"
        MIDDLE = "m"
        ZEBRA = "z"
      TOML

      merged = described_class.new(
        template,
        destination,
        sort_keys: true,
        add_template_only_nodes: true,
      ).merge

      keys = merged.lines.select { |l| l.match?(/\A\w+\s*=/) }.map { |l| l.split("=").first.strip }
      expect(keys).to eq(%w[ALPHA MIDDLE ZEBRA])
    end

    it "inserts template-only keys alphabetically" do
      template = <<~TOML
        [env]
        ALPHA = "a"
        MIDDLE = "m"
        ZEBRA = "z"
      TOML

      destination = <<~TOML
        [env]
        ALPHA = "a"
        ZEBRA = "z"
      TOML

      merged = described_class.new(
        template,
        destination,
        sort_keys: true,
        add_template_only_nodes: true,
      ).merge

      keys = merged.lines.select { |l| l.match?(/\A\w+\s*=/) }.map { |l| l.split("=").first.strip }
      expect(keys).to eq(%w[ALPHA MIDDLE ZEBRA])
    end

    it "handles dotted keys (_.path etc.) in sort" do
      template = <<~TOML
        [env]
        ZEBRA = "z"
        ALPHA = "a"
        _.path = ["exe", "bin"]
        _.file = { path = ".env.local", redact = true }
      TOML

      destination = <<~TOML
        [env]
        ZEBRA = "z"
        ALPHA = "a"
        _.path = ["exe", "bin"]
        _.file = { path = ".env.local", redact = true }
      TOML

      merged = described_class.new(template, destination, sort_keys: true).merge

      keys = merged.lines.select { |l| l.match?(/\A[_\w]+.*\s*=/) }.map { |l| l.split("=").first.strip }
      expect(keys).to eq(%w[ALPHA ZEBRA _.file _.path])
    end

    it "does not sort when sort_keys is false (default)" do
      template = <<~TOML
        [env]
        ZEBRA = "z"
        ALPHA = "a"
      TOML

      destination = <<~TOML
        [env]
        ZEBRA = "z"
        ALPHA = "a"
      TOML

      merged = described_class.new(template, destination).merge

      keys = merged.lines.select { |l| l.match?(/\A\w+\s*=/) }.map { |l| l.split("=").first.strip }
      expect(keys).to eq(%w[ZEBRA ALPHA])
    end

    it "handles trailing comment owned by preceding key" do
      template = <<~TOML
        [env]
        ZEBRA = "z"
        # trailing comment for zebra
        ALPHA = "a"
      TOML

      destination = <<~TOML
        [env]
        ZEBRA = "z"
        # trailing comment for zebra
        ALPHA = "a"
      TOML

      # When ALPHA sorts before ZEBRA, the comment between them
      # should stay with ZEBRA (as a trailing comment when there's
      # no following key it's leading for, but here ALPHA follows
      # so the comment is leading for ALPHA)
      merged = described_class.new(template, destination, sort_keys: true).merge
      keys = merged.lines.select { |l| l.match?(/\A\w+\s*=/) }.map { |l| l.split("=").first.strip }
      expect(keys).to eq(%w[ALPHA ZEBRA])
    end

    it "preserves table headers and only sorts pairs within tables" do
      template = <<~TOML
        # preamble comment
        [env]
        ZEBRA = "z"
        ALPHA = "a"

        [other]
        Y = "y"
        X = "x"
      TOML

      destination = <<~TOML
        # preamble comment
        [env]
        ZEBRA = "z"
        ALPHA = "a"

        [other]
        Y = "y"
        X = "x"
      TOML

      merged = described_class.new(template, destination, sort_keys: true).merge

      lines = merged.lines.map(&:rstrip)
      env_idx = lines.index("[env]")
      other_idx = lines.index("[other]")

      # Within [env]: A before Z
      env_keys = lines[env_idx..other_idx].select { |l| l.match?(/\A\w+\s*=/) }.map { |l| l.split("=").first.strip }
      expect(env_keys).to eq(%w[ALPHA ZEBRA])

      # Within [other]: X before Y
      other_keys = lines[other_idx..].select { |l| l.match?(/\A\w+\s*=/) }.map { |l| l.split("=").first.strip }
      expect(other_keys).to eq(%w[X Y])
    end
  end
end
