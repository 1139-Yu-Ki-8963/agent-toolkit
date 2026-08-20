---
name: consult-ai-config-doctor
description: "顧客のClaude Code設定6ドメイン診断・S〜D判定・処方箋適用。 TRIGGER when: 「プロジェクト診断」「設定の健康診断」「グレード判定」「AI駆動レベル判定」「ドクター」と言われた時。 SKIP: 単一アセットのレビュー・dry-run（→managing-agent-configs）、簡易スキャン（→consult-diagnose）。"
invocation: consult-ai-config-doctor
type: audit
allowed-tools: [Agent, Read, Grep, Bash, Write, AskUserQuestion]
---

# Claude Code プロジェクト健康診断オーケストレーター

本スキルは **Claude Code 設定の運用実態に特化した診断ツール** であり、汎用のコード品質診断ではない。対象プロジェクトの `.claude/` 配下（CLAUDE.md・Rules・Skills・Hooks・Subagents）と、それらを支える自動化・運用衛生の計 6 ドメインを読み取り専用で並列診断し、D〜S の 5 段階（星 1〜5）で採点したうえで AI 駆動レベル 1〜5 と連動させ、ユーザー承認済みの処方箋（fix）適用まで一気通貫で担う。

## Iron rules（最上位契約。本文の他の記述より優先する）

1. 診断フェーズ（Phase 1〜3）は読み取り専用。Write は報告物と診断 JSON の保存のみに使う。設定ファイル本体・アセットの変更は一切行わない
2. fix（変更）は Phase 4 でユーザーが承認した処方箋のみを対象とし、Phase 5 で実行する。未承認の処方箋を先回りして適用しない
3. permission ガード・hook が発火したら迂回せず停止して報告する。block を回避する目的でのコマンド言い換え・sandbox 解除は行わない
4. シークレット値は引用禁止。`.env` の中身・API キー・トークン等はパスと存在の言及にとどめ、値そのものを報告物に転記しない

## 共通の前段（必ず最初に実行）

1. **進捗の可視化**: Phase 1〜6 の各主要ステップを `TaskCreate` で登録し、開始時に `TaskUpdate` で `in_progress`、完了時に `completed` に切り替える
2. **スコープ確認**（Phase 1 着手前）: 対象ルート・除外パス・出力先の 3 項目を `AskUserQuestion` で確定する。対象プロジェクトの `.claude/diagnosis/latest.json` が存在すれば diff モードを有効化し、前回診断との比較を後段（Phase 3・Phase 6）で提示する
3. **既存の判定基準ロード**: `references/grading-rules.md`（グレード判定式の正本）を Read する。これを読まずに Phase 2 の判定へ進まない

## Phase 構成

| Phase | 内容 | 完了条件 |
|---|---|---|
| Phase 1 | 並列診断: investigator 6 体をドメインごとに並列起動し、`.claude/diagnosis/raw/` に findings JSON を保存 | 6 ドメイン分の findings JSON が回収されている |
| Phase 2 | 集計判定: `scripts/aggregate-findings.mjs` で normalize + グレード判定 + AI 駆動レベル確定 | 集計 JSON が生成され、スクリプトが exit 0 で終了している |
| Phase 3 | レポート出力: 判定票 Markdown（`references/report-format.md` 準拠）+ `scripts/render-dashboard.mjs` による HTML 出力。diff モード時は `scripts/compare-diagnoses.mjs` の結果も併せて表示。集計 JSON を対象プロジェクトの `.claude/diagnosis/<timestamp>.json` と `.claude/diagnosis/latest.json` に保存 | 判定票 Markdown・ダッシュボード HTML・診断 JSON の 3 成果物が出力先に存在する |
| Phase 4 | fix 承認: 処方箋一覧（risk・所要時間・期待効果を列挙）を `AskUserQuestion` で提示し、適用対象を確定する。処方箋 0 件なら Phase 6 へ直行 | 適用対象の承認集合が確定している |
| Phase 5 | fix 適用: worker-sonnet が safe → careful → surgery の順に処方箋を適用する。surgery 分類は 1 件ごとに個別確認を取る。手順詳細は `references/fix-playbook.md` | 承認済み処方箋がすべて適用済み、または失敗が記録済みである |
| Phase 6 | 再診断・完了報告: 変更のあったドメインのみ再診断し、diff を表示してから完了報告を出す | **Goal**: 総合グレードと AI 駆動レベルが確定し、diff モード時は前回比較が提示されている |

Phase 番号は 1 始まりの正整数のみを使う。共通の前段（スコープ確認・判定基準ロード）は Phase 1 の前段扱いとし、独立した Phase 番号を割り当てない。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 6 ドメイン分の findings JSON が `.claude/diagnosis/raw/` に揃っている |
| Phase 2 | 集計 JSON が生成され、6 ドメインすべてにグレードと星数が付与されている |
| Phase 3 | 判定票 Markdown・ダッシュボード HTML・診断 JSON の 3 成果物が出力先に存在する |
| Phase 4 | 適用対象（0 件を含む）の承認集合が確定している |
| Phase 5 | 承認分の処方箋がすべて適用済みまたは失敗理由付きで記録されている |
| Phase 6 | 変更ドメインの再診断が完了し、diff が提示されている |
| **Goal** | 全 Phase を通過し、総合グレードと AI 駆動レベルが確定している。diff モード時は前回比較が併記されている |

