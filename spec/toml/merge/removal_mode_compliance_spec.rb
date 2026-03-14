# frozen_string_literal: true

require "spec_helper"
require "toml/merge"
require "ast/merge/rspec/shared_examples"

RSpec.describe Toml::Merge::SmartMerger, :mri_backend, :toml_grammar do
  around do |example|
    TreeHaver.with_backend(:mri) do
      example.run
    end
  end

  it_behaves_like "Ast::Merge::RemovalModeCompliance" do
    let(:merger_class) { described_class }

    let(:removal_mode_leading_comments_case) do
      {
        template: <<~TOML,
          [database]
          title = "template"
          tail = "keep"
        TOML
        destination: <<~TOML,
          [database]
          title = "destination"
          # keep removed key doc
          legacy = "destination"
          tail = "keep"
        TOML
        expected: <<~TOML,
          [database]
          title = "destination"
          # keep removed key doc
          tail = "keep"
        TOML
      }
    end

    let(:removal_mode_inline_comments_case) do
      {
        template: <<~TOML,
          [database]
          title = "template"
          tail = "keep"
        TOML
        destination: <<~TOML,
          [database]
          title = "destination"
          legacy = "destination" # keep removed inline
          tail = "keep"
        TOML
        expected: <<~TOML,
          [database]
          title = "destination"
          # keep removed inline
          tail = "keep"
        TOML
      }
    end

    let(:removal_mode_separator_blank_line_case) do
      {
        template: <<~TOML,
          [database]
          title = "template"
          tail = "keep"
        TOML
        destination: <<~TOML,
          [database]
          title = "destination"
          # keep removed key doc
          legacy = "destination" # keep removed inline

          # trailing note
          tail = "keep"
        TOML
        expected: <<~TOML,
          [database]
          title = "destination"
          # keep removed key doc
          # keep removed inline

          # trailing note
          tail = "keep"
        TOML
      }
    end

    let(:removal_mode_recursive_case) do
      {
        template: <<~TOML,
          [database]
          title = "template"
        TOML
        destination: <<~TOML,
          [database]
          title = "destination"

          # legacy table docs
          [legacy] # legacy inline
          # nested key docs
          key = "destination" # nested inline
        TOML
        expected: <<~TOML,
          [database]
          title = "destination"

          # legacy table docs
          # legacy inline
          # nested key docs
          # nested inline
        TOML
      }
    end
  end
end
