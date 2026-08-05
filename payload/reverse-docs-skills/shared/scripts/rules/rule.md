# 規約定義・派生生成スクリプトの設計判断

`shared/scripts/rules/` 配下のスクリプトの定義ドキュメント。設計正本は
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

## 関連

- `shared/references/規約定義と派生生成の設計.md` — 変換規則・検査規則の設計正本
- `shared/samples/規約定義/docs/rules/` — 入力形式の実例