## サブエージェント委任仕様

| 呼び出し箇所 | subagent_type | prompt 骨格 | 期待返却値 |
|---|---|---|---|
| Phase 1（ドメイン診断） | `investigator` ×6（並列） | `references/domain-briefs.md` の共通禁止ブロック（読み取り専用契約・許可コマンド・シークレット非引用・除外パス）+ 該当ドメイン節の定義 + findings JSON スキーマ + 出力行数上限 | ドメインごとの findings JSON のみ（CRITICAL/WARN/INFO 件数・該当箇所・充足率） |
| Phase 5（fix 適用） | `worker-sonnet` | 承認済み処方箋の適用プロンプト実体（対象ファイル・変更意図・スコープ外変更禁止を明記）+ 完了条件 | 適用結果（成功/失敗）と検証出力（適用前後の差分要約） |
| Phase 6（再診断） | `investigator` | 変更のあったドメインのみを対象にした Phase 1 と同じ prompt 骨格（対象ドメインを限定） | 変更ドメイン分の findings JSON |

## ループ設計

Phase 5 → Phase 6 の適用・再診断サイクルは最大 2 周まで反復する。

| 要素 | 内容 |
|---|---|
| 反復条件 | Phase 6 の再診断でグレード未改善または新規 CRITICAL 検出時に、原因を特定して Phase 5 に戻る |
| 上限回数 | 最大 2 周 |
| 停止条件 | 下記 3 パターンのうち 2 つ以上で停止する |

- **収束停止**: 全ドメインで CRITICAL 0 到達
- **発散検知**: 再診断でグレードが改善しない（同一グレードのまま停滞）
- **リソース上限**: 2 周に到達

検証役（Phase 6 の investigator）は適用役（Phase 5 の worker-sonnet）と分離する。

## グレード判定（要約。正本は references/grading-rules.md）

| グレード | 条件 |
|---|---|
| D | ドメイン不在・検査不能 |
| C | CRITICAL ≧ 1 |
| S | CRITICAL = 0 かつ WARN = 0 かつ充足率 ≧ 90% |
| A | CRITICAL = 0 かつ WARN ≦ 3 |
| B | CRITICAL = 0 かつ WARN ≧ 4 |

星換算: S=5 / A=4 / B=3 / C=2 / D=1。総合グレードは全ドメイン最低値を採用し、他ドメイン平均が最低値より 2 段階以上高い場合のみ 1 段階加点する。

AI 駆動レベル対応: S→レベル5（完全自動）/ A→レベル4（例外のみ人介入）/ B→レベル3（人が承認する AI 実行）/ C→レベル2（AI 補助）/ D→レベル1（人手のみ）。

判定式の詳細（充足率の算出方法・ドメイン別の重み付け・境界値の扱い）は `references/grading-rules.md` を正本とする。本節はその要約であり、齟齬が生じた場合は `references/grading-rules.md` を優先する。

## 予想を裏切る挙動

- 「診断」という単語だけでは発火しない。単一のスキル・ルール・フックのレビューや読み取り専用の dry-run 診断は `managing-agent-configs` の担当であり、本スキルはプロジェクト横断の 6 ドメイン診断のみを扱う
- ダッシュボード HTML は `assets/dashboard-template.html` を土台にする。外部 CDN 依存を持たない自己完結 HTML を維持する
- 診断 JSON（`<timestamp>.json` / `latest.json`）は本スキル側ではなく **対象プロジェクト側** の `.claude/diagnosis/` に保存される。複数プロジェクトを診断しても本スキルのディレクトリは汚れない
- 対象プロジェクトに `.claude/` が存在しない場合、全ドメインが D 判定になるのは仕様どおりの正常動作であり、検査不能をバグとして扱わない
- Phase 5 の fix は risk 分類（safe / careful / surgery）を必ず経由する。分類を飛ばして一括適用しない

## 完了報告

`.claude/skills/shared/references/completion-report-format.md` の共通骨格（作業報告型）に従う。

固有の検証行:
- 総合グレード（S〜D）・星数
- ドメイン別グレード（CLAUDE.md / Rules / Skills / Hooks / Subagents / 自動化・運用衛生）
- AI 駆動レベル（1〜5）
- 処方箋の適用件数（承認件数 / 適用成功件数 / 失敗件数）
- diff モード時の前回比較結果（改善・悪化・変化なしドメインの内訳）

## 参照資料

- `references/grading-rules.md` — グレード判定式・充足率算出・境界値の正本
- `references/domain-briefs.md` — 6 ドメインの共通禁止ブロックとドメイン別診断定義
- `references/claude-md-checks.md` — CLAUDE.md ドメインの個別チェック項目
- `references/fix-playbook.md` — 処方箋の risk 分類（safe / careful / surgery）と適用手順
- `references/report-format.md` — 判定票 Markdown のフォーマット定義
- `scripts/aggregate-findings.mjs` — findings JSON の normalize・グレード判定・AI 駆動レベル確定
- `scripts/render-dashboard.mjs` — 集計 JSON からダッシュボード HTML を生成
- `scripts/compare-diagnoses.mjs` — 前回診断との diff 算出（diff モード用）
