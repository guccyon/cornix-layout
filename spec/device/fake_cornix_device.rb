# frozen_string_literal: true

require_relative 'fake_rmk_device'

# Cornix の大きさの偽の実機（FakeRmkDevice を layout.vil の大きさにしたもの）。device のサーバーの適合テストなどで使う。
#
#   device = FakeCornixDevice.new
#   device.load_image(image)            # Image::DeviceImage の状態にする（compile の出力など）
#   device.fail_write_after = 2         # 書き込みのコマンドを 2 回送ったあと、応答がなくなる（Cornix::DeviceUnavailable :timeout）
#   device.ignore_writes = true         # 書き込みに応答するが値を変えない（読み直しで違いが残る）
#   device.unavailable = :not_connected # 開けない（FakeCornixDevice.opener が Cornix::DeviceUnavailable を送出する）
#
# 大きさ: 10 レイヤー・8 行 × 7 列（キーは各行の列 0〜5 と、エンコーダのプッシュ (2,6)・(5,6)）・エンコーダ 2 つ・
# マクロ 32 個（バッファ MACRO_SPACE バイト）・タップダンス 32・コンボ 32・設定は Device::Protocol::SETTING_WIDTHS の 9 つ
class FakeCornixDevice < FakeRmkDevice
  LAYERS = 10
  ROWS = 8
  COLS = 7
  ENCODERS = 2
  MACRO_COUNT = 32
  MACRO_SPACE = 1024
  ENTRIES = 32
  # spec/fixtures/layout.vil の設定の値
  SETTINGS = { 2 => 50, 6 => 1000, 7 => 250, 18 => 20, 19 => 20, 22 => 1, 23 => 0, 26 => 1, 27 => 120 }.freeze
  KEYS = [*(0...ROWS).flat_map { |r| (0...6).map { |c| "#{r},#{c}" } }, '2,6', '5,6'].freeze

  DEFINITION = {
    'name' => 'Cornix',
    'matrix' => { 'rows' => ROWS, 'cols' => COLS },
    'layouts' => {
      'keymap' => [*KEYS.each_slice(7).to_a, ["0,0\n\n\n\n\n\n\n\n\ne", "1,0\n\n\n\n\n\n\n\n\ne"]]
    }
  }.freeze

  attr_accessor :fail_write_after, :ignore_writes, :unavailable

  # Environment の device_opener（unavailable なら開くときに Cornix::DeviceUnavailable）
  def self.opener(device)
    lambda do |&block|
      reason = device.unavailable
      raise Cornix::DeviceUnavailable.new("偽の実機が使えません（#{reason}）", reason: reason) if reason

      block.call(Cornix::Device::Session.new(device, definition: DEFINITION, connection_info: device.info))
    end
  end

  def initialize
    super(layers: LAYERS, rows: ROWS, cols: COLS, encoders: ENCODERS, macro_count: MACRO_COUNT, macro_size: MACRO_SPACE,
          tap_dance: ENTRIES, combo: ENTRIES, settings: SETTINGS)
    @write_count = 0
  end

  def info = { 'product' => 'Cornix', 'transport' => 'test' }

  # image（Image::DeviceImage）の状態にする。キーのない位置（nil）は 0、ない設定は今の値のまま
  def load_image(image, macro_codec: Cornix::Mapping::MacroCodec.new)
    layers.times do |l|
      rows.times { |r| cols.times { |c| @keymap[l][r][c] = image.layers.dig(l, r, c) || 0 } }
      @encoders[l].each_index do |e|
        record = image.encoders.dig(l, e)
        @encoders[l][e] = record ? [record.ccw, record.cw] : [0, 0]
      end
    end
    macros = (image.macros + ([[]] * macro_count)).first(macro_count)
    bytes = macro_codec.encode_all(macros).bytes
    raise ArgumentError, "マクロがバッファ（#{macro_size} バイト）に収まりません" if bytes.size > macro_size

    @macro = bytes + Array.new(macro_size - bytes.size, 0)
    @tap_dances = Array.new(tap_dance_count) do |i|
      td = image.tap_dances[i]
      td ? [td.on_tap, td.on_hold, td.on_double_tap, td.on_tap_hold, td.tapping_term] : [0, 0, 0, 0, 0]
    end
    @combos = Array.new(combo_count) { |i| (cb = image.combos[i]) ? [*cb.keys, cb.output] : [0, 0, 0, 0, 0] }
    image.settings.each { |id, value| @settings[id] = value if @settings.key?(id) }
    self
  end

  def transfer(bytes)
    msg = bytes + [0] * (32 - bytes.size)
    return super unless write_message?(msg)

    @write_count += 1
    if fail_write_after && @write_count > fail_write_after
      raise Cornix::DeviceUnavailable.new('キーボードから応答がありません（偽の実機）', reason: :timeout)
    end
    return (@sent << msg) && msg.dup if ignore_writes

    super
  end
end
