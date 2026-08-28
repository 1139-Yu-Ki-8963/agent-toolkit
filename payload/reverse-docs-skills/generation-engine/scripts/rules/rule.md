# 規約定義・派生生成スクリプトの設計判断

`generation-engine/scripts/rules/` 配下のスクリプトの定義ドキュメント。設計の定義は
`delivery-payload/references/規約定義と派生生成の設計.md`。本ファイルは
新規のシェルスクリプトには設計判断の記載が要るという要求に応えるための
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
`EXPECTED_KEYS` と `delivery-payload/references/規約定義と派生生成の設計.md` の 3 節を同時に
更新する。

**廃棄条件**: 規約定義と派生生成の設計自体を廃止した時、または `docs/rules/` の
取り込みスキル（`importing-rule-proposals`、未実装）が検査を内包するようになった時。

### build-derived-rules.sh

**必要性**: `docs/rules/` から `.claude/`・`.cursor/`・`AGENTS.md`・hooks 登録の
4 種の派生物を生成する変換（設計 5 節・6 節）は、鍵ごとの写像規則が種類ごとに異なり
（配置パス組み立て・front matter 変換・索引マーカー差し替え・JSON/TOML への
hooks 登録）、決定的な生成結果を毎回保証する必要がある。dry-run を既定にして
`--apply` なしでは書き込まない安全弁も、都度の Bash 直叩きでは保証できない。

2026-08-11 に 5 種目の派生物として MCP サーバー設定（`<docs/rules root>/mcp-servers.json`
= McpCanon から `.mcp.json` の `mcpServers` キーと `.codex/config.toml` の
`[mcp_servers.*]` ブロックを生成）を追加した。改善課題「Codex設定-未生成」「MCP設定-未生成」
（このリポジトリ自身の開発構想文書が定めた「`.codex/` の範囲: 初期は MCP サーバー設定」
「`.mcp.json` と `.codex/config.toml` は McpCanon という中間表現を経て相互変換する」）への対応。
既知の限界: Codex 向け TOML 変換は stdio 型のみ対応し、remote(http/url) 型は変換対象外として
stderr へ列挙する（Codex の remote MCP サーバーの TOML 表現を本リポジトリの参照範囲内で
確認できなかったため）。`.mcp.json` 側は stdio・remote の両方を変換する。
`mcp-servers.json` が不在の場合は生成をスキップする（hooks が初期 0 個でも配管だけ敷くという
構想の決定と同型）。

**代替案を採用しなかった理由**:
- Bash ツール直叩き: 4 種の派生物それぞれの変換規則を対話のたびに手動再現すると、
  生成結果の決定性（同じ入力で同じ出力）を保証できない
- 既存 Makefile ターゲット拡張: このリポジトリに Makefile は存在せず、新規導入は
  本チェック専用の依存を増やすだけになる
- package.json scripts 追加: 同様に、このリポジトリはビルド設定を持たない

**保守責任者**: 人手（ユーザー）。変換規則（設計 5 節の表）を変更する場合は本
スクリプトと `delivery-payload/references/規約定義と派生生成の設計.md` を同時に更新する。

**廃棄条件**: 規約定義と派生生成の設計自体を廃止した時、または取り込み・適用の
両納品スキル（`importing-rule-proposals` / `syncing-derived-artifacts`、いずれも
未実装）がこの変換ロジックを内包するようになった時。

### check-rule-drift.sh

**必要性**: `build-derived-rules.sh --apply` が丸ごと生成する派生物（`.claude/rules/**/rule.md`・
`.cursor/rules/*.mdc`）は、生成後に手作業で編集されると定義との対応が壊れたまま気付けない。
台帳は持たない。台帳は状態をファイルへ持つ仕組みであり、記録と現物がずれたときにどちらが正か
を決められない。毎回その場で `docs/rules/` の定義から一時ディレクトリへ生成し直し、出力先
リポジトリの現物と内容を突き合わせる方式にすることで、`docs/rules/` が唯一の正になる。
判定は `diff -q` によるファイル内容の突合で行い、記録・更新時刻は使わない（`git checkout` や
別ツールでも時刻は動くため）。生成経路（`build-derived-rules.sh` 実行後の確認）と納品先での
状態確認の両方から同じ判定を呼ぶため、判定を 1 本のスクリプトへ集約する必要がある。

**代替案を採用しなかった理由**:
- Bash ツール直叩き: 一時ディレクトリへの再生成と現物との突合という複数段の処理を、
  生成経路・確認経路の両方から対話のたびに手動再現すると判定基準が経路ごとにずれる
- 台帳方式（ハッシュを記録して以後の突合に使う）: 記録と現物がずれたときにどちらが正かを
  台帳自身では決められず、記録の更新漏れが新たな不整合源になる。`docs/rules/` を毎回読み直す
  再生成突合であれば、定義そのものが常に唯一の正であり続ける
