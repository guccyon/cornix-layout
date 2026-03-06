#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../lib/cornix/cli_helpers'
require_relative '../../lib/cornix/validator'

config_dir = File.expand_path('../../config', __dir__)

# Ensure config exists
Cornix::CliHelpers.ensure_config_exists(config_dir)

# Validate
validator = Cornix::Validator.new(config_dir)
success = validator.validate
exit(success ? 0 : 1)
