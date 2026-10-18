# vial_gui_0_7_5_codes.tsv.gz を作る（vial_notation_spec が format_code と全 16bit 値で比べる期待値）。
#
#   git clone https://github.com/vial-kb/vial-gui.git && git -C vial-gui checkout v0.7.5
#   python3 -m venv venv && venv/bin/pip install simpleeval
#   venv/bin/python -I spec/fixtures/expected/vial_gui_codes.py vial-gui/src/main/python spec/fixtures/expected/vial_gui_0_7_5_codes.tsv.gz
#
# Cornix の枠（Domain::Capabilities::CORNIX）で Vial GUI がキーボードに接続したときの表を作り、
# Keycode.serialize が名前を返す値だけを書く（それ以外は 16 進）。
import gzip
import sys

sys.path.insert(0, sys.argv[1])
from keycodes.keycodes import Keycode, recreate_keyboard_keycodes  # noqa: E402


class Cornix:
    vial_protocol = 6
    layers = 10
    macro_count = 32
    tap_dance_count = 32
    # Cornix の customKeycodes（8 個）。Vial GUI は USER00〜USER07 にだけ名前を作る（serialize には個数だけが効く）
    custom_keycodes = [{"name": "BT%d" % i} for i in range(8)]
    midi = None
    supported_features = set()  # 名前の表には影響しない（hidden が付くだけ）


recreate_keyboard_keycodes(Cornix())
lines = ["# vial-gui 0.7.5 (e42622c) Keycode.serialize(code) for Cornix: vial_protocol 6, 10 layers, 32 macros, 32 tap dances, 8 custom keycodes",
         "# code<TAB>serialize(code). codes not listed are serialized as hex"]
for code in range(0x10000):
    name = Keycode.serialize(code)
    if not name.startswith("0x"):
        lines.append("%04X\t%s" % (code, name))
with gzip.GzipFile(sys.argv[2], "wb", mtime=0) as f:
    f.write(("\n".join(lines) + "\n").encode())
