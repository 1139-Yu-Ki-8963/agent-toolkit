window.TASK_BOARD = {
  "schema_version": 1,
  "tasks": [
    {
      "id": "portal-common-debt-fix",
      "goal": "ポータル全ページ共通の既存債務（footer なし・更新日時とコミット番号のメタ表示なし・テーマ切替の FOUC・theme ボタンの aria-pressed 欠落）を src/common 側で解消する",
      "completion_conditions": [
        "portal-reviewer の site-wide inherited 指摘 4 件が全ページで PASS になる"
      ],
      "status": "pending",
      "priority": "normal",
      "project": "/Users/<project>/agent-home",
      "created_at": "2026-07-23T17:52:22+09:00",
      "updated_at": "2026-07-23T17:52:22+09:00",
      "session_id": null,
      "receipt": null
    },
    {
      "id": "portal-catalog-drift-fix",
      "goal": "manage-portal.mjs verify の FAIL 5 件（managing-github-operations リネーム未反映・domain-terms 辞書カテゴリ未登録等のカタログずれ）を解消する",
      "completion_conditions": [
        "manage-portal.mjs verify が exit 0 になる"
      ],
      "status": "pending",
      "priority": "high",
      "project": "/Users/<project>/agent-home",
      "created_at": "2026-07-23T17:52:22+09:00",
      "updated_at": "2026-07-23T17:52:22+09:00",
      "session_id": null,
      "receipt": null
    },
    {
      "id": "review-window-rearm-fix",
      "goal": "check-managing-configs-review-needed.sh の抑制条件を時間窓 900 秒方式に変更し、レビュー後の編集に督促が再発火するようにする",
      "completion_conditions": [
        "時間窓判定の 6 パターン検証通過"
      ],
      "status": "done",
      "priority": "high",
      "project": "/Users/<project>/agent-home",
      "created_at": "2026-07-24T00:17:56+09:00",
      "updated_at": "2026-07-24T00:20:45+09:00",
      "session_id": "419bfcd2-8a03-47dc-8736-dad3cd684f4f",
      "receipt": "時間窓900秒方式へ変更。6パターン検証通過（抑制/再督促/フォールバック）。rule.md 再帰防止節を更新済み"
    },
    {
      "id": "gate-message-trim",
      "goal": "task-breakdown / plan-before-bulk-edit の block メッセージを 300 字以内に短縮し、重複実装の裁定を design-notes に記録する",
      "completion_conditions": [
        "wc -c で 300 字以内・回帰テスト通過"
      ],
      "status": "done",
      "priority": "high",
      "project": "/Users/<project>/agent-home",
      "created_at": "2026-07-24T00:17:56+09:00",
      "updated_at": "2026-07-24T00:21:25+09:00",
      "session_id": "419bfcd2-8a03-47dc-8736-dad3cd684f4f",
      "receipt": "両hookのblockメッセージを205字/192字に短縮・回帰テスト通過。重複裁定をdesign-notes 2件に記録"
    },
    {
      "id": "transcribing-images-skill",
      "goal": "画像書き起こしスキル transcribing-images を作成し、Phase 4 の次アクション提案を 100% スキル経由に固定する",
      "completion_conditions": [
        "SKILL.md + ガイド HTML + ポータル登録 + verify 通過"
      ],
      "status": "pending",
      "priority": "high",
      "project": "/Users/<project>/agent-home",
      "created_at": "2026-07-24T00:17:56+09:00",
      "updated_at": "2026-07-24T00:17:56+09:00",
      "session_id": null,
      "receipt": null
    },
    {
      "id": "gate-block-message-shortening",
      "goal": "task-breakdown/plan-before-bulk-edit hook の block メッセージ 300 字以内化と design-notes.txt 裁定追記（4ファイル）",
      "completion_conditions": [],
      "status": "done",
      "priority": "normal",
      "project": null,
      "created_at": "2026-07-24T00:19:34+09:00",
      "updated_at": "2026-07-24T00:21:25+09:00",
      "session_id": "419bfcd2-8a03-47dc-8736-dad3cd684f4f",
      "receipt": "gate-message-trim と同一作業（worker のゲート解消用登録）。本体タスク側で完了"
    },
    {
      "id": "reporting-session-progress-skill",
      "goal": "進捗確認スキル reporting-session-progress を新設（ボード・flow-status・実行中エージェント・git status の 1 画面集約報告）",
      "completion_conditions": [
        "SKILL.md + ガイド + ポータル登録 + verify 通過"
      ],
      "status": "pending",
      "priority": "high",
      "project": "/Users/<project>/agent-home",
      "created_at": "2026-07-24T00:48:29+09:00",
      "updated_at": "2026-07-24T00:48:29+09:00",
      "session_id": null,
      "receipt": null
    },
    {
      "id": "slides-skill-trigger-fix",
      "goal": "generating-explanation-html-slides の description を実測依頼文言に合わせて改善",
      "completion_conditions": [
        "実測パターンが TRIGGER に反映されている"
      ],
      "status": "done",
      "priority": "normal",
      "project": "/Users/<project>/agent-home",
      "created_at": "2026-07-24T00:48:29+09:00",
      "updated_at": "2026-07-24T00:50:43+09:00",
      "session_id": "419bfcd2-8a03-47dc-8736-dad3cd684f4f",
      "receipt": "SKILL.md frontmatterのTRIGGER/SKIP行を実測依頼文言に合わせて拡張"
    },
    {
      "id": "proposing-names-skill",
      "goal": "命名候補提案スキル proposing-names を新設（規約参照・3 案 + 根拠 + 適合チェック）",
      "completion_conditions": [
        "SKILL.md + ガイド + ポータル登録 + verify 通過"
      ],
      "status": "pending",
      "priority": "normal",
      "project": "/Users/<project>/agent-home",
      "created_at": "2026-07-24T00:48:29+09:00",
      "updated_at": "2026-07-24T00:48:29+09:00",
      "session_id": null,
      "receipt": null
    },
    {
      "id": "skill-description-budget-overrun",
      "goal": "全スキル description 合計が予算 2000 字を超過（実測 2992 字）。各スキルの description を圧縮して予算内に収める",
      "completion_conditions": [
        "合計 2000 字以内"
      ],
      "status": "pending",
      "priority": "normal",
      "project": "/Users/<project>/agent-home",
      "created_at": "2026-07-24T00:51:10+09:00",
      "updated_at": "2026-07-24T00:51:10+09:00",
      "session_id": null,
      "receipt": null
    }
  ]
};
