#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../lib/cornix/device/mcp_server'

# LANG が未設定でもファイルや標準入出力を UTF-8 として扱う
Encoding.default_external = Encoding::UTF_8

# stdout は MCP の JSON-RPC 専用なので、ここでは何も表示しない
Cornix::Device::McpServer.new.run
