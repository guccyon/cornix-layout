# frozen_string_literal: true

module Cornix
  module Application
    # Claude Code の CLI（claude -p）にプロンプトを渡して出力を受け取る（rename の提案に使う）。
    # 入れ子のセッションにならないよう CLAUDECODE を外して起動する（旧 RenameCommand と同じ）
    class ClaudeCli
      def initialize(command: 'claude')
        @command = command
      end

      # PATH に claude があるか
      def available?
        ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |dir|
          path = File.join(dir, @command)
          File.file?(path) && File.executable?(path)
        end
      end

      # → [成功したか, 出力（標準エラーも含む）]
      def run(prompt)
        output = IO.popen({ 'CLAUDECODE' => nil }, [@command, '-p'], 'r+', err: %i[child out]) do |io|
          io.write(prompt)
          io.close_write
          io.read
        end
        [$?.success?, output.to_s]
      rescue SystemCallError => e
        [false, "Error: Command not found - #{e.message}"]
      end
    end
  end
end
