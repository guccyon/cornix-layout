# frozen_string_literal: true

module Cornix
  module Interface
    module EditorServer
      # JSON-RPC のエラーの code（protocol.md の 9.）。独自の code は LSP が使う範囲と重ならない -32050 台・-32060 台
      module ErrorCodes
        PARSE_ERROR = -32_700
        INVALID_REQUEST = -32_600
        METHOD_NOT_FOUND = -32_601
        INVALID_PARAMS = -32_602
        INTERNAL_ERROR = -32_603
        SERVER_NOT_INITIALIZED = -32_002
        PROFILE_NOT_FOUND = -32_050
        PROTOCOL_VERSION_MISMATCH = -32_051
        NOT_SUPPORTED = -32_052
        VERSION_CONFLICT = -32_060
        EDIT_NOT_LOCAL = -32_061
      end
    end
  end
end
