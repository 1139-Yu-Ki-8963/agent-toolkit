# グレード判定の正本（grading-rules）

本ファイルは `consult-ai-config-doctor` の判定式・スキーマの正本である。**Claude Code のプロジェクト設定（CLAUDE.md・Rules・Skills・Hooks・Subagents・自動化衛生）を診断対象とする専用ルールであり、汎用のコード品質診断（テストカバレッジ・複雑度・脆弱性スキャン等）は対象外**。汎用コード品質を診断したい場合は本スキルではなく別ツールを使う。

## 1. ドメイン別グレード判定式

各ドメインの findings（CRITICAL / WARN 件数）と充足率（推奨項目のうち満たした割合）から、以下の優先順位で判定する。上から順に評価し、最初に条件が成立した段階のグレードを採用する。

| 優先順 | グレード | 星 | 条件 |
|---|---|---|---|
| 1 | D | ★1 | ドメインが存在しない、または検査不能（例: CLAUDE.md が存在しない・Subagents 未導入） |
| 2 | C | ★2 | CRITICAL ≧ 1 |
| 3 | S | ★5 | CRITICAL = 0 かつ WARN = 0 かつ充足率 ≧ 90% |
| 4 | A | ★4 | CRITICAL = 0 かつ WARN ≦ 3 |
| 5 | B | ★3 | CRITICAL = 0 かつ WARN ≧ 4 |

- 充足率 = 満たしたチェック項目数 ÷ 当該ドメインの全チェック項目数。項目定義は `references/domain-briefs.md`（CLAUDE.md ドメインのみ `references/claude-md-checks.md`）の観点表に従う
- D と C は WARN 件数・充足率を問わず優先して確定する（D はそもそも計測不能、C は CRITICAL の存在自体が支配的な欠陥のため）
- 該当ドメインが「存在しないことが設計上妥当」（例: 小規模プロジェクトで Hooks 不要）と判断できる場合は、判定票の脚注に理由を明記したうえで総合判定の算出対象から除外してよい（除外しても D として全ドメイン最低値の算出には残す運用と、除外して母集団から外す運用のどちらを採るかは診断者が脚注で宣言する）

## 2. 総合判定の算出

1. 6 ドメイン（CLAUDE.md / Rules / Skills / Hooks / Subagents / 自動化・運用衛生）それぞれに §1 のグレードを付与する
2. 総合判定は全ドメインの最低グレードを基準とする
3. 最低グレード以外の 5 ドメインの平均が最低グレードより **2 段階以上高い場合に限り**、総合判定を 1 段階のみ加点する（例: 最低が D で他平均が B なら、D→C の 1 段階のみ加点。C→A のような 2 段階加点はしない）
4. 加点条件を満たさない場合、総合判定は最低グレードそのままとする

段階順序（低い→高い）: D < C < B < A < S

## 3. AI 駆動レベル対応表

総合判定から推奨 AI 駆動レベル上限を導出する。出典: ai-consulting-toolkit の AI 化レベル基準（誤り影響度・判断定型度・入力構造化度・検証容易性の 4 判定軸）に基づく。

| 総合判定 | AI 駆動レベル | レベル名称 |
|---|---|---|
| S | レベル5 | 完全自動 |
| A | レベル4 | 例外のみ人介入 |
| B | レベル3 | 人が承認する AI 実行 |
| C | レベル2 | AI 補助 |
| D | レベル1 | 人手のみ |

### 4 判定軸と設定層整備の対応関係

設定層の整備状況が上がるほど、対応する判定軸の評価が実態として引き上がる。整備が伴わないままレベルだけを引き上げると、軸の実態と乖離した過大評価になる。

| 4 判定軸 | 対応する設定層整備 | 整備が効く理由 |
|---|---|---|
| 検証容易性 | Hooks 整備（JSON 出力スキーマ・exit code 規約準拠） | 機械強制による即時 block/advisory があれば、成果物の正誤を全件人手精査なしで確認できる |
| 判断定型度 | Rules 整備（違反手順網羅・scope 適合性） | 判断基準が rule.md に文書化・機械参照可能な形で定型化されるほど、都度判断への依存が下がる |
| 入力構造化度 | Skills 整備（frontmatter 必須項目・Phase/Step 構造） | TRIGGER/SKIP・完了条件が構造化されるほど、ユーザー発話から実行手順への変換が整備済みに近づく |
| 誤り影響度 | Subagents 整備（単一責任・禁止ツール制御）+ 自動化衛生（冪等性・品質ゲート） | 責務分離と冪等性・品質ゲートが揃うほど、誤った成果物の影響範囲が局所化される |

## 4. CRITICAL による強制降格

いずれかのドメインで CRITICAL ≧ 1 件を検出した場合、そのドメインのグレードは WARN 件数・充足率に関わらず **C 以下に強制される**（§1 優先順 2 が S/A/B より先に評価されるため、自動的にこの挙動になる）。CRITICAL を「軽微」として A・B・S に押し上げる判定は禁止する。

## 5. findings JSON スキーマ

Phase 1・Phase 6 の投資エージェント（investigator）は、ドメインごとに以下のスキーマで findings を返す。

```json
{
  "domain": "claude-md|rules|skills|hooks|subagents|hygiene",
  "present": true,
  "coverage": 0.85,
  "findings": [
    {
      "key": "意味語キー",
      "severity": "CRITICAL|WARN|INFO",
      "detail": "検証済み事実",
      "evidence": "確認コマンドと出力抜粋",
      "recommendation": "提案",
      "fix": {
        "risk": "safe|careful|surgery",
        "time_min": 15,
        "expected": "C→B",
        "prompt": "適用プロンプト"
      }
    }
  ]
}
```

- `present: false` の場合は D 確定であり `coverage` は無視してよい（`null` 許容）
- `key` は連番禁止。対象と観点要約を組み合わせた意味語とする（例: `本体行数-200行上限`）
- `fix` は CRITICAL / WARN のみ必須。INFO は `fix: null` でよい

## 6. 集計 JSON スキーマ

Phase 2（`scripts/aggregate-findings.mjs`）が findings JSON 群から生成する集計物のスキーマ。

```json
{
  "meta": { "project": "string", "date": "ISO8601", "target_root": "string" },
  "domains": [
    {
      "id": "claude-md|rules|skills|hooks|subagents|hygiene",
      "label": "string",
      "grade": "S|A|B|C|D",
      "stars": 1,
      "critical": 0,
      "warn": 0,
      "info": 0,
      "coverage": 0.85,
      "top_finding": "意味語キー"
    }
  ],
  "overall": { "grade": "S|A|B|C|D", "stars": 1, "ai_level": 1, "ai_level_label": "string" },
  "prescriptions": [
    { "key": "処方箋キー", "domain": "string", "risk": "safe|careful|surgery", "time_min": 15, "expected": "C→B", "prompt": "string" }
  ],
  "diff": {
    "prev_date": "ISO8601|null",
    "changes": [ { "domain": "string", "from": "S|A|B|C|D", "to": "S|A|B|C|D" } ],
    "overall_from": "S|A|B|C|D|null",
    "overall_to": "S|A|B|C|D"
  }
}
```

- `diff` は `.claude/diagnosis/latest.json` が存在しない初回診断では `prev_date: null` / `changes: []` / `overall_from: null` とする
- `prescriptions` は CRITICAL / WARN の findings から `fix` を持つもののみを集約する
