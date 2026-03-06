#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../lib/cornix/cli_helpers'

# Parse force flag (ARGV has already had the command removed by bin/cornix)
force = ARGV[0] == '-f' || ARGV[0] == '--force'

# Delegate to helper
Cornix::CliHelpers.cleanup(force)
