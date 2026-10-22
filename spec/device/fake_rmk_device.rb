# frozen_string_literal: true

# RMK 0.8 系ファームウェアの Vial 応答を模したテスト用デバイス（HidBridge#transfer の代わり）
#
# - 送られたコマンドをすべて sent に記録する
# - 範囲外アクセスはファームウェアならパニックする箇所なので、ここでは例外にしてテストを失敗させる
# - 大きさ（レイヤー・マトリクス・エンコーダ・マクロ・タップダンス・コンボ・設定）は new のキーワードで変えられる。
#   既定は小さな偽物（下の定数）。Cornix の大きさは spec/device/fake_cornix_device.rb の FakeCornixDevice
class FakeRmkDevice
  LAYERS = 2
  ROWS = 2
  COLS = 3
  ENCODERS = 1
  MACRO_COUNT = 4
  MACRO_SIZE = 64
  TAP_DANCE = 2
  COMBO = 2
  SETTINGS = { 2 => 50, 7 => 200, 22 => 0 }.freeze

  DEFINITION = {
    'name' => 'Fake',
    'matrix' => { 'rows' => ROWS, 'cols' => COLS },
    'customKeycodes' => [{ 'name' => 'BT0' }],
    'layouts' => {
      'keymap' => [
        ['0,0', '0,1', '0,2'],
        ['1,0', '1,1'], # (1,2) はキーとして存在しない
        ["0,0\n\n\n\n\n\n\n\n\ne", "0,1\n\n\n\n\n\n\n\n\ne"]
      ]
    }
  }.freeze

  # 設定 ID → 幅（バイト数）。ここにない ID は 2 バイト
  SETTING_WIDTHS = { 22 => 1, 23 => 1, 26 => 1 }.freeze

  attr_reader :sent, :keymap, :encoders, :macro, :tap_dances, :combos, :settings, :layers, :rows, :cols,
              :macro_count, :macro_size, :tap_dance_count, :combo_count

  def initialize(layers: LAYERS, rows: ROWS, cols: COLS, encoders: ENCODERS, macro_count: MACRO_COUNT,
                 macro_size: MACRO_SIZE, tap_dance: TAP_DANCE, combo: COMBO, settings: SETTINGS)
    @layers = layers
    @rows = rows
    @cols = cols
    @macro_count = macro_count
    @macro_size = macro_size
    @tap_dance_count = tap_dance
    @combo_count = combo
    @setting_ids = settings.keys.sort.freeze
    @sent = []
    @keymap = Array.new(layers) { Array.new(rows) { Array.new(cols, 0) } }
    @keymap[0][0][0] = 0x04 # KC_A
    @encoders = Array.new(layers) { Array.new(encoders) { [0xAA, 0xA9] } } # KC_VOLD, KC_VOLU
    @macro = Array.new(macro_size, 0)
    @tap_dances = Array.new(tap_dance) { [0, 0, 0, 0, 250] }
    @combos = Array.new(combo) { [0, 0, 0, 0, 0] }
    @settings = settings.dup
  end

  def info = { 'product' => 'Fake', 'transport' => 'test' }

  def writes = sent.select { |m| write_message?(m) }

  # 書き込みのコマンドか（キー・マクロ・エンコーダ・設定・タップダンス・コンボ）
  def write_message?(m)
    [0x05, 0x0F].include?(m[0]) || (m[0] == 0xFE && [0x04, 0x0B].include?(m[1])) ||
      (m[0] == 0xFE && m[1] == 0x0D && [0x02, 0x04].include?(m[2]))
  end

  def transfer(bytes)
    msg = bytes + [0] * (32 - bytes.size)
    @sent << msg
    out = msg.dup
    case msg[0]
    when 0x01 then out[1] = 0; out[2] = 9
    when 0x02 then out[2..5] = [0, 0, 0, 1] if msg[1] == 0x04
    when 0x05
      layer, row, col = msg[1..3]
      raise 'firmware panic: set_action_at out of range' unless layer < @layers && row < @rows && col < @cols

      @keymap[layer][row][col] = (msg[4] << 8) | msg[5]
    when 0x0C then out[1] = @macro_count
    when 0x0D then out[1] = @macro_size >> 8; out[2] = @macro_size & 0xFF
    when 0x0E, 0x0F
      offset = (msg[1] << 8) | msg[2]
      size = msg[3]
      raise 'firmware panic: macro buffer out of range' if size > 28 || offset + size > @macro_size

      if msg[0] == 0x0E
        out[4, size] = @macro[offset, size]
      else
        @macro = Array.new(@macro_size, 0) if offset.zero? # RMK 0.8 は先頭書き込みでキャッシュをクリアする
        @macro[offset, size] = msg[4, size]
      end
    when 0x11 then out[1] = @layers
    when 0x12
      offset = (msg[1] << 8) | msg[2]
      flat = @keymap.flatten
      (msg[3] / 2).times do |i|
        kc = flat[(offset / 2) + i] || 0
        out[4 + (i * 2)] = kc >> 8
        out[5 + (i * 2)] = kc & 0xFF
      end
    when 0xFE then out = vial(msg)
    else raise format('fake device: unexpected command 0x%02x', msg[0])
    end
    out
  end

  private

  def setting_width(id) = SETTING_WIDTHS.fetch(id, 2)

  def vial(msg)
    out = msg.dup
    case msg[1]
    when 0x00 then out[0..11] = [6, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8]
    when 0x03
      ccw, cw = @encoders.dig(msg[2], msg[3]) || [0, 0]
      out[0..3] = [ccw >> 8, ccw & 0xFF, cw >> 8, cw & 0xFF]
    when 0x04
      layer, idx, cw = msg[2..4]
      @encoders[layer][idx][cw == 1 ? 1 : 0] = (msg[5] << 8) | msg[6] if @encoders.dig(layer, idx)
    when 0x05 then out = [0, 0, 1, 1, 1, 2] + [0xFF] * 26
    when 0x09
      # greater_than より大きい ID を 16 個まで（残りは 0xFFFF）
      greater_than = msg[2] | (msg[3] << 8)
      out = Array.new(32, 0xFF)
      @setting_ids.select { |id| id > greater_than }.first(16).each_with_index do |id, i|
        out[i * 2] = id & 0xFF
        out[(i * 2) + 1] = id >> 8
      end
    when 0x0A
      id = msg[2] | (msg[3] << 8)
      out = Array.new(32, 0xFF)
      out[0] = 0
      out[1] = @settings[id] & 0xFF
      out[2] = @settings[id] >> 8 unless setting_width(id) == 1
    when 0x0B
      id = msg[2] | (msg[3] << 8)
      @settings[id] = setting_width(id) == 1 ? msg[4] : msg[4] | (msg[5] << 8)
    when 0x0D then out = dynamic(msg)
    else raise format('fake device: unexpected vial command 0x%02x', msg[1])
    end
    out
  end

  def dynamic(msg)
    out = msg.dup
    idx = msg[3]
    case msg[2]
    when 0x00 then out[0] = @tap_dance_count; out[1] = @combo_count; out[2] = 0
    when 0x01 then out[0] = 0; out[1..10] = @tap_dances[idx].pack('v5').bytes
    when 0x02 then @tap_dances[idx] = msg[4..13].pack('C*').unpack('v5') if idx < @tap_dance_count
    when 0x03 then out[0] = 0; out[1..10] = @combos[idx].pack('v5').bytes
    when 0x04 then @combos[idx] = msg[4..13].pack('C*').unpack('v5') if idx < @combo_count
    else raise 'fake device: unexpected dynamic op'
    end
    out
  end
end
