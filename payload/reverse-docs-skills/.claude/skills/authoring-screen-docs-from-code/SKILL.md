---
name: authoring-screen-docs-from-code
description: "元コードを読解し画面詳細設計書・DESIGN.mdを著述するリバース著者役。 TRIGGER when: リバース設計書の新規著述、元コードからの設計書ブートストラップ、宣言的契約事実表の作成。 SKIP: 盲検の往復検証（→rebuilding-screen-unit-from-docs）、環境同期・基準タグ（→syncing-reverse-env）。"
invocation: authoring-screen-docs-from-code
type: orchestration
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Agent]
---

# 元コードからのリバース設計書著述スキル

元コードを読解し、リバース設計書（画面詳細設計書・DESIGN.md・単体テスト観点表）を「元コード水準の網羅性」で著述する著者役スキル。本スキルは体系内で唯一「**対象ファイルの原本を読むことが正当**」な工程である。リバース設計書とは原本から書くものであり、盲検（原本読解の禁止）が必要なのは検証スキル rebuilding-screen-unit-from-docs の生成役だけである。

ただし著述は「**宣言的契約への正規化**」であり、コード行の字面転記（コードブロック丸写し）は禁止する（例外: テンプレート §15.2 の typescript 型ブロックはテンプレート様式として許可）。字面転記禁止の境界例は `references/phase-details.md` を参照する。

## 目的

著者役と検証役は情報アクセス規律が正反対である。著者役は原本を読むのが仕事であり、検証役は原本を読んだら測定が無効になる。両者を同居させると「検証役の規律を著者役に誤適用して設計書がスカスカのまま収束宣言される」事故が起きる。本スキルは著者役を独立させ、原本読解を正当な工程として引き受ける。

## 使用タイミング

- リバース設計書を元コードから新規著述したいとき・from-code で設計書の記載粒度をブートストラップしたいとき
- 本スキルが `status=AUTHORED` を返した後に検証スキル rebuilding-screen-unit-from-docs を起動する（著述 → 盲検往復検証の順）
- 検証スキルが `差し戻し`（設計書に対象契約なし）を返した場合の差し戻し先は本スキルである
- 起動引数は screen_dir + 資産パス群 + mode（+ mode=file 時は target_file_path）

## スコープ（2 モード）

- **mode=file**: 1 起動 = 1 ファイル。対象ファイルの宣言的契約を該当章へ著述する
- **mode=screen**: 画面横断章（§1 画面概要・§2 機能一覧・§4 業務ルール・§12 画面遷移・§13 非機能要件・§14 共通仕様準拠）と画面構成の統合（§3 画面構造・§9 領域別仕様）を著述する。mode=file が**全対象ファイル分完了した後**に実行する

## 設計原則

1. **正本一元化**: 事実表（fact-table.md）は監査証跡であり第二の正本ではない。正は設計書。設計書と事実表が食い違ったら設計書を直す
2. **「該当なし」に根拠を必須とする**（例:「該当なし（事実表にイベント項目なし）」）。根拠なしの裸の「未確認」は完了条件違反
3. **プロジェクト非依存**: リバース対象の固有値（対象リポジトリパス・画面 ID・BL 名）はすべて起動引数・設計書側に置き、本 SKILL.md 本文には書かない。完成後に固有文字列ゼロを確認する（環境名の直書き禁止規約にも整合させる）
4. **検証スキルとの関係を明記**: 上記「使用タイミング」の通り、AUTHORED 後に検証スキルを起動し、検証 差し戻し の差し戻し先は本スキルである

## Phase 1: preflight（起動引数検収・スキャフォールディング）

起動引数を検収する: screen_dir / docs_root / template_root / chapter_map_path / audit_script_path / target_repo_path / target_branch / source_ref / mode / target_file_path（mode=file 時）。補助情報源（スクリーンショット dir・レジストリ値）があれば受け取る。いずれか必須引数が欠ける場合は起動不可として呼び出し元へ差し戻す。

画面ディレクトリが未存在の場合、本スキルがスキャフォールディングを実施する: `scripts/scaffold-screen.sh <docs_root> <画面ID> [<画面名>]`。既存の場合は `scripts/scaffold-screen.sh --verify <docs_root> <画面ID>` で構造の健全性を確認し、exit 1 なら template_root 起点の原本から欠落ファイルのみ復元して再実行する（fail-closed）。

完了条件: 必須引数が揃い、画面ディレクトリの構造健全性を確認済み

## Phase 2: 原本読解（宣言的契約事実表の作成）

対象の原本を読解し、9 分類の「宣言的契約事実表」を `<screen_dir>/検証記録/著述-<対象>/<timestamp>/fact-table.md` に作成する。9 分類（①import ②export・型 ③定数 ④状態変数 ⑤イベントハンドラ ⑥JSX 構造 ⑦スタイル実測値 ⑧API 呼出 ⑨実測系）の抽出粒度・キーの付け方・節構成テンプレートは `references/phase-details.md` を参照する。

