#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../lib/cornix/cli_helpers'
require_relative '../../lib/cornix/compiler'
require_relative '../../lib/cornix/validators/model_validator'

config_dir = File.expand_path('../../config', __dir__)
output_file = File.expand_path('../../layout.vil', __dir__)

# Ensure config exists
Cornix::CliHelpers.ensure_config_exists(config_dir) do
  puts "Run 'cornix decompile' first to create config files"
end

# NEW: Auto-validate before compiling
puts "🔍 Validating configuration..."
validator = Cornix::Validators::ModelValidator.new(config_dir)
unless validator.validate
  puts "\n❌ Validation failed. Fix errors before compiling."
  exit 1
end
puts "✓ Validation passed\n\n"

# Compile
puts "🔨 Compiling..."
compiler = Cornix::Compiler.new(config_dir)
compiler.compile(output_file)
puts "\n✓ Compilation completed: #{output_file}"
