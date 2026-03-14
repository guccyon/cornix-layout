#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../lib/cornix/cli_helpers'
require_relative '../../lib/cornix/model_validator'

config_dir = File.expand_path('../../config', __dir__)

# Ensure config exists
Cornix::CliHelpers.ensure_config_exists(config_dir)

# Validate
validator = Cornix::ModelValidator.new(config_dir)
success = validator.validate(mode: :collect)
exit(success ? 0 : 1)