各分類は「該当なし」でも根拠付きで節を残す。表の 1 列目は意味キー（連番禁止・内容要約キー）とし、これが Phase 5 の転記突合の識別子になる。

完了条件: 事実表が 9 分類すべての節を持ち（該当なし節も根拠付きで残す）作成済み

## Phase 3: 観点表追記

事実表から単体テスト観点表へ観点行を追記する（意味キー規約: 連番禁止・内容要約キー）。⑨実測系に由来する観点は `[画面単位検証で実測]` として留保する。

完了条件: 事実表由来の観点行が観点表に追記済み・意味キー規約準拠

## Phase 4: 設計書転記

事実表を下記マップに従って各章へ転記する。⑨実測系は転記せず、該当章に `[画面単位検証で実測]` プレースホルダを残し、返却ブロックの `measurement_pending[]` に一覧化する。判定条件付きの詳細は `references/phase-details.md` を参照する。

| 事実表分類 | 転記先 |
|---|---|
| ①import | §15.3（依存） |
| ②export・型 | §15.1（ファイル分割）/ §15.2（型定義） |
| ③定数 | §10（定数・設定値） |
| ④状態変数 | §5（状態管理） |
| ⑤イベントハンドラ | §8（イベント処理） |
| ⑥JSX 構造 | §3（画面構造）/ §9（領域別仕様） |
| ⑦スタイル実測値 | DESIGN.md + §3.6/§15.6 のキー参照 |
| ⑧API 呼出 | §7（API 通信仕様） |
| ⑨実測系 | 転記せず `[画面単位検証で実測]` + measurement_pending |

章の役割キー → §番号の解決は起動引数 chapter_map_path を正本とする。§番号は既定値であり、設計書の章マップ表で解決する。

完了条件: 転記完了・⑨が `[画面単位検証で実測]` として留保済み

## Phase 5: 完全性ゲート

1. `scripts/check-fact-coverage.sh <fact-table.md> <画面詳細設計書.md> [<DESIGN.md>]` を実行し exit 0 を確認する。事実表の全行（⑨除く）が設計書いずれかの章に転記済みかを機械突合し、未転記が 1 行でもあれば exit 1（fail-closed）。未転記キーを Phase 4 のマップに従って転記してから再実行する
2. 起動引数 audit_script_path（`shared/scripts/audit-consistency.sh`）を通常モードで実行し、内部整合性の違反が 0 件であることを確認する

完了条件: `check-fact-coverage.sh` が exit 0 かつ `audit-consistency.sh` 違反 0 件

## Phase 6: 返却

返却ブロックを検証記録に保存する（下記「返却ブロック」を参照）。

完了条件: `status=AUTHORED` の返却ブロックが検証記録に保存済み

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 必須引数が揃い、画面ディレクトリの構造健全性を確認済み |
| Phase 2 | 事実表が 9 分類すべての節を持ち（該当なし節も根拠付きで残す）作成済み |
| Phase 3 | 事実表由来の観点行が観点表に追記済み・意味キー規約準拠 |
| Phase 4 | 転記完了・⑨が `[画面単位検証で実測]` として留保済み |
| Phase 5 | `check-fact-coverage.sh` が exit 0 かつ `audit-consistency.sh` 違反 0 件 |
| Phase 6 | `status=AUTHORED` の返却ブロックが検証記録に保存済み |
| **Goal** | 裸の「未確認」ゼロ（残ってよいのは `[画面単位検証で実測]` と §16 起票済みのみ） |

## ループ設計

Phase 5（完全性ゲート）で未転記キーが検出された場合、Phase 4 へ差し戻して転記を補い、Phase 5 を再実行する。

| 要素 | 内容 |
|---|---|
| 反復条件 | `check-fact-coverage.sh` が未転記キーを検出（exit 1）したら、Phase 4 で転記を補い Phase 5 を再実行する |
| 上限回数 | 5 回 |
| 停止条件 | 収束停止: `check-fact-coverage.sh` exit 0 かつ `audit-consistency.sh` 違反 0 件 ／ リソース上限: 5 回到達（未収束の場合は BLOCKED として呼び出し元へ差し戻す） |

原本読解（Phase 2）はサブエージェントへ委任しない。本スキルはカンニング防止が不要な著者役であり、対象ファイルの原本を読むことが正当な唯一の工程はメインエージェント自身が担う（検証スキルのカンニング防止層 2 とは異なる設計）。

## 返却ブロック

契約正本 `orchestrating-reverse-docs-flow/references/contract.md` の共通サブセット（status/scope/artifacts/hint）に準拠する。

