// /adapt 完了判定 CLI（check-adapt.mjs）
// 使い方: node .claude/hooks/lib/check-adapt.mjs
// 残 0 件なら「OK」と exit 0、1 件以上ならマーカー一覧と exit 1。
// 読み取り専用。人間が叩いても安全。

import { findAdaptMarkers, projectDir } from './common.mjs';

const markers = findAdaptMarkers(projectDir());

if (markers.length === 0) {
  console.log('OK — ADAPT マーカーは残っていません');
  process.exit(0);
} else {
  console.log(`ADAPT マーカーが ${markers.length} 件残っています:\n`);
  for (const m of markers) {
    console.log(`  ${m.file}:${m.line}  ${m.text}`);
  }
  process.exit(1);
}
