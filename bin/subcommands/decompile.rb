#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'digest'
require_relative '../../lib/cornix/cli_helpers'
require_relative '../../lib/cornix/decompiler'

# Parse arguments (ARGV has already had the command removed by bin/cornix)
vil_file = ARGV[0] || File.expand_path('../../tmp/layout.vil', __dir__)
output_dir = File.expand_path('../../config', __dir__)

# Validate input file
unless File.exist?(vil_file)
  puts "Error: #{vil_file} not found"
  exit 1
end

# Check for existing config protection
Cornix::CliHelpers.check_config_lock(output_dir)

# Decompile
puts "Decompiling: #{vil_file}"
puts "Output to: #{output_dir}"
puts ""

decompiler = Cornix::Decompiler.new(vil_file)
decompiler.decompile(output_dir)

# Create lock file
lock_file = "#{output_dir}/.decompile.lock"
File.write(lock_file, {
  'decompiled_at' => Time.now.to_s,
  'source_file' => vil_file,
  'checksum' => Digest::SHA256.file(vil_file).hexdigest
}.to_yaml)

puts "\n✓ Decompilation completed: #{output_dir}"
puts "✓ Lock file created: #{lock_file}"
