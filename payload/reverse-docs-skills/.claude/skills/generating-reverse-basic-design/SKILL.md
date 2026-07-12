---
name: generating-reverse-basic-design
description: "封印済みfactsから業務語彙のみで基本設計書を執筆する執筆役。 TRIGGER when: 事実封印後の基本設計書生成、決定木「基本設計未著述」での起動。 SKIP: 詳細設計執筆（→generating-reverse-detailed-design）、facts抽出（→extracting-unit-facts-from-code）。"
invocation: generating-reverse-basic-design
type: transform
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob]
---

# 封印済みfactsからの基本設計書執筆スキル

封印済み facts（facts.yml）とプロジェクト共通文書だけを情報源に、業務語彙のみで書かれた基本設計書（画面基本設計書.md）を著述する執筆専任スキル。generating-reverse-detailed-design と同じく原本非アクセスの執筆役であり、情報源は facts_ref 配下の facts.yml と common_docs_root 配下の共通文書に限定する。**本スキル実行中に対象リポジトリの原本コードを Read することは全面禁止**（検証の盲検性を壊す契約違反）である。

基本設計書は詳細設計書の抽象化・要約ではない。facts.yml から業務語彙で直接書く独立した成果物であり、詳細設計書（コード識別子・型構文を含む実装契約）とは章立て・読み手（業務担当者）が異なる。

## 目的

orchestrating-reverse-docs-flow の状態判定表で「基本設計未著述」は「事実未封印」の直後・「設計書未著述」の直前に位置する。本スキルはこの間隙を埋め、facts 封印直後に業務語彙のみの基本設計書を確立する。詳細設計書（generating-reverse-detailed-design が著述）が実装寄りの宣言的契約を担うのに対し、本スキルは業務担当者が読める業務レベルの記述に限定した基本設計書を担う。両者は互いに独立した成果物であり、一方が他方の入力にはならない（本スキルは詳細設計書を参照しない）。

## 使用タイミング

- facts が封印済み（extracting-unit-facts-from-code が `status=封印済み` で facts_ref を返した後）で、画面基本設計書を新規著述・再著述したいとき
- 本スキルが `status=基本設計著述完了` を返した後、orchestrating-reverse-docs-flow は次に generating-reverse-detailed-design（設計書未著述）を起動する
- 起動引数は screen_dir + facts_ref + common_docs_root + 資産パス群 + unit_kind

## スコープ

unit_kind パラメータで screen / batch / report / external を区別する契約とするが、**現時点で実装済みなのは unit_kind=screen のみ**（テンプレート `shared/templates/リバース検証/画面/基本設計/画面基本設計書.md` が存在するのは screen のみ。batch/report/external の基本設計書テンプレートは `納品物フォルダ体系.md` の【段階計画 Cycle 4】であり未着手）。screen 以外を指定された場合は著述を行わず `status=基本設計著述失敗` とし、hint に「unit_kind=screen 以外は未実装」と記す。この契約は extracting-unit-facts-from-code の `profile=screen のみ実装` と同型である。

## 設計原則

1. **正本一元化**: facts.yml は封印済みの確定情報であり第二の正本ではない。正は基本設計書。設計書と facts.yml が食い違ったら基本設計書を直す（facts.yml 自体の誤りは extracting-unit-facts-from-code への差し戻し対象であり本スキルは書き換えない）
2. **「該当なし」に根拠を必須とする**（例:「該当なし（facts.yml の api セクションに項目なし）」）。根拠なしの裸の「未確認」は完了条件違反
3. **プロジェクト非依存**: リバース対象の固有値（対象リポジトリパス・画面 ID・業務名）はすべて起動引数・設計書側に置き、本 SKILL.md 本文には書かない
4. **原本 Read 禁止**: 本スキル実行中に対象リポジトリの原本コードを Read することを全面禁止する。情報源は起動引数 facts_ref 配下の facts.yml と common_docs_root 配下の共通文書に限定する
5. **業務語彙限定**: コード識別子・フレームワーク用語・型構文・ファイルパス・ライブラリ名を一切含めない。実装寄りの契約は詳細設計書（generating-reverse-detailed-design）が担う
6. **詳細設計非依存**: 詳細設計書を参照・要約しない。facts.yml から独立して業務語彙で直接書く

## Phase 1: テンプレート展開と facts 読込