- 既存 Makefile ターゲット拡張: このリポジトリに Makefile は存在せず、新規導入は本チェック
  専用の依存を増やすだけになる
- package.json scripts 追加: 同様に、このリポジトリはビルド設定を持たない

**保守責任者**: 人手（ユーザー）。突合対象パターン（丸ごと生成されるファイルの種類）を
増減する場合は本スクリプトの `list_targets` と `delivery-payload/references/規約定義と派生生成の設計.md`
の 6 節を同時に更新する。

**廃棄条件**: 規約定義と派生生成の設計自体を廃止した時、または適用納品スキル
（`syncing-derived-artifacts`、未実装）がずれ検知を内包するようになった時。

### scaffold-rule-definitions.sh

**必要性**: まっさらな対象リポジトリへ規約定義一式（親 7・子 27）を配る処理は、
`delivery-payload/references/rule-taxonomy.json` の宣言から `docs/rules/<親>/<子>/rule.md`
（front matter 13 鍵の空雛形）・`parent.yml`・`design-notes.md` を機械的に組み立て、
`toolDefined: true` を宣言する子だけ
本文入りで作り分ける必要がある。既存 rule.md を上書きしない保護、dry-run 既定、
`--deploy-rule-scripts`（`build-derived-rules.sh` を呼ぶだけで重複実装しない）の各条件を
毎回手動で満たすのは非現実的であり、CLI から繰り返し・決定的に呼べるスクリプトが要る。
あわせて、実装フローのゲートが
必須とする `.claude/rules/always/project-context/flow-values.yml`・`rule.md` の
2 ファイルも、生成経路がどのスキルにも存在しなかった（改修課題「実装フロー定義-誰も
生成しない」）。規約定義を配る本スクリプトが同じ既存保護（`write_if_new`）の枠組みで
配るのが、新規スクリプトを増やさない最小差分の解決である。

**代替案を採用しなかった理由**:
- Bash ツール直叩き: 親 7・子 27・toolDefined の作り分け・既存保護・dry-run
  という複数段の分岐を対話のたびに手動再現すると、生成結果の決定性を保証できない
- 既存 Makefile ターゲット拡張: このリポジトリに Makefile は存在せず、新規導入は
  本チェック専用の依存を増やすだけになる
- package.json scripts 追加: 同様に、このリポジトリはビルド設定を持たない
- `build-derived-rules.sh` への機能追加: あちらは `docs/rules/` からの派生生成
  （定義 → 各ツール形式）が関心であり、定義そのものの初期配置（rule-taxonomy.json
  → docs/rules/）とは生成の方向・入力が異なる

**保守責任者**: 人手（ユーザー）。`rule-taxonomy.json` の親・子構成を変更する場合は
本スクリプトの既定値組み立て処理と `delivery-payload/references/規約定義と派生生成の設計.md`
を同時に更新する。

**廃棄条件**: 規約定義と派生生成の設計自体を廃止した時、または取り込みスキル
（`importing-rule-proposals`、未実装）が新規リポジトリへの初期配置を内包する
ようになった時。

**節単位の上書き（2026-08-18改修、対象プロジェクトの実態を反映させる指示書.md 3.1）**:
当初の実装は `toolDefined: true` の子カテゴリの rule.md を、既存の有無によらず
常にファイル単位で上書きしていた。これは「ツール側が本文を定める規約は他経路の
本文で上書きされてはならない」という改善課題1-48の要求を満たす一方、
`toolDefined: true` の rule.md が持つ「このプロジェクトの規則」節（雛形自身が
現場に書き込みを促す唯一の節）まで含めて毎回消してしまう副作用を持っていた
（実測: 対象26本で表のデータ行が115行から26行へ減少）。`merge_project_rule_section` /
`is_placeholder_project_rule_section` を追加し、上書きの単位をファイルから
「このプロジェクトの規則」節だけへ下げた。既存の当該節がプレースホルダ1行
（ラベルが 未解析／対象なし／（未記入）のいずれか）だけならツールの本文で上書きし、
現場が書き足した内容を持つ場合はその内容を保持する。

**既知の限界（プレースホルダ判定はラベルのみで行う）**: `is_placeholder_project_rule_section`
は行の最初の列（ラベル）だけを見て判定する。現場がラベルを `未解析` のまま残して
説明文だけを書き換えた場合、その説明文は現場の内容として保護されず、次の再実行で
ツールの本文へ上書きされる（この挙動はケース17が意図して固定している）。ラベルまで
含めて判定を厳密化する（例: 行全体がテンプレートの既定文言と完全一致するかで見る）
選択肢もあったが、`決めていないこと 1`（節の単位で上書きする実装の方法）の範囲内で
担当者が選んだ簡潔な実装であり、ラベルを書き換えずに本文を書く運用を前提とする。

