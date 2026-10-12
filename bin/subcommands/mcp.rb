#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../lib/cornix/device/mcp_server'

# stdout は MCP の JSON-RPC 専用なので、ここでは何も表示しない
Cornix::Device::McpServer.new.run
