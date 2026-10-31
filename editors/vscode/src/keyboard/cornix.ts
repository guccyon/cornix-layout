// Cornix の KeyboardSpec（spec.ts）。値は cornix 本体の Domain::Capabilities::CORNIX と docs/domain-model.md の position_map に合わせる。
// Webview はこのファイルを import しない（ホストが選んで送る。ADR 026）
import type { KeyboardSpec } from './spec';

export const CORNIX: KeyboardSpec = {
  id: 'cornix',
  displayName: 'Cornix',
  limits: { layers: 10, macros: 32, tapDances: 32, combos: 32, comboKeys: 4 },
  sections: [
    { id: 'left', label: '左手' },
    { id: 'right', label: '右手' },
  ],
  groups: [
    { id: 'row0', label: '1 段目' },
    { id: 'row1', label: '2 段目' },
    { id: 'row2', label: '3 段目' },
    { id: 'row3', label: '4 段目' },
    { id: 'thumb', label: '親指' },
    // 前の版のサーバーが返す旧名
    { id: 'thumb_keys', label: '親指' },
  ],
  // 図の配置は K2（#139）で埋める
  keys: [],
  encoders: [],
};
