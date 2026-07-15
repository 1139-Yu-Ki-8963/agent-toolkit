# 判定票 Markdown フォーマット定義（report-format）

Phase 3(レポート出力)が生成する判定票 Markdown のテンプレート。`判定票サンプル.md`(設計時の記入例)の構成を、診断実行時に実データで埋める版として移植したもの。1〜7節の見出し構成・列構成は固定し、本文中の値のみを診断結果で置換する。

## 出力テンプレート

```markdown
# <対象プロジェクト名> Claude Code プロジェクト診断 判定票

診断日時: <ISO8601>
対象ルート: <target_root>
前回診断: <prev_date または「初回診断」>

## 1. 判定票の使い方

本票は `consult-ai-config-doctor` により CLAUDE.md・Rules・Skills・Hooks・Subagents・自動化衛生の 6 ドメインを
D〜S の 5 段階で採点した結果である。診断は読み取り専用で実施し、修正(fix)は7節の処方箋一覧をユーザーが
承認した範囲のみ適用済み(未適用の場合は「未実施」と明記)。

## 2. ドメイン別判定基準表

| 判定 | 星 | 条件 |
|---|---|---|
| S | ★5 | CRITICAL 0・WARN 0・充足率 90% 以上 |
| A | ★4 | CRITICAL 0・WARN 3 件以下 |
| B | ★3 | CRITICAL 0・WARN 4 件以上 |
| C | ★2 | CRITICAL 1 件以上 |
| D | ★1 | 当該ドメインが存在しない・検査不能 |

## 3. ドメイン別結果

| ドメイン | CRITICAL | WARN | INFO | 充足率 | ドメイン判定 | 主要な指摘 |
|---|---|---|---|---|---|---|
<!-- 充足率は集計 JSON の domains[].coverage を百分率表記する。入力 findings に coverage が無かったドメインは normalize で 0 に補正されるため「0%※（未計測）」と脚注を付ける -->

| CLAUDE.md | <n> | <n> | <n> | <pct> | <grade> | <top_finding> |
| Rules | <n> | <n> | <n> | <pct> | <grade> | <top_finding> |
| Skills | <n> | <n> | <n> | <pct> | <grade> | <top_finding> |
| Hooks | <n> | <n> | <n> | <pct> | <grade> | <top_finding> |
| Subagents | <n> | <n> | <n> | <pct> | <grade> | <top_finding> |
| 自動化・運用衛生 | <n> | <n> | <n> | <pct> | <grade> | <top_finding> |

### ドメイン別詳細(観点キー単位)

ドメインごとに検出された全 findings を意味語キー単位で列挙する(連番禁止)。

```
#### <ドメイン名>
- [<CRITICAL|WARN|INFO>] <観点キー>: <detail>
  根拠: <evidence>
  提案: <recommendation>
```

## 4. 総合判定の算出

- 最低グレードのドメイン: <domain> (<grade>)
- 他 5 ドメイン平均: <grade相当>
- 加点判定: <2段階以上高いため1段階加点 / 加点条件不成立>
- **総合判定: <overall.grade>(★<overall.stars>)**

## 5. AI 駆動レベル連動

| 総合判定 | 推奨 AI 駆動レベル上限 |
|---|---|
| S | レベル5(完全自動) |
| A | レベル4(例外のみ人介入) |
| B | レベル3(人が承認する AI 実行) |
| C | レベル2(AI 補助) |
| D | レベル1(人手のみ) |

- **推奨 AI 駆動レベル: レベル<overall.ai_level>(<overall.ai_level_label>)**
- 判断根拠: <最低グレードドメインが何か・他ドメインとの差分から導いた1〜3文の説明>

## 6. 処方箋一覧

| 処方箋キー | ドメイン | リスク | 所要時間 | 期待効果 | 適用状況 |
|---|---|---|---|---|---|
| <key> | <domain> | <safe/careful/surgery> | <n>分 | <domain>: <from>→<to> | <未承認/承認・未適用/適用済み/適用失敗> |

## 7. diff(2 回目以降の診断のみ)

| ドメイン | 前回判定 | 今回判定 | 変化 |
|---|---|---|---|
| <domain> | <from> | <to> | <改善/悪化/変化なし> |

総合判定: <overall_from> → <overall_to>
```

## 埋め込みルール

- `<n>` 等の山括弧プレースホルダーは Phase 2 の集計 JSON(`references/grading-rules.md` 6節のスキーマ)の対応フィールドから機械的に埋める
- `<domain>` は `claude-md` / `rules` / `skills` / `hooks` / `subagents` / `hygiene` の内部 id ではなく、3節の表に示す日本語ラベル(CLAUDE.md / Rules / Skills / Hooks / Subagents / 自動化・運用衛生)で表示する
- 初回診断(`diff.prev_date == null`)では 7 節セクション自体を出力しない
- 該当ドメインが D(検査不能)で「設計上妥当」な除外理由がある場合、3節の行に脚注(`※` 付き注記)を追加し、除外理由を明記する
- 診断時に生成する成果物には「記入例」は含めない。本ファイルはあくまでテンプレート定義であり、架空の記入例は本ファイル内に持たない(記入例が必要な場合は設計時サンプルの `判定票サンプル.md` を別途参照する)

## 参照資料

- `references/grading-rules.md` — 判定式・集計 JSON スキーマの正本
- `scripts/render-dashboard.mjs` — 本テンプレートと対になる HTML ダッシュボード生成スクリプト
