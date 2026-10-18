# frozen_string_literal: true

module Cornix
  module Storage
    # .cornix.yml（どの設定ディレクトリを使うか）の検索と読み書き。中身は次のどちらか 1 行:
    #   profile: NAME   … <.cornix.yml のディレクトリ>/profiles/NAME
    #   config: PATH    … .cornix.yml からの相対パス
    module SettingsFile
      NAME = '.cornix.yml'
      KEYS = %w[profile config].freeze

      module_function

      # dir に .cornix.yml があればそのパス、なければ nil
      def at(dir)
        path = File.join(dir, NAME)
        File.file?(path) ? path : nil
      end

      # start_dir から親へたどって最初に見つかる .cornix.yml のパス（なければ nil）
      def find(start_dir)
        dir = start_dir
        loop do
          found = at(dir)
          return found if found

          parent = File.dirname(dir)
          return nil if parent == dir

          dir = parent
        end
      end

      # → ['profile' | 'config', 値]。形が違えば ConfigError
      def read(path)
        data = YamlFile.read(path)
        raise ConfigError.new('profile: NAME か config: PATH を書いたマッピングにしてください', path: path) unless data.is_a?(Hash)

        given = KEYS.select { |key| !data[key].to_s.empty? }
        raise ConfigError.new('profile: NAME か config: PATH のどちらか 1 つを書いてください', path: path) unless given.size == 1

        [given.first, data[given.first].to_s]
      rescue YamlFile::Unreadable => e
        raise ConfigError.new("YAML として読めません: #{e.message}", path: path)
      end

      # dir に .cornix.yml を書く（key は 'profile' か 'config'）→ パス
      def write(dir, key, value)
        raise ArgumentError, "知らないキーです: #{key}" unless KEYS.include?(key)

        path = File.join(dir, NAME)
        File.write(path, "#{key}: #{value}\n")
        path
      end
    end
  end
end
