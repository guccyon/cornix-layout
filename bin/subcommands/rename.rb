#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../lib/cornix/cli_helpers'
require_relative '../../lib/cornix/rename_command'

config_dir = File.expand_path('../../config', __dir__)

# Ensure config exists
Cornix::CliHelpers.ensure_config_exists(config_dir) do
  puts "Run 'cornix decompile' first to create config files"
end

# Execute rename command
rename_command = Cornix::RenameCommand.new(config_dir)
rename_command.execute
