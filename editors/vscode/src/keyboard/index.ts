// プロファイルに使う KeyboardSpec を選ぶ（ホスト側）。今は常に Cornix
import { CORNIX } from './cornix';
import type { KeyboardSpec } from './spec';

export function keyboardSpecFor(_profileDir?: string): KeyboardSpec {
  return CORNIX;
}
