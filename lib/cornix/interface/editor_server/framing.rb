# frozen_string_literal: true

require 'json'

module Cornix
  module Interface
    module EditorServer
      # LSP と同じ `Content-Length: <バイト数>\r\n\r\n<JSON>` の枠で 1 メッセージずつ読み書きする（JSON は UTF-8）
      #
      #   Framing.read($stdin)            #=> Hash（読んだ JSON）| nil（EOF）
      #   Framing.write($stdout, message) # message は JSON にできる Hash
      #
      # ヘッダーは Content-Length のほかを無視する（Content-Type など）。名前の大文字小文字は区別しない
      module Framing
        # ヘッダーが読めない（Content-Length がない・数でない）。本文の長さが分からないので、それ以降は読めない
        class HeaderError < StandardError; end

        # 本文が JSON として読めない（本文は読み終えているので、続けて次のメッセージを読める）
        class ParseError < StandardError; end

        HEADER = 'Content-Length'

        module_function

        def read(io)
          length = read_headers(io)
          return nil if length.nil?

          body = io.read(length)
          return nil if body.nil? || body.bytesize < length

          parse(body)
        end

        def write(io, message)
          body = JSON.generate(message)
          io.write("#{HEADER}: #{body.bytesize}\r\n\r\n", body)
          io.flush if io.respond_to?(:flush)
        end

        # → 本文のバイト数。ヘッダーの前で EOF なら nil
        def read_headers(io)
          length = nil
          seen = false
          while (line = io.gets("\n"))
            line = line.chomp("\n").chomp("\r")
            if line.empty?
              next unless seen # メッセージの間の空行は読み飛ばす

              raise HeaderError, "#{HEADER} のヘッダーがありません" if length.nil?

              return length
            end
            seen = true
            name, value = line.split(':', 2)
            next unless name.strip.casecmp?(HEADER)

            raise HeaderError, "#{HEADER} が数ではありません: #{value.to_s.strip}" unless value.to_s.strip.match?(/\A\d+\z/)

            length = Integer(value.strip, 10)
          end
          raise HeaderError, 'ヘッダーの途中で入力が終わりました' if seen

          nil
        end

        def parse(body)
          text = body.dup.force_encoding(Encoding::UTF_8)
          raise ParseError, 'UTF-8 として読めません' unless text.valid_encoding?

          JSON.parse(text)
        rescue JSON::ParserError => e
          raise ParseError, e.message
        end
      end
    end
  end
end
