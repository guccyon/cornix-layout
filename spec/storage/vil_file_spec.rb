# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tmpdir'
require_relative '../mapping/support/vil_image'

RSpec.describe Cornix::Storage::VilFile do
  subject(:vil_file) { described_class.new }

  let(:image_class) { Cornix::Image }
  let(:fixture) { File.expand_path('../fixtures/layout.vil', __dir__) }
  let(:baseline) { File.expand_path('../fixtures/authors_baseline.vil', __dir__) }

  # 2 つの JSON の葉を並べて、文字列が違う場所を [場所, 元, 出力] で返す
  def spelling_differences(original, dumped, at = '')
    case original
    when Hash
      original.flat_map { |key, value| spelling_differences(value, dumped[key], "#{at}.#{key}") }
    when Array
      original.each_with_index.flat_map { |value, i| spelling_differences(value, dumped[i], "#{at}[#{i}]") }
    else
      original == dumped ? [] : [[at, original, dumped]]
    end
  end

  def minimal(overrides = {})
    {
      'version' => 1, 'uid' => 1, 'vial_protocol' => 6, 'via_protocol' => 9,
      'settings' => { '7' => 180 },
      'layout' => [[['KC_A', -1]]], 'encoder_layout' => [[%w[KC_VOLD KC_VOLU]]],
      'macro' => [[]], 'tap_dance' => [['KC_A', 'KC_B', 'KC_NO', 'KC_NO', 200]],
      'combo' => [%w[KC_A KC_B KC_NO KC_NO KC_C]],
      'layout_options' => 0, 'key_override' => [], 'alt_repeat_key' => []
    }.merge(overrides)
  end

  def parse_error(data)
    vil_file.parse(data.is_a?(String) ? data : JSON.generate(data))
    raise 'ConfigError が出ませんでした'
  rescue Cornix::ConfigError => e
    e
  end

  describe 'layout.vil の往復' do
    shared_examples 'round trip' do |label|
      it "#{label}: dump(read) は元のファイルと同じ（違うのは同じ値の別表記だけ）" do
        skip "#{path} がありません" unless File.exist?(path)

        source = File.read(path, encoding: Encoding::UTF_8)
        dumped = vil_file.dump(vil_file.read(path))
        next if dumped == source

        original_json = JSON.parse(source)
        dumped_json = JSON.parse(dumped)
        expect(dumped_json.keys).to eq(original_json.keys)
        expect(dumped).to eq(JSON.pretty_generate(dumped_json))
        differences = spelling_differences(original_json, dumped_json)
        vial = vil_file.vial
        differences.each do |at, original, after|
          expect([at, vial.parse_code(after)]).to eq([at, vial.parse_code(original)])
        end
        expect(differences.size).to be <= expected_spelling_differences
      end
    end

    context 'spec/fixtures/layout.vil' do
      let(:path) { fixture }
      let(:expected_spelling_differences) { 2 } # KC_LEFT_PAREN / KC_RIGHT_PAREN → LSFT(KC_9) / LSFT(KC_0)

      include_examples 'round trip', 'fixture'
    end

    context 'spec/fixtures/authors_baseline.vil' do
      let(:path) { baseline }
      let(:expected_spelling_differences) { 2 } # KC_PGDN → KC_PGDOWN, LGUI(LSFT(KC_EQUAL)) → SGUI(KC_EQUAL)

      include_examples 'round trip', 'baseline'
    end

    it '整数は旧 Device::Keycodes#encode で求めて保存した値（spec/fixtures/expected）と同じになる' do
      VilImage::NAMES.each do |name|
        expected = VilImage.load(name)
        image = vil_file.read(VilImage.path(name))
        %i[layers encoders tap_dances combos macros settings meta].each do |field|
          expect(image.public_send(field)).to eq(expected.public_send(field)), "#{name}: #{field}"
        end
        # 旧表にない名前は p1 で追加した QMK の長い名前だけ
        expect(VilImage.values(name)['names_unknown_to_old_table'] - %w[KC_LEFT_PAREN KC_RIGHT_PAREN]).to be_empty
      end
    end
  end

  describe '#parse' do
    it '各項目を DeviceImage にする' do
      image = vil_file.parse(JSON.generate(minimal(
        'macro' => [[['tap', 'KC_A', 'KC_B'], ['down', 'KC_LSHIFT'], ['up', 'KC_LSHIFT'], ['delay', 100], %w[text abc]], []]
      )))
      expect(image.layers).to eq([[[0x04, nil]]])
      expect(image.encoders).to eq([[image_class::EncoderRecord.new(ccw: 0xAA, cw: 0xA9)]])
      expect(image.settings).to eq(7 => 180)
      expect(image.tap_dances).to eq([image_class::TapDanceRecord.new(on_tap: 0x04, on_hold: 0x05, on_double_tap: 0,
                                                                      on_tap_hold: 0, tapping_term: 200)])
      expect(image.combos).to eq([image_class::ComboRecord.new(keys: [0x04, 0x05, 0, 0], output: 0x06)])
      expect(image.macros).to eq([
        [image_class::MacroAction.new(kind: :tap, keys: [0x04, 0x05]),
         image_class::MacroAction.new(kind: :down, keys: [0xE1]),
         image_class::MacroAction.new(kind: :up, keys: [0xE1]),
         image_class::MacroAction.new(kind: :delay, value: 100),
         image_class::MacroAction.new(kind: :text, value: 'abc')],
        []
      ])
    end

    it 'その他のトップレベル項目は元の順で meta に入る' do
      image = vil_file.parse(JSON.generate(minimal('extra' => { 'a' => 1 })))
      expect(image.meta.keys).to eq(%w[version uid vial_protocol via_protocol layout_options key_override alt_repeat_key extra])
      expect(image.meta['extra']).to eq('a' => 1)
    end

    it 'Device::Reader と同じ形の meta を持つ（Planning::ImageDiff が読む）' do
      image = vil_file.parse(JSON.generate(minimal))
      expect(image.meta).to include('version' => 1, 'uid' => 1, 'vial_protocol' => 6, 'via_protocol' => 9,
                                    'layout_options' => 0, 'alt_repeat_key' => [], 'key_override' => [])
    end

    it '項目がなければ空として読む' do
      image = vil_file.parse('{"version": 1}')
      expect([image.layers, image.encoders, image.macros, image.tap_dances, image.combos, image.settings])
        .to eq([[], [], [], [], [], {}])
    end

    describe 'エラー' do
      it 'JSON の構文エラーは ConfigError' do
        expect(parse_error('{"layout": [').message).to include('JSON として読めません')
      end

      it 'ルートがオブジェクトでなければ ConfigError' do
        expect(parse_error([1]).message).to include('JSON のオブジェクトではありません')
      end

      it '不明なキーコードは場所付きで、すべて集めて報告する' do
        error = parse_error(minimal(
          'layout' => [[['KC_A', 'KC_BOGUS']], [['NOPE', -1]]],
          'encoder_layout' => [[%w[KC_VOLD XX]]],
          'combo' => [%w[KC_A KC_B KC_NO KC_NO YY]]
        ))
        expect(error.message).to include('4 件の問題があります')
        expect(error.message).to include('layout[0][0][1]: 不明なキーコード: KC_BOGUS')
        expect(error.message).to include('layout[1][0][0]: 不明なキーコード: NOPE')
        expect(error.message).to include('encoder_layout[0][0][1]: 不明なキーコード: XX')
        expect(error.message).to include('combo[0][4]: 不明なキーコード: YY')
      end

      it '形の違いを場所付きで報告する' do
        error = parse_error(minimal(
          'settings' => { 'x' => 1, '3' => 'a' },
          'layout' => [{}],
          'encoder_layout' => [[['KC_A']]],
          'macro' => [[['beep'], ['delay', 'x'], ['text'], 'tap', ['tap', 1.5]]],
          'tap_dance' => [['KC_A', 'KC_B', 'KC_NO', 'KC_NO', -1], ['KC_A']],
          'combo' => 'x'
        ))
        [
          'settings["x"]: 設定の番号は 0 以上の整数です',
          'settings["3"]: 設定の値は整数です',
          'layout[0]: 配列ではありません（オブジェクト）',
          'encoder_layout[0][0]: [反時計回り, 時計回り] の 2 要素の配列ではありません',
          'macro[0][0][0]: マクロの動作が不明です: "beep"',
          'macro[0][1]: ["delay", ミリ秒] の形ではありません',
          'macro[0][2]: ["text", 文字列] の形ではありません',
          'macro[0][3]: マクロの動作は配列です（文字列）',
          'macro[0][4][1]: キーコードは文字列です（数値）',
          'tap_dance[0][4]: tapping_term は 0 以上の整数です',
          'tap_dance[1]: [on_tap, on_hold, on_double_tap, on_tap_hold, tapping_term] の 5 要素の配列ではありません',
          'combo: 配列ではありません（文字列）'
        ].each { |message| expect(error.message).to include(message) }
      end

      it '#read のエラーにはファイルのパスが付く' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'layout.vil')
          File.write(path, JSON.generate(minimal('layout' => [[['KC_BOGUS']]])))
          expect { vil_file.read(path) }.to raise_error(Cornix::ConfigError) { |e|
            expect(e.path).to eq(path)
            expect(e.message).to start_with("#{path}: layout[0][0][0]: 不明なキーコード: KC_BOGUS")
          }
        end
      end

      it '読めないファイルは ConfigError' do
        expect { vil_file.read('/nonexistent/layout.vil') }.to raise_error(Cornix::ConfigError, /読み込めません/)
      end
    end
  end

  describe '#dump / #write' do
    it '旧 VialWriter と同じキーの順（ヘッダ → 各項目 → その他の meta）で書く' do
      image = image_class::DeviceImage.new(
        layers: [[[0x04, nil]]], encoders: [[image_class::EncoderRecord.new(ccw: 0xAA, cw: 0xA9)]],
        macros: [[image_class::MacroAction.new(kind: :tap, keys: [0x04]), image_class::MacroAction.new(kind: :delay, value: 5),
                  image_class::MacroAction.new(kind: :text, value: 'hi')]],
        tap_dances: [image_class::TapDanceRecord.new(on_tap: 4, on_hold: 0x5221, on_double_tap: 0, on_tap_hold: 0,
                                                     tapping_term: 200)],
        combos: [image_class::ComboRecord.new(keys: [4, 5, 0, 0], output: 0x7700)],
        settings: { 27 => 120, 7 => 180 },
        meta: { 'layout_options' => 0, 'version' => 1, 'uid' => 2, 'vial_protocol' => 6, 'via_protocol' => 9,
                'alt_repeat_key' => [], 'key_override' => [] }
      )
      json = JSON.parse(vil_file.dump(image))
      expect(json.keys).to eq(%w[version uid vial_protocol via_protocol settings layout encoder_layout macro tap_dance
                                 combo layout_options alt_repeat_key key_override])
      expect(json['settings']).to eq('7' => 180, '27' => 120)
      expect(json['settings'].keys).to eq(%w[7 27])
      expect(json['layout']).to eq([[['KC_A', -1]]])
      expect(json['encoder_layout']).to eq([[%w[KC_VOLD KC_VOLU]]])
      expect(json['macro']).to eq([[%w[tap KC_A], ['delay', 5], %w[text hi]]])
      expect(json['tap_dance']).to eq([['KC_A', 'MO(1)', 'KC_NO', 'KC_NO', 200]])
      expect(json['combo']).to eq([%w[KC_A KC_B KC_NO KC_NO M0]])
      expect(vil_file.parse(vil_file.dump(image))).to eq(image)
    end

    it '#write はファイルに書いてパスを返す' do
      image = vil_file.read(fixture)
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'out.vil')
        expect(vil_file.write(image, path)).to eq(path)
        expect(vil_file.read(path)).to eq(image)
      end
    end
  end
end
