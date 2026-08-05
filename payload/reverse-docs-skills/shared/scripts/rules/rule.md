# 規約定義・派生生成スクリプトの設計判断

`shared/scripts/rules/` 配下のスクリプトの定義ドキュメント。設計の定義は
`shared/references/規約定義と派生生成の設計.md`。本ファイルは
`~/.claude/rules/scoped/tooling/shell/rule.md` が新規 `.sh` 作成時に要求する
ADR（設計判断）の記載場所として、スクリプトと同じディレクトリに置く。

## 設計判断

### validate-rule-definitions.sh

**必要性**: `docs/rules/<親>/<子>/rule.md` の front matter 13 鍵の必須・値域検査と、
設計 9 節が定める 6 検査（鍵-対応整合・検査-テスト同伴・適用範囲-必須・階層-一致・
矯正-矛盾なし・派生-未承認除外）は、フォルダ横断（`matched-formatter` 値の突合）と
ファイル実在確認（checker・test ファイル）を伴う。手動確認では毎回同じ 6 種の判定を
目視で繰り返すことになりトークンを浪費し、`build-derived-rules.sh` からも起動時
検査として呼ばれるため、CLI から繰り返し呼べるスクリプトである必要がある。

**代替案を採用しなかった理由**:
- Bash ツール直叩き: front matter 解析・6 検査・横断突合という複数段の分岐を、
  対話のたびに手動再現するのは非現実的
- 既存 Makefile ターゲット拡張: このリポジトリに Makefile は存在せず、新規導入は
  本チェック専用の依存を増やすだけになる
- package.json scripts 追加: 同様に、このリポジトリはビルド設定を持たない

**保守責任者**: 人手（ユーザー）。front matter の鍵を増減する場合は本スクリプトの
`EXPECTED_KEYS` と `shared/references/規約定義と派生生成の設計.md` の 3 節を同時に
更新する。

**廃棄条件**: 規約定義と派生生成の設計自体を廃止した時、または `docs/rules/` の
取り込みスキル（`importing-rule-proposals`、未実装）が検査を内包するようになった時。

### build-derived-rules.sh

**必要性**: `docs/rules/` から `.claude/`・`.cursor/`・`AGENTS.md`・hooks 登録の
4 種の派生物を生成する変換（設計 5 節・6 節）は、鍵ごとの写像規則が種類ごとに異なり
（配置パス組み立て・front matter 変換・索引マーカー差し替え・JSON/TOML への
hooks 登録）、決定的な生成結果を毎回保証する必要がある。dry-run を既定にして
`--apply` なしでは書き込まない安全弁も、都度の Bash 直叩きでは保証できない。

**代替案を採用しなかった理由**:
- Bash ツール直叩き: 4 種の派生物それぞれの変換規則を対話のたびに手動再現すると、
  生成結果の決定性（同じ入力で同じ出力）を保証できない
- 既存 Makefile ターゲット拡張: このリポジトリに Makefile は存在せず、新規導入は
  本チェック専用の依存を増やすだけになる
- package.json scripts 追加: 同様に、このリポジトリはビルド設定を持たない

**保守責任者**: 人手（ユーザー）。変換規則（設計 5 節の表）を変更する場合は本
スクリプトと `shared/references/規約定義と派生生成の設計.md` を同時に更新する。

**廃棄条件**: 規約定義と派生生成の設計自体を廃止した時、または取り込み・適用の
両納品スキル（`importing-rule-proposals` / `syncing-derived-artifacts`、いずれも
未実装）がこの変換ロジックを内包するようになった時。

### check-rule-drift.sh

**必要性**: `build-derived-rules.sh --apply` が丸ごと生成する派生物（`.claude/rules/**/rule.md`・
`.cursor/rules/*.mdc`）は、生成後に手作業で編集されると定義との対応が壊れたまま気付けない。
生成時にハッシュを台帳（`derived-rule-fingerprints.json`）へ記録し、以後の突合で MODIFIED と
DELETED を検知する必要がある。`build-derived-rules.sh` の実行直後の記録と、納品先での状態確認
（`status` コマンド）の 2 経路から同じ判定を呼ぶため、判定を 1 本のスクリプトへ集約する必要が
ある。判定はハッシュだけで行い、更新時刻は使わない（`git checkout` や別ツールでも時刻は動く
ため）。

**代替案を採用しなかった理由**:
- Bash ツール直叩き: 台帳の記録（`record`）と突合（`status`）の 2 コマンドを、生成経路・
  確認経路の両方から同一のハッシュ判定で呼ぶ必要があり、対話のたびに手動再現すると判定基準が
  経路ごとにずれる
- 既存 Makefile ターゲット拡張: このリポジトリに Makefile は存在せず、新規導入は本チェック
  専用の依存を増やすだけになる
- package.json scripts 追加: 同様に、このリポジトリはビルド設定を持たない

**保守責任者**: 人手（ユーザー）。台帳の対象パターン（丸ごと生成されるファイルの種類）を
増減する場合は本スクリプトの `list_targets` と `shared/references/規約定義と派生生成の設計.md`
の 6 節を同時に更新する。

**廃棄条件**: 規約定義と派生生成の設計自体を廃止した時、または適用納品スキル
（`syncing-derived-artifacts`、未実装）がずれ検知を内包するようになった時。

### scaffold-rule-definitions.sh

**必要性**: まっさらな対象リポジトリへ規約定義一式（親 7・子 27）を配る処理は、
`shared/references/rule-taxonomy.json` の宣言から `docs/rules/<親>/<子>/rule.md`
（front matter 13 鍵の空雛形）・`parent.yml`・`design-notes.md` を機械的に組み立て、
`toolDefined: true` の 2 件（`ai-config-asset-management`・`portal-maintenance`）だけ
本文入りで作り分ける必要がある。既存 rule.md を上書きしない保護、dry-run 既定、
`--deploy-tooling`（`build-derived-rules.sh` を呼ぶだけで重複実装しない）の各条件を
毎回手動で満たすのは非現実的であり、CLI から繰り返し・決定的に呼べるスクリプトが要る。

**代替案を採用しなかった理由**:
- Bash ツール直叩き: 親 7・子 27・toolDefined 2 件の作り分け・既存保護・dry-run
  という複数段の分岐を対話のたびに手動再現すると、生成結果の決定性を保証できない
- 既存 Makefile ターゲット拡張: このリポジトリに Makefile は存在せず、新規導入は
  本チェック専用の依存を増やすだけになる
- package.json scripts 追加: 同様に、このリポジトリはビルド設定を持たない
- `build-derived-rules.sh` への機能追加: あちらは `docs/rules/` からの派生生成
  （定義 → 各ツール形式）が関心であり、定義そのものの初期配置（rule-taxonomy.json
  → docs/rules/）とは生成の方向・入力が異なる

**保守責任者**: 人手（ユーザー）。`rule-taxonomy.json` の親・子構成を変更する場合は
本スクリプトの既定値組み立て処理と `shared/references/規約定義と派生生成の設計.md`
を同時に更新する。

**廃棄条件**: 規約定義と派生生成の設計自体を廃止した時、または取り込みスキル
（`importing-rule-proposals`、未実装）が新規リポジトリへの初期配置を内包する
ようになった時。

## 関連

- `shared/references/規約定義と派生生成の設計.md` — 変換規則・検査規則の設計定義
- `shared/references/rule-taxonomy.json` — scaffold-rule-definitions.sh が読む親7・子27の宣言
- `shared/samples/規約定義/docs/rules/` — 入力形式の実例