**macOS標準awkの制約（`-v` への複数行文字列割り当て不可）**: 上記2関数の実装時、
生成した本文中の節を既存内容へ差し替える処理を `awk -v repl="<複数行文字列>"` で
書いたところ、macOS標準の `awk`（one-true-awk。GNU awkではない）が
`awk: newline in string ... at source line 1` で構文エラーになることを検出した。
`-v` は値に埋め込まれた改行を許さない（gawkなら通る）。この環境依存の落とし穴を
踏まないよう、`merge_project_rule_section` は `awk -v` を使わず、行番号を求めて
`head`/`tail` で継ぎ合わせる方式にした。また同関数は command substitution
（`$(...)`）が末尾の改行をすべて剥がす性質により、既存の節が末尾に持っていた
空行の数を正確には復元できない（既知の制約）。次の見出しへ続く場合は空行数に
依存せず常に1行だけ空行を入れて区切る（全テンプレートの書式と同じ規約）ことで、
空行の喪失（表の最終行と次の見出しが接着する不具合）を回避している
（ケース18が固定で検査する）。

### rule-scope-overrides.sh

**必要性**: 対象プロジェクトの実態を反映させる指示書.md 3.3 は「適用範囲（scope・paths）に
対象側の受け口を設ける」ことを求める。当初 `scaffold-rule-definitions.sh` は前付けの
scope・paths を `rule-taxonomy.json`（触らない対象）の既定値から直接読むだけで、対象
プロジェクト固有の値（実在するディレクトリへ合わせた paths 等）を宣言する受け口が無く、
配置を再実行するたびに既定値へ戻っていた（実測: 対象26本すべて）。`output-layout.sh` と
同じ「対象側の宣言ファイルを読み、キー単位で合成する」形式（`resolve_*`/`*_get` の対）を
再利用し、`docs/rules/rule-scope-overrides.json` を宣言の受け口とした。scope・paths の
組み合わせの妥当性検査（scoped は paths 必須・空配列禁止、always は paths 省略時に
既定 `["**/*"]` を補う、scope 値域の検査）を持ち、`resolve_output_layout` と対称な
構造で毎回の `run_scaffold` 呼び出しにつき1回だけ解決するため、繰り返し・決定的に
呼べるスクリプトへ切り出す必要があった。`rule-scope-overrides` という語は本スクリプトの
ファイル名・関数名（`resolve_rule_scope_overrides`・`rule_scope_override_get`）・
自己テストの対象名として一貫して使う。

**代替案を採用しなかった理由**:
- Bash ツール直叩き: scope・paths の組み合わせ妥当性検査（scoped/always の分岐・
  空配列禁止・既定値補完）を対話のたびに手動再現すると、判定基準がぶれる
- `output-layout.sh` への機能追加: あちらは生成物の出力配置パス（日本語パス）の
  宣言解決のみを担い、規約の適用範囲（front matter の scope・paths）という
  異なるドメインの宣言を混ぜると単一責任が崩れる。両者は形式（対象側宣言ファイル
  の読み込み・キー単位合成）だけを共有し、宣言の中身・妥当性検査は別物である
- `rule-taxonomy.json` への上書き機構の直接組み込み: 同ファイルは「触らない範囲」
  （対象プロジェクトの実態を反映させる指示書.md 5節）に明記されており、変更できない
- 既存 Makefile ターゲット拡張・package.json scripts 追加: このリポジトリはどちらも持たない

**保守責任者**: 人手（ユーザー）。宣言ファイルのスキーマ（`specVersion`・`overrides.<key>.scope`・
`overrides.<key>.paths` の値域）を変更する場合は本スクリプトと本節と self-test を同時に更新する。

**廃棄条件**: 規約定義と派生生成の設計自体を廃止した時、または適用範囲の対象側宣言を
`rule-taxonomy.json` 側の機構（触らない範囲の見直しを含む）に統合した時。

## 関連

- `delivery-payload/references/規約定義と派生生成の設計.md` — 変換規則・検査規則の設計定義
- `delivery-payload/references/rule-taxonomy.json` — scaffold-rule-definitions.sh が読む親7・子27の宣言
- `generation-engine/samples/docs/rules/agent-operations/ai-behavior/`・`generation-engine/samples/docs/rules/code-standards/naming/` — 取り込み済み（`status: approved` / `origin: proposal`）の実例。他の子カテゴリは scaffold-rule-definitions.sh が配る空雛形のまま

**additionalChildren（改善課題1-286）**: 同じ宣言ファイルは `additionalChildren` を持てる。形は
`{"<親キー>": [{"key": "<ケバブケース>", "title": "<表示名>", "summary": "<要約>"}]}` で、
親キーごとに子を任意個足す。`rule_additional_children_get <解決済みJSON> <親キー>` が
1行1件の JSON（`toolDefined:false`・`projectDefined:true`・既定 `scope:"always"`・
`paths:["**/*"]` を補ったもの）を返し、`scaffold-rule-definitions.sh` が taxonomy の子と
同列に合流させる。足した子の雛形は `status: draft` で配置され、`validate-rule-definitions.sh`
の検査が同じように働く。子の数を親7件・子27件に固定しない。

