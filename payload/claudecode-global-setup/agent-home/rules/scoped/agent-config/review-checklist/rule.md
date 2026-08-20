---
paths:
  - "**/.claude/rules/scoped/review-checklist/**"
  - "**/.claude/rules/always/review-checklist/**"
  - "**/.claude/agents/*-reviewer/**"
---

# レビュー観点フォルダ統治規約（REVIEW-CHECKLIST-STRUCTURE）

`~/.claude/rules/scoped/review-checklist/`（専門家別観点）と `~/.claude/rules/always/review-checklist/`（横断観点）の構造、およびレビュー専門家サブエージェントとの対応を統治する規約。レビュー観点・専門家・横断規約の 3 者のズレを構造とマシン監査で防ぐ。

## 構造の原則

1. **scoped 側・第 1 階層 = 専門家と 1 対 1**: `scoped/review-checklist/<domain>/` のフォルダ名は、担当サブエージェント `<domain>-reviewer`（`~/.claude/agents/<domain>-reviewer/`）と 1 対 1 対応する。フォルダに置いた瞬間に担当が確定し、frontmatter での宣言は不要（specialist フィールドは廃止済み。フォルダ導出が唯一の正）
2. **scoped 側・第 2 階層 = 観点**: `scoped/review-checklist/<domain>/<name>/rule.md` が観点の定義。paths frontmatter が適用対象ファイルを宣言する。1 ファイルに複数観点・複数ドメインが該当する場合は全て照合する
3. **always 側 = 全専門家の横断観点**: `always/review-checklist/<name>/rule.md` は「常時注入で全タスクに効く」規約のうち、レビュー時にも成果物の内容を機械照合すべきもの（用語辞書・連番ID・略称）。フォルダ位置が登録の代わりであり、登録リスト（旧 always-rules.txt）は持たない。全レビュー専門家が担当し、各専門家定義に実パス参照を持つことを監査が検証する
4. **観点の新設**: scoped は既存ドメイン配下にフォルダを足すだけでレビュー経路に乗る。新ドメインを作る場合は、対応する `<domain>-reviewer` を managing-agent-configs（種別 subagents）で先に新設する。always 側は「常時注入が必要か」を基準に判断する（レビュー時だけ必要なら scoped へ）
5. **rules の深さ**: scoped/review-checklist 配下のみ深さ 4。always/review-checklist は通常どおり深さ 3（scope/topic/name）

## サイドカー（本フォルダに同居する台帳）

| ファイル | 役割 |
|---|---|
| `rule-classification.txt` | レビュー観点**以外**の全グローバル rule の仕分け台帳。「config-asset / hook-enforced / behavior」のいずれかに分類し、未分類を禁止する。レビュー観点そのものは review-checklist 配下という場所が分類になるため載せない |

## 機械強制

| timing | スクリプト | 注入タグ | 挙動 |
|---|---|---|---|
| 手動・レビュー時 | `~/agent-home/skills/reviewing-against-rules/scripts/audit-review-coverage.sh` | なし（exit code） | ①scoped 各ドメインの `<domain>-reviewer` 実在 ②always/review-checklist の各規約が専門家定義から参照されているか ③ディスク上の全 rule.md が「review-checklist 配下」か「分類済み」か、を検証。1 件でも欠けると exit 1 |

hook による自動発火はなし。managing-agent-configs の rules レビュー時と、reviewing-against-rules の実行時に上記監査を走らせる。

## 違反検知時の手順

audit-review-coverage.sh が FAIL を出した場合:

1. `<domain>-reviewer 不在`: フォルダ名の typo か専門家未作成。managing-agent-configs（種別 subagents）で専門家を新設するか、既存ドメインへ観点を移す
2. `未分類 rule`: レビュー観点なら review-checklist 配下（scoped/<domain>/ または always/）へ移し、そうでなければ rule-classification.txt に分類（config-asset / hook-enforced / behavior）と補足を 1 行追記する
3. `横断観点 未参照`: always/review-checklist 配下の該当規約の実パス（`~/` 形式）を各専門家定義の動作原則に追記する
4. `dead entry`: 分類台帳から実在しない行を削除するか、参照先の rename に追従する

## 設計判断

設計判断・経緯の記録は同ディレクトリの `design-notes.txt` を参照（非注入サイドカー）。

## プロジェクト上書き

- 上書き可否: 一律適用
- 理由: レビュー観点フォルダの構造はグローバル資産の統治であり、プロジェクト側の迂回を想定しない。プロジェクト固有の観点値は各観点 rule の受け口（`<repo>/.claude/rules/scoped/review-checklist/<domain>/<name>/rule.md`）が担う

## 関連

- `~/agent-home/skills/reviewing-against-rules/SKILL.md` — レビューの単一入口（解決・委任の実行手順）
- `~/agent-home/skills/reviewing-against-rules/scripts/resolve-applicable-rules.sh` — 適用 rule と担当専門家（フォルダ導出）の解決
- `~/agent-home/ai-management-portal/architecture/review-architecture.html` — 仕組み全体の解説
- `~/.claude/rules/always/agent-config/review/rule.md` — 設定資産側のレビューゲート（managing-agent-configs 管轄）
