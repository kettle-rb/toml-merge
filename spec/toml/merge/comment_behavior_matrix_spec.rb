# frozen_string_literal: true

require "spec_helper"
require "ast/merge/rspec/shared_examples"

RSpec.describe "toml comment behavior matrix" do
  extend Ast::Merge::RSpec::CommentBehaviorMatrixAdapters

  shared_examples "a TOML comment behavior matrix" do
    include_examples "Ast::Merge::CommentBehaviorMatrix" do
      hash_comment_line_based_comment_matrix_adapter(
        analysis_class: Toml::Merge::FileAnalysis,
        merger_class: Toml::Merge::SmartMerger,
        structural_owners_reader: ->(analysis) { analysis.statements.select { |statement| statement.respond_to?(:pair?) && statement.pair? } },
        owner_value_reader: ->(owner) { owner.value_node&.text },
        line_builder: lambda do |name, value, inline: nil|
          line = "#{name} = #{value}"
          inline ? "#{line} # #{inline}" : line
        end,
        capabilities: -> { backend_comment_matrix_capabilities },
      )
    end
  end

  context "with tree-sitter backend", :mri_backend, :toml_grammar do
    around do |example|
      TreeHaver.with_backend(:mri) do
        example.run
      end
    end

    let(:backend_comment_matrix_capabilities) do
      {
        floating_leading_regions: "gap-separated leading docs are not yet surfaced as floating attachment regions",
        template_only_floating_comment_additions: "template-only additions currently emit node payloads without floating leading docs",
        template_only_preamble_additions: "template-only additions currently emit node payloads without file-preamble comments",
        template_only_trailing_comment_additions: "template-only additions currently emit node payloads without trailing full-line docs",
        removed_node_floating_gap_preservation: "removed floating docs currently collapse their separating blank line",
        removed_node_preamble_gap_preservation: "removed-node preamble comments currently collapse their separating blank line",
      }
    end

    include_examples "a TOML comment behavior matrix"
  end

  context "with parslet backend", :parslet_backend do
    around do |example|
      TreeHaver.with_backend(:parslet) do
        example.run
      end
    end

    let(:backend_comment_matrix_capabilities) do
      {
        floating_leading_regions: "gap-separated leading docs are not yet surfaced as floating attachment regions",
        quoted_hash_inline_literals: "quoted TOML values with trailing inline comments are not normalized consistently on the parslet path yet",
        template_only_floating_comment_additions: "template-only additions currently emit node payloads without floating leading docs",
        template_only_preamble_additions: "template-only additions currently emit node payloads without file-preamble comments",
        template_only_trailing_comment_additions: "template-only additions currently emit node payloads without trailing full-line docs",
        removed_node_floating_gap_preservation: "removed floating docs currently collapse their separating blank line",
        removed_node_preamble_gap_preservation: "removed-node preamble comments currently collapse their separating blank line",
      }
    end

    include_examples "a TOML comment behavior matrix"
  end
end
