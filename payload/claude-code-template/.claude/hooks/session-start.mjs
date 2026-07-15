// 未適応検知（session-start.mjs）
// 配線: SessionStart — matcher: "startup|resume|clear"
// 設計: ADAPT マーカーが残っている場合のみ additionalContext を注入する。
//       適応済み（0 件）なら完全に沈黙する（コンテキスト節約）。
//       この hook が正常動作すること自体が「Node が動いている」カナリアとして機能する。
// fail-open: エラー時は素通しする。

import { readInput, output, findAdaptMarkers, projectDir } from './lib/common.mjs';

try {
  const input = await readInput();
  if (!input) process.exit(0);
  if (input.source === 'compact') process.exit(0);

  const markers = findAdaptMarkers(projectDir());
  if (markers.length === 0) process.exit(0);

  const files = [...new Set(markers.map(m => m.file))].slice(0, 5);
  output({
    hookSpecificOutput: {
      hookEventName: 'SessionStart',
      additionalContext: `テンプレートの ADAPT マーカーが ${markers.length} 件残っています（対象: ${files.join(', ')}）。/adapt を実行すると適応が完了します。ユーザーが別の作業を依頼している場合はそれを優先し、区切りで一度だけ提案してください。`,
    },
  });
} catch { /* fail-open */ }