起動引数を検収する: screen_dir / docs_root / template_root / scaffold_script_path / facts_ref / common_docs_root / unit_kind（既定 screen）。unit_kind が screen 以外の場合は著述を行わず `status=基本設計著述失敗` とする（「スコープ」節を参照）。

画面ディレクトリが未存在の場合、本スキルがスキャフォールディングを実施する: `bash <scaffold_script_path> <docs_root> <画面ID> [<画面名>]`（scaffold_script_path は管理者が解決して渡すスキャフォールディングスクリプトのパス。実体: `shared/scripts/scaffold-screen.sh`。正本はこの1本のみ。基本設計/画面基本設計書.md を含む画面単位テンプレート一式を展開する）。既存の場合は `bash <scaffold_script_path> --verify <docs_root> <画面ID>` で構造の健全性を確認する。

`shared/scripts/seal-facts.sh verify <facts_ref>` を実行し exit 0 を確認する（必須ゲート）。exit 1（facts.yml が封印時から改変されている）なら著述を行わず `status=基本設計著述失敗` とし、hint に「extracting-unit-facts-from-code で再封印せよ」と記す。

exit 0 を確認したら `<facts_ref>/facts.yml`（`shared/references/facts-schema.md` 準拠の9分類構造）と `common_docs_root` 配下のプロジェクト共通文書だけを情報源として読み込む。**対象リポジトリの原本コードは Read しない**（設計原則4）。

完了条件: 必須引数が揃い、画面ディレクトリの構造健全性を確認済み・`seal-facts.sh verify` が exit 0・facts.yml と共通文書の読込完了

## Phase 2: facts → 業務語彙への転記（章ごとに実施）

facts.yml の各セクションを下記マップに従って基本設計書の各章へ転記する。facts.yml の実際のセクションキー（`shared/references/facts-schema.md` 準拠）は import / export_type / const / state / handler / jsx / style / api / measurement_pending の9分類であり、基本設計書が使うのはこのうち業務挙動に直結する4分類（state / handler / jsx / api）と meta.route のみである。import / export_type / const / style / measurement_pending（実装寄り・実測系の5分類）は基本設計書に転記しない（詳細設計書の担当）。

| facts.yml セクション | 基本設計書の章 | 変換規則 |
|---|---|---|
| handler | §2 機能仕様 | 業務動作に翻訳する（例: `onClick` ハンドラ → 「ボタン押下時の処理」） |
| jsx | §1 画面の目的 | 業務目的に翻訳する（画面が「何を見せるか」を業務の言葉で書く） |
| api | §4 入出力の業務的意味 | 業務目的に翻訳する（「何のデータをやり取りするか」を業務の言葉で書く） |
| state | §3 業務ルール | 業務的な制約・条件に翻訳する（実装の条件式ではなく業務の言葉で書く） |
| meta.route（+ common_docs_root の共通設計書） | §5 画面遷移の業務文脈 | 共通設計書の遷移情報を参照引用する |

各章のキー（意味キー規約準拠）は facts.yml のキーをそのまま流用せず、業務語彙で章ごとに新規に付け直す（例: `handler-onRowClick-遷移` → §2 の機能キー `一覧行選択-詳細遷移`）。facts.yml に該当分類の事実が無い場合は「該当なし」＋根拠（例:「該当なし（facts.yml の api セクションに項目なし）」）を記す。

完了条件: テンプレートの5章（§1〜§5）すべてに記述がある（「該当なし」＋根拠を含む）

## Phase 3: 実装用語混入検査

生成した画面基本設計書.md 全文に対し、コード識別子・フレームワーク用語・型構文・ファイルパス・ライブラリ名の混入を grep で検査する。

```bash
grep -nE 'useState|useEffect|useReducer|\bProps\b|styled-components|\bReact\b|\bVue\b|\bAngular\b|interface [A-Z]|: *(string|number|boolean)\b|/[A-Za-z0-9_-]+\.(tsx|ts|jsx|js|css)\b' <画面基本設計書.md>
```

検出0件で完了とする。1件でも検出された場合は、該当箇所を業務語彙へ書き直してから Phase 3 を再実行する（Phase 2 の転記自体は既に完了しているため、書き直しは検出箇所のみに限定し Phase 2 全体はやり直さない）。

