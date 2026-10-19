// 頭文字のバッジ（badge:<文字>）の色。Simple Icons にも Material Icon Theme にもないアプリのもので、画像は作らず CSS で描く。
// 色はそのアプリのアイコンの色に寄せた自前のもの（ロゴは写さない）。表にない文字は文字から決まる色にする。
const BADGE_COLORS: Record<string, string> = {
  Ai: '#FF9A00', // Illustrator
  Ps: '#31A8FF', // Photoshop
  Pr: '#9999FF', // Premiere Pro
  X: '#217346', // Microsoft Excel
  S: '#611F69', // Slack
  W: '#0078D4', // Windows
  CS: '#3478F6', // CleanShot X
  CSP: '#E8A33D', // CLIP STUDIO PAINT
  F: '#F26B1D', // Fusion 360
};

export function badgeColor(text: string): string {
  const known = BADGE_COLORS[text];
  if (known) return known;
  let hash = 0;
  for (const char of text) hash = (hash * 31 + char.charCodeAt(0)) % 360;
  return `hsl(${hash}, 55%, 45%)`;
}