| キー | 値 |
|---|---|
| status | `AUTHORED`（著述完了）\| `BLOCKED`（原本不在・引数不足等で著述不能） |
| scope | `<system>-<画面ID>`（工程を跨いだ同一性キー） |
| artifacts | 画面詳細設計書・DESIGN.md・単体テスト観点表・fact-table.md のパス |
| measurement_pending | ⑨実測系として設計書に確定せず画面単位検証へ委譲した項目の一覧（拡張フィールド） |
| hint | 次工程（検証スキル起動）への申し送り・差し戻し理由 |

## Gotchas

- 原本の字面転記（コードブロック丸写し）は禁止。宣言的契約への正規化として書く（境界例は `references/phase-details.md`）
- ⑨実測系（初期表示値・DOM 順・要素位置・レイアウト）を目視転記・推測で確定しない。`[画面単位検証で実測]` に留め measurement_pending へ回す
- 「該当なし」は必ず根拠を添える。裸の「未確認」は完了条件違反
- 本 SKILL.md 本文にリバース対象の固有値（対象リポジトリパス・画面 ID・BL 名）を書かない。固有値は起動引数・設計書側に置く
- 進捗は Step 単位で TaskCreate/TaskUpdate する（一括登録しない）

## 設計判断

### check-fact-coverage.sh

**必要性**: 事実表の全行が設計書に転記されたかの網羅を機械ゲート化する必要がある。著述の完了条件は「裸の未確認ゼロ」であり、転記漏れを目視確認に頼ると from-zero でスカスカの設計書が収束宣言される事故（本スキル分離の動機そのもの）を防げない。事実表の意味キー集合と設計書本文の言及を突合し、未転記が 1 件でもあれば exit 1 とすることで Phase 5 の完全性ゲートに組み込む。⑨実測系を除外する分岐・意味キー抽出・自己テストという複数分岐があり、Bash 直叩きでは再現性が失われる。

**代替案を採用しなかった理由**:
- Bash 直叩き: 意味キー抽出・⑨除外・comm 突合を都度手書きすると抽出条件がぶれ、転記漏れの見逃しを誘発する
- 既存 Makefile ターゲット拡張: このリポジトリに Makefile がない
- package.json scripts 追加: スキル用途でありプロジェクトの package.json に属さない

**保守責任者**: 人手（ユーザー）。fact-table.md の書式・除外分類を変更した時に更新する。

**廃棄条件**: 本スキル廃止時、または転記突合が別の網羅計測に統合された時。

### scaffold-screen.sh（rebuilding-screen-unit-from-docs からの複製）

**必要性**: 画面ディレクトリのスキャフォールディングは、設計書を新規著述する著者役こそが本来の担い手である。従来 rebuilding-screen-unit-from-docs が持っていた `scaffold-screen.sh` の保守正本を本スキルへ移管し、著者役が Phase 1 で自律的にテンプレート展開できるようにする。スクリプトは template_root（引数指定 or 既定値）からのコピー・プレースホルダ置換・staging 経由の原子的配置・--verify/--dry-run の 3 モードを持ち、Bash 直叩きでは再現性がない。

**代替案を採用しなかった理由**:
- Bash 直叩き: テンプレートコピー・sed 置換・相対パス補正・staging mv を都度手書きすると部分生成物の混入を招く
- 既存 Makefile ターゲット拡張: このリポジトリに Makefile がない
- package.json scripts 追加: スキル用途でありプロジェクトの package.json に属さない

**保守責任者**: 人手（ユーザー）。テンプレート構造の変更時に更新する。rebuilding-screen-unit-from-docs 側の複製元は別セッションで削除し、以後の保守正本は本スキル側とする。

**廃棄条件**: 本スキル廃止時、またはスキャフォールディングがテンプレートエンジンに統合された時。

## 参照資料

本スキルは orchestrating-reverse-docs-flow の契約（`references/contract.md`）に準拠し、args 全量指定で単独起動できる。

- `references/phase-details.md` — 9 分類の抽出粒度・Phase 4 転記マップの判定条件・字面転記禁止の境界例・fact-table.md の節構成テンプレート
- `scripts/check-fact-coverage.sh` — Phase 5 完全性ゲート（事実表 → 設計書の転記突合。`--self-test` 内蔵）
- `scripts/scaffold-screen.sh` — Phase 1 スキャフォールディング（テンプレート展開・--verify・--dry-run）
- 起動引数 chapter_map_path（章役割キー対応表。実体: `shared/references/chapter-map.md`）
- 起動引数 audit_script_path（内部整合性監査。実体: `shared/scripts/audit-consistency.sh`）
- 起動引数 template_root（テンプレート原本。実体: `shared/templates/リバース検証`）