完了条件: 実装用語検出0件

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 必須引数が揃い、画面ディレクトリの構造健全性を確認済み・`seal-facts.sh verify` が exit 0・facts.yml と共通文書の読込完了 |
| Phase 2 | テンプレートの5章（§1〜§5）すべてに記述がある（「該当なし」＋根拠を含む） |
| Phase 3 | 実装用語検出0件 |
| **Goal** | `status=基本設計著述完了` の返却ブロックが検証記録に保存済み。裸の「未確認」ゼロ |

## ループ設計

Phase 3（実装用語混入検査）で実装用語が検出された場合、該当箇所を業務語彙へ書き直して Phase 3 を再実行する。

| 要素 | 内容 |
|---|---|
| 反復条件 | grep 検査で実装用語が1件でも検出されたら、該当箇所を書き直して Phase 3 を再実行する |
| 上限回数 | 3回 |
| 停止条件 | 収束停止: grep 検出0件 ／ リソース上限: 3回到達（未収束の場合は `status=基本設計著述失敗` として呼び出し元へ差し戻す） |
| Phase 1ゲートとの違い | Phase 1 の封印検証失敗（exit 1）はこのループの対象外。即 `status=基本設計著述失敗` の終端条件 |

facts 読込・執筆（Phase 1〜2）はサブエージェントへ委任しない。本スキルは原本非アクセスの執筆役であり、業務語彙の一貫性を保つため単一のメインエージェントが通しで担う。

## 返却ブロック

契約正本 `orchestrating-reverse-docs-flow/references/contract.md` の共通サブセット（status/scope/artifacts/hint）に準拠する。

| キー | 値 |
|---|---|
| status | `基本設計著述完了`（著述完了）\| `基本設計著述失敗`（facts 未封印・unit_kind 未実装・実装用語混入が上限内で解消しない等で著述不能） |
| scope | `<system>-<画面ID>`（工程を跨いだ同一性キー） |
| artifacts | 画面基本設計書のパス |
| facts_ref（拡張） | 入力で受け取った facts ディレクトリの絶対パスをそのまま転記（下流工程への追跡用） |
| hint | 次工程（generating-reverse-detailed-design 起動）への申し送り・差し戻し理由 |

## 予想を裏切る挙動

- 入力は封印済み facts であり、原本コードは直接読まない。コードから事実を抽出するのは extracting-unit-facts-from-code の責務
- 詳細設計書は参照しない。基本設計書は facts から独立して業務語彙で直接書く（詳細設計の劣化版・要約版ではない）
- chapter_map_path・audit_script_path は受け取らない。基本設計書は5章固定のテンプレートであり、章役割キーの解決も15章監査（audit-consistency.sh）も不要。本スキル独自の Phase 3 grep 検査で完結する
- unit_kind は受け取るが screen 以外は未実装。batch/report/external の基本設計書テンプレートが存在しないため、無理に screen 用テンプレートを流用しない
- facts.yml の import / export_type / const / style / measurement_pending（実装寄り・実測系の5分類）は基本設計書に一切転記しない。転記対象は state / handler / jsx / api / meta.route の5分類のみ
- 本 SKILL.md 本文にリバース対象の固有値（対象リポジトリパス・画面 ID・業務名）を書かない
- 進捗は Step 単位で TaskCreate/TaskUpdate する（一括登録しない）

## 完了報告

`managing-agent-configs/references/skills/completion-report-format.md` の共通骨格（作業報告型）に従う。

固有の検証行:
- 実装用語検出結果（grep 0件 / N件）
- 5章（§1〜§5）の記述充足状況

## 参照資料

本スキルは orchestrating-reverse-docs-flow の契約（`references/contract.md`）に準拠し、args 全量指定で単独起動できる。

- 起動引数 scaffold_script_path（Phase 1 スキャフォールディング。実体: `shared/scripts/scaffold-screen.sh`。正本はこの1本のみ）
- 起動引数 facts_ref（封印済み facts ディレクトリの絶対パス。実体: extracting-unit-facts-from-code が出力する `<screen_dir>/検証記録/facts/<run_id>/`）
- 起動引数 common_docs_root（プロジェクト共通文書ルートの絶対パス。実体: generating-reverse-common-docs が採録する `プロジェクト共通/`）
- 起動引数 template_root（テンプレート原本。実体: `shared/templates/リバース検証`）
- `shared/references/facts-schema.md` — facts.yml のスキーマ正本（9 分類・必須フィールド・正規化規則）
- `shared/templates/リバース検証/画面/基本設計/画面基本設計書.md` — 基本設計書テンプレート正本（5章固定）
