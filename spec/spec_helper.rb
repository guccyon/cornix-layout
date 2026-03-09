# frozen_string_literal: true

require 'rspec'

# Helper methods for hierarchical layer structure
module LayerHelpers
  # Convert flat mapping to hierarchical structure
  # Accepts hierarchical paths like "left_hand.row0.LT1" or falls back to "left_hand.row0.{key}"
  # Smart detection: LT*, LH* → left_hand, RT*, RH* → right_hand, *_rotary_* → encoders
  def hierarchical_mapping(flat_mapping)
    hierarchical = {
      'left_hand' => { 'row0' => {}, 'row1' => {}, 'row2' => {}, 'row3' => {}, 'thumb_keys' => {} },
      'right_hand' => { 'row0' => {}, 'row1' => {}, 'row2' => {}, 'row3' => {}, 'thumb_keys' => {} },
      'encoders' => { 'left' => {}, 'right' => {} }
    }

    flat_mapping.each do |key, value|
      # For flat keys (like 'LT1'), infer hand from prefix
      if !key.include?('.')
        # Check for encoder keys first (before checking r_ prefix)
        if key.include?('rotary')
          if key.start_with?('l_rotary')
            action = key.sub('l_rotary_', '')
            hierarchical['encoders']['left'][action] = value
          elsif key.start_with?('r_rotary')
            action = key.sub('r_rotary_', '')
            hierarchical['encoders']['right'][action] = value
          end
        elsif key.include?('thumb')
          # Thumb keys
          if key.start_with?('l_thumb')
            hierarchical['left_hand']['thumb_keys'][key] = value
          elsif key.start_with?('r_thumb')
            hierarchical['right_hand']['thumb_keys'][key] = value
          end
        elsif key.start_with?('RT', 'RH', 'r_')
          # Right hand keys (but not r_rotary or r_thumb)
          hierarchical['right_hand']['row0'][key] = value
        else
          # Default to left_hand.row0
          hierarchical['left_hand']['row0'][key] = value
        end
      else
        # Parse hierarchical path
        parts = key.split('.')
        if parts[0] == 'left_hand' || parts[0] == 'right_hand'
          if parts[1] == 'thumb_keys'
            hierarchical[parts[0]]['thumb_keys'][parts[2]] = value
          else
            hierarchical[parts[0]][parts[1]][parts[2]] = value
          end
        elsif parts[0] == 'encoders'
          hierarchical['encoders'][parts[1]][parts[2]] = value
        end
      end
    end

    # Remove empty sections
    hierarchical.each do |section, data|
      if data.is_a?(Hash)
        data.delete_if { |_, v| v.is_a?(Hash) && v.empty? }
      end
    end
    hierarchical.delete_if { |_, v| v.is_a?(Hash) && v.empty? }

    hierarchical
  end
end

RSpec.configure do |config|
  config.include LayerHelpers

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!
  config.warnings = true

  if config.files_to_run.one?
    config.default_formatter = 'doc'
  end

  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed
end
