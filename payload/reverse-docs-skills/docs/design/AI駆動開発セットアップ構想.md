# AI駆動開発セットアップツール群への転換構想

## この文書の扱い

この文書は公開同期の対象外である。同期対象は agent-toolkit の `scripts/sync-manifest.json` が定める。このリポジトリについては次の 5 つに限定されている。

- `.claude/skills`
- `shared`
- `README.md`
- `docs/guides/reverse-docs-overview.html`
- `RUNBOOK.md`

同期はこの列挙に載ったパスだけを対象とする仕組みであり、リポジトリ直下の新規 `.md` は対象に入らない。除外設定の追加は不要である。公開完遂ガード（`.claude/rules/always/publish/complete/rule.md`）の比較対象にも入らない。

## 用語

本構想で「定義」と呼ぶのは、AI が読む唯一の生成元である Markdown と根拠画像を指す。派生物はすべて定義から生成し、逆向きの生成はしない。

コミット値については 3 つの系統を区別する。混同すると保守の対象を取り違える。

| 呼び名 | 実体 | 置き場 |
|---|---|---|
| 原本のコミット値 | 設計書と facts が持つ `source_ref`（66 箇所） | 画面詳細設計書の先頭、`facts.yml` |
| 基準タグ | `reverse-baseline/<scope>` というタグの名前と、その有無を示す状態（`baseline_tag`、40 箇所） | git のタグ |
| 表示コミット | 設計書frontmatterの`source_ref`集計。画面ページは画面固有値 | ポータルのサイドバーとフッター |

`sourceRef`（370 箇所）は字面が近いが別概念である。証跡のファイルパスと行番号を指す。統一の対象に含めない。

## 何を変えるか

`reverse-docs-skills` の役割を「既存コードから設計書をリバースするスキル群」から「AI駆動開発のセットアップを行うツール群」へ広げる。リバースは 3 つの役割のうちの 1 つに縮む。

| 役割 | 入力 | 出力 |
|---|---|---|
| セットアップ | 対象リポジトリ（コードの有無を問わない） | AI が読む定義、各 AI ツールの設定フォルダ、人間向けポータル |
| リバース | 既存コード | 定義への事実の書き込みと、そこから導出される設計書、一覧、ポータル |
| 保守 | 生成済みの定義と派生物 | 定義と派生物のずれの検知と再生成 |

統括スキル 1 本がセットアップとリバースとポータル生成のすべてを扱う。保守は別スキルとして枝分かれさせ、統括経由と単独起動のどちらでも呼べる形にする。

## なぜ変えるか

コードを持たないリポジトリと画面を持たないリポジトリが、入口から辿れない。各 AI ツール（Claude Code、Cursor、Codex）の設定フォルダを生成する手段がない。生成済みの HTML を仕組みを知らない人が直接編集すると、定義との対応が壊れたまま気付けない。

## 確定した決定

調査を経て次の 22 点を確定した。根拠は各工程の節と「派生アダプターの整合設計」の節に記す。

| 決定 | 内容 |
|---|---|
| 統括スキルの新しい名前 | `orchestrating-ai-development-setup` |
| 各 AI ツール設定の持ち方 | symlink と形式変換の併用 |
| `.codex/` の範囲 | 初期は MCP サーバー設定。規約と指示は `AGENTS.md` へ集める。hooks は定義が増えた時の自動反映先に含める |
| hooks の提供 | 初期 0。`docs/rules/` に規約と検査を置けば、適用操作により各ツール形式へ自動反映される配管を最初から敷く |
| 片側編集の検知 | フィンガープリント台帳と検査スクリプト 1 本。判定に更新時刻は使わない |
| 画面カードの見せ方 | 選べない状態で表示する |
| 画面 0 件の扱い | 他 5 種別と同型にして工程を続ける |
| 非機能要件と業務要件 | 空の雛形だけを置く |
| 規約の中身 | 2026-08-14 時点で、全 27 カテゴリを本文入りで納品する。本文は役割と方針の水準に留め、対象リポジトリ固有の規則は「このプロジェクトの規則」の節が受ける。コードからの観測は規約提案として別に出力し、取り込みの判断を経てこの節へ入る |
| 規約提案の取り込み | 取り込みの判断は現場のエンジニアが行う。取り込み操作のスキルを納品物に含め、対象リポジトリ側へ配る |
| 納品スキルの構成 | `syncing-derived-artifacts`（状態表示と適用と復旧の 3 モード）、`importing-rule-proposals` の 2 本。全モードで同一セットを納品する（2026-08-11 時点の決定。当初案にあった `enabling-new-units` は、配布経路 `scaffold-rule-definitions.sh` の配布対象名がこの2本で確定済みのため現行スコープに含めない） |
| 納品スキルの位置づけ | 実体は `.claude/skills/` に置き、docs 側には索引と保守手順書を置く。ツール群から見れば派生物であり、再納品で上書きされる。手作業の編集はずれ検知の対象に含める |
| スキルテストの文書化 | スキルごとに `references/test-cases.md` を持ち、観点の表と機械検証（self-test 等）の対応を文書として管理する |
| 最初の適用先 | 画面ありと画面なしの両方。モノレポではサブプロジェクト単位で分かれる |
| 規約提案の出力先 | リポジトリ外。起動時に外部パスの指定を必須とし、既定値を持たない。リポジトリ内のパスは拒否する。リバースの検証記録と同じ思想 |
| 提案のポータル非反映 | 観測由来の規範候補をスキルが `project-portal/` へ直接書くことを禁止する。ポータルに載るのは、取り込み後に定義から生成された内容だけ |
| 用語辞書の扱い | 用語の観測は規約提案（用語の追加候補）として外部へ出力する。承認済みの用語定義だけが `docs/rules/business-domain/glossary/` に載る |
| このリポジトリの再編 | `docs/` を新設し、説明と設計と台帳を集約する。検証系は `generation-engine/scripts/tests/` へ集約する（第 2 波）。`shared/` 自体の階層と機械が読む定義（unit-axes 等）とスキルのガイド HTML は動かさない（相対参照 208 箇所とスキルの自己完結を壊さないため） |
| 用語集の仕組み | `docs/guides/用語集.md` を説明 HTML 群の用語の単一情報源とする。種別は技術用語と AI 用語とドメイン用語の 3 区分。語を減らすことが先で、残る語だけを載せる。ガイドのパネルとの同期はずれ検知の対象 |
| 検証出力の外部化 | プロジェクト内に `verification/` を作らない。facts と比較ログと作業記録等は、作成前に外部の保存先を対話で確認する。確認できなければ `OUTPUT_PATH_REQUIRED` で停止する（従前の「docs と同階層に verification/」の決定を上書き） |
| docs 直下の許可 | 納品先の `docs/` 直下は `rules/` と `screens/` と `common/` の 3 つだけを許可する |
| 設計図の配置 | 画面遷移図と ER 図と状態遷移図はポータルの一覧カテゴリへ統合する |

## 現状の実測

`docs/guides/reverse-docs-overview.html` の §1.1「これは何か」節は、物理配置を 3 層に分ける方針を既に定めている。AI が読む Markdown と根拠画像を置く `docs/`、人間向け HTML を置く `project-portal/`、各 AI ツールが定義へ到達するための派生アダプターである。

実装は追いついていない。実測値は次のとおり。

| 測定対象 | 実測値 | 意味 |
|---|---|---|
| `generation-engine/scripts/` と各スキル `scripts/` における日本語パス片の出現数 | 197 箇所 | パスは宣言から解決されず生成スクリプトへ直書きされている |
| 上記が出現するファイル数 | 26 件（`generation-engine/scripts/` 配下 23 件、スキルの `scripts/` 配下 3 件） | 置き換えの対象範囲 |
| 異なりパスパターン数 | 53 件 | 宣言の鍵の上限 |
| うち本番経路のパターン数 | 17 件 | 宣言の鍵の実数。残りは自己テストのフィクスチャ |
| `project-portal` を参照するファイル数 | 5 件 | 目標配置がほぼ未実装 |
| `docs/rules` を参照するファイル数 | 2 件 | 同上 |
| 統括スキル名の参照元ファイル数 | 74 件 | 改称の追従先の量 |

上表は 2026-08-01 の時点の値である。測定中に別セッションの作業が `generation-engine/scripts/build-portal.sh` を変更してマージされたため、マージ後に再測定して同一値であることを確認した。着手時には改めて測り直す。実施後の 2026-08-10 に測り直したところ、`project-portal` を参照するファイルは 13 件、`docs/rules` を参照するファイルは 9 件である。

統括スキルの契約は `.claude/skills/orchestrating-ai-development-setup/references/contract.md` にある。着手前にそこが示していた実際の配置は 3 つであった。`<output_dir>/一覧/` と `<output_dir>/プロジェクト共通/` と `<verification_dir>/` である。目標の配置は当時、文書化済みで未実装であった。現在は `delivery-payload/references/output-layout.json` の宣言経由へ移行済みである。

## どう変えるか

### 採用する方針: 定義層を先に 1 度だけ確定する

挙がった要望は、いずれも「何が定義で、何がそこから導出される派生物か」に行き着く。各 AI ツールの設定フォルダ生成は定義を指す派生アダプターを作る作業である。`docs/` 中心の連動は定義の物理位置を決める作業である。画面名と表示コミットの保守は、派生物が定義からずれたことを検知する作業である。画面を持たないポータルは、定義が空である場合の派生物の姿を決める作業である。

定義層を先に決めれば、残りは導出規則として書ける。並行して設計すると、同じ問いに対して互いに矛盾する答えが複数生まれる。

### 借用する仕組み

`DevsProtein/agents-sync` の実装を調べた。Claude Code と Codex に分かれた設定を 1 つにまとめ、以後ずれないよう同期するツールである。借用する点は 4 つ。

**同じ形式は symlink、違う形式は変換で扱う。** `src/targets/link.ts` が `ln -s` で相対パスの symlink を作る。対象は 2 組ある。

- `.agents/skills/<name>` から `../../.claude/skills/<name>`
- `AGENTS.md` から `CLAUDE.md`

一方で `.mcp.json` と `.codex/config.toml` は `McpCanon` という中間表現を経て相互変換する。hooks はコマンド文字列を `«REPO»` トークンへ正準化する。展開先は Claude 向けが `${CLAUDE_PROJECT_DIR}`、Codex 向けが `$(git rev-parse --show-toplevel)` である。

**symlink は版管理へそのまま載せられる。** README に明記がある。「git は symlink をモード `120000` の blob として記録します。そのまま版管理でき、clone や checkout で復元されます」という記述である。`.gitignore` への追加を推奨しているのはバックアップ置き場だけである。

**ずれの判定はハッシュで行い、更新時刻は使わない。** `src/lib/engine.ts` の `decide()` が前回同期時のフィンガープリントと現在値を比べ、両側が変わっていれば競合と判定する。コード中のコメントは「ファイルの更新時刻は git checkout や別ツールでも動くため信用しない」と述べ、時刻方式を明示的に不採用としている。

**操作は状態表示と適用と復旧に分ける。** `--apply` を付けない限り全コマンドがプレビュー表示に留まり、書き込みをしない。既存ファイルは無条件に上書きせず、`promote`（既存内容を定義側へ移してから symlink 化）、`replace`、`create` の 3 分岐で扱う。バックアップは `.agents-sync/backups/<runId>/` に 20 世代を保持する。

### 派生アダプターの整合設計

3 ツールの公式仕様を調べ、次の事実を確定した。

| 事実 | 根拠 |
|---|---|
| Cursor の rules は `.mdc` 拡張子と front matter が必須で、素の `.md` は無視される。必要な鍵は `description` と `globs` と `alwaysApply` | Cursor 公式ドキュメント（rules） |
| Cursor にも hook 機構がある。`beforeShellExecution` や `afterFileEdit` や `sessionStart` 等のイベントで任意スクリプトを実行できる | Cursor 公式ドキュメント（hooks） |
| Codex は `AGENTS.md` を各階層で探索して連結する（下位優先） | Codex 公式ドキュメント |
| Codex はリポジトリ単位の `.codex/config.toml` を読む。信頼されたプロジェクトではリポジトリ内 hooks も読む | Codex 公式ドキュメント。agents-sync の「AGENTS.md だけ」という記述は古い |
| MCP 設定は 3 ツールとも `mcpServers` 鍵で互換性が高い。ただし Claude Code だけリモートサーバーに `type` を必須とする | 両公式ドキュメントの突合 |

この事実に基づき、派生物を 3 層に分けて扱う。

| 層 | 対象 | 揃え方 | 片側編集の防ぎ方 |
|---|---|---|---|
| 同形式 | `AGENTS.md` 系、skills | symlink | 構造で防がれる。編集できる 2 つ目の実体が存在しない |
| 異形式 | MCP 設定、Cursor 向け rules（`.mdc` 生成）、hooks | 中間表現を経た生成 | フィンガープリント台帳との突合で検知する |
| 単側実効 | ツール固有の設定 | 定義側に実体を置き、他ツールへは索引だけ渡す | 生成物であることを示す印を検知する |

規約本文は当初 symlink 共有を想定したが、Cursor が素の `.md` を無視するため、Cursor 向けだけ第 2 層になる。front matter を付けて `.mdc` として生成する。本文は同一に保つ。

hooks は初期 0 で提供する。ただし配管は最初から敷く。後から `docs/rules/` に規約と検査スクリプト（linter 等）を置けば、適用の操作により各 AI ツールの形式へ自動で反映される。反映先は Claude Code の `settings.json` と Cursor の hooks と Codex の `.codex/` である。これはこの PC における agent-home と同じ思想である。定義は 1 箇所に置き、ツール別の形式は派生として生成する。

揃えるタイミングは 2 つの観測点に置く。生成時（統括スキルまたは保守スキルの適用操作）と、対象リポジトリのコミット時である。常駐監視は採らない。agents-sync の常駐は macOS 限定であり、すべての対象リポジトリへ常駐プロセスを要求できないためである。

片側編集の検知は、フィンガープリント台帳と検査スクリプト 1 本に集約する。適用のたびに各派生物のハッシュを台帳へ記録する。検査（状態表示の操作）が現在値と台帳を突合し、不一致を報告する。判定に更新時刻は使わない。git checkout や別ツールでも時刻は動くためである。この台帳と検査は Phase D の派生値ずれ検知と同一の機構であり、1 度作れば両方で使う。

機械強制の届く範囲には制約がある。Claude Code 利用者にはコミット時の hook で即時に検知が効く。他のエディタの利用者に clone した直後から効く強制は CI に限られる。CI を持たないリポジトリでは検査スクリプトの手動実行に留まる。この限界は解消できないため、明記して運用する。

### 検討したが採用しない方針

| 不採用の方針 | 不採用の理由 |
|---|---|
| 9 件の要望を個別のスキル追加として並行実装する | 各要望が「定義と派生物の関係」という同じ問いに依存する。並行すると互いに矛盾する答えが生まれる |
| `docs/` への物理移動とパス解決の宣言化を同時に行う | 26 ファイルの改修が失敗した際に、配置の誤りと参照方法の誤りを切り分けられない |
| 画面名の保守と表示コミットの保守を別スキルにする | どちらも「派生値が定義からずれた」という同一の状態である。仕組みが 2 つに分かれると検知漏れの経路も 2 つになる |
| 手作業で編集された HTML を後から修復する | 修復は編集を許す前提に立つ。手作業の編集が機械的に不合格と判定される状態を作るほうが検知漏れが起きない |
| 設定の持ち方を symlink か変換のどちらかに揃える | agents-sync は形式が同じものと違うもので使い分けている。片方に揃えると、形式変換が必要な MCP 設定か、複製の重複のどちらかを抱える |
| 規約本文を `.codex/` にも複製する | Codex は `AGENTS.md` の階層連結で規約へ到達できる。複製は同じ内容の 2 つ目の実体を作り、片側編集の穴を増やす |
| 機能詳細設計書をテンプレートの追加だけで済ませる | 当初はこの見積りを採ったが成立しない。Phase C に 3 つの欠落と、必要な 3 作業を示す |
| リポジトリ名を改称する | 持ち主の判断により対象外。公開先パス（`payload/reverse-docs-skills/`）の同期設定の変更を伴わない |

## 現在地（実装の進捗）

初見のセッションが完了済みの工程をやり直さないための進捗表である。2026-08-05時点の値である。

| 工程キー | 状態 | 実体 |
|---|---|---|
| 定義層-パス解決の間接化 | 完了 | `delivery-payload/references/output-layout.json`と`generation-engine/scripts/output-layout.sh`へ画面単位rootの`screenUnitRoot`を追加し、生成・集約・ポータル・再構築の利用側を追従した。既定値は`画面`を維持し、上書き値の衝突、制御文字・Unicode正規化、symlink経由のroot外参照を拒否する。専用E2Eと既存self-testで回帰を固定済み |
| 定義層-docs移行 | 完了 | 永続しない`workRecordDoc`と`sampleRecordDoc`をlayoutから除外し、共通文書ゲートを永続6文書へ限定した。規約4文書は存在時だけ補助検査し、サンプル記録はゲート対象外とした。`docs/`と`project-portal/`を物理分離し、アーキテクチャ調査書の移行先を`docs/design/common/`へ確定し、規約提案への置換を完了した |
| 規約-定義形式の確定 | 完了 | `delivery-payload/references/規約定義と派生生成の設計.md`が front matter 13鍵・判定結果JSONのスキーマ・3ツールへの変換規則・linterの配線・フォーマッタの合成・整合検査6項目を定める。規約フォルダには linter とその回帰テストを同居させ、検査できない規約には理由の明記を必須とする |
| 規約-コード系4種の空雛形化 | 完了 | テンプレート4枚を空雛形へ統一し、`generate-rules-from-common-docs.sh` を削除した。`check-common-docs.sh` の検査2（規則行完備性）と検査5（理想論表現）を撤去し、統括スキルの状態判定を共通6文書へ縮小した。観測は規約提案HTMLとして別途出力する経路が実装済みである |
| rules階層-親子の全面設計 | 完了 | `delivery-payload/references/rule-taxonomy.json`が親7子27を宣言し、`generation-engine/scripts/rules/scaffold-rule-definitions.sh`が空のリポジトリへ27枚の雛形と`parent.yml`を配る。`toolDefined`を宣言する子は本文入り、それ以外は空雛形とする |
| 規約-整合検査 | 完了 | `generation-engine/scripts/rules/validate-rule-definitions.sh`がfront matterの必須と値域、checkableとcheckerの対応、linterとテストの同伴、親宣言の実在を検査する |
| 一覧-画面0件の対称化 | 完了 | `generating-screen-list-for-reverse-docs`に「0件時の分岐」節とstatus=NONEを追加済み |
| コミット値-単一化 | 完了 | `build-portal.sh`が設計書frontmatterの`source_ref`集計で表示し、ページ個別値にも対応する。自己テストのケース34で固定済み |
| 保守-派生値ずれ検知 | 完了 | 規約の派生物は`generation-engine/scripts/rules/check-rule-drift.sh`が定義から一時ディレクトリへ生成し直し、内容を`diff`で突合する。対象は`.claude/rules`のrule.mdと`.cursor/rules`のmdcに限る。HTML向けの`generation-engine/scripts/check-derived-drift.sh`は従来どおり。画面名と表示コミットの値レベル突合は `generation-engine/scripts/check-derived-values.sh` が担う。台帳を持たず、定義から毎回導出して現在の表示値と突き合わせる |
| 品質-スキルテスト文書 | 完了 | 全スキルに`references/test-cases.md`を整備済み。スキル数は追加に伴って変わるため本文に固定値を書かず、`.claude/skills/`配下のディレクトリ数で確認する |
| 用語集の仕組み | 完了 | `docs/guides/用語集.md`（15語）。`generation-engine/scripts/check-glossary-sync.sh` が用語集とガイドの用語パネルを突き合わせ、ずれを検知する |
| このリポジトリの再編 | 完了 | `docs/`（説明と設計と台帳）と`generation-engine/scripts/tests/`（自己テスト22本）へ集約済み |
| アダプター-三ツール設定生成 | 完了 | `generation-engine/scripts/rules/build-derived-rules.sh`が`docs/rules/`から`.claude/rules/`・`.cursor/rules/*.mdc`・`AGENTS.md`の索引・3ツールのhooks登録を生成する。linterの実体は複製せず、3ツールが同じファイルを相対参照する |
| 規約-提案出力 | 完了 | `delivery-payload/templates/rule-proposal/`と`generation-engine/scripts/rule-proposal/build-rule-proposal.sh`が提案HTMLを決定的に生成する。`.claude/skills/generating-rule-proposals-for-reverse-docs/`が対象コードの観測から提案を起こす。出力先はリポジトリ外を必須とする |
| 納品-保守スキル同梱 | 完了 | `delivery-payload/templates/delivered-skills/`の2本（`importing-rule-proposals`・`syncing-derived-artifacts`）と、検証・生成・ずれ検知の道具3本を`scaffold-rule-definitions.sh --with-skills`が配る |
| 規約-3段の通し検証 | 完了 | 空のリポジトリへの納品から、提案生成・取り込み・派生生成・ずれ検知までを実走で確認した。取り込みで既存の空雛形が埋まり新規フォルダが増えないこと、hooks生成でlinterが複製されないことを実測した |
| 統括-改称 | 完了 | `.claude/skills/orchestrating-reverse-docs-flow/` を `orchestrating-ai-development-setup/` へ `git mv` で改称し、SKILL.md の `name`・`invocation` を追従させた。旧名を含む94ファイルのうち91ファイルを追従させ、過去の実績を記す `docs/ledgers/` 配下の3ファイルは当時の名称のままで残している |
| 統括-モード分岐、順序-初見者向け導線 | 完了 | `resolve-flow-mode.sh`が`setup-only`・`reverse-full`・`reverse-degraded`の3モードを機械判定し、self-testの6ケースが通過する。初見者向け導線は文脈を持たない読み手に3度読ませ、詰まり11点中10点を解消した |
| ポータル-画面なし縮退 | 完了 | `delivery-payload/references/portal-catalog.json` で `disabledWhenEmpty` を持つ種別は、対象リポジトリに実ファイルが 0 件でもカードを消さず、選べない状態で残す。`build-portal.sh --self-test` のケース38と、実描画で遷移しないことを確かめる `generation-engine/scripts/tests/test-portal-disabled-card-interaction.cjs` で固定した |
| 設計書-機能設計書 | 完了 | 機能設計書テンプレート（11章・単位非依存）を`delivery-payload/templates/リバース検証/機能/機能設計書.md`へ新設し、章の役割キーを`chapter-map.md`へ接頭辞付きで登録した。あわせてAPI一覧の調査項目へ非HTTP系の呼び出し境界（ビルド定義の生成ターゲットを主手段とする優先度表7段）を追加し、`kind`に`entrypoint`・`dispatch-entry`・`exported-function`を足した。機能一覧は画面該当なしの対象でも生成できるよう入力条件を緩和し、`strategy.screenPresence`と`strategy.boundarySource`を記録する。機能設計書を生成する `.claude/skills/generating-feature-design-for-reverse-docs/` を新設した |

推奨する着手順: Phase A・Phase B・Phase C・Phase D の項目はすべて完了している。次の着手先は「未解決の課題」節を参照する。

## 工程

工程の識別子は内容を要約した意味語で付ける。連番は付けない。

### Phase A: 定義層の確定

| キー | 内容 | 前提 |
|---|---|---|
| 定義層-パス解決の間接化 | 本番経路 17 パターンを宣言からの解決に置き換える。自己テストのフィクスチャは同じ宣言へ追従させる。この時点では物理配置を変えない | なし |
| 定義層-docs移行 | 定義を `docs/` へ、人間向け HTML を `project-portal/` へ移す。宣言の値の差し替えで済む状態にしてから実行する | 定義層-パス解決の間接化 |
| rules階層-親子の全面設計 | `docs/rules/` を親 7 と子 27 の 2 階層で構成する。全子にフォルダと rule.md を置く。2026-08-14 に全 27 子を本文入りへ移行した。日本語表示名は `project-portal/規約/` と完全一致で連動し、対応表を宣言に持ちずれ検知の対象とする | 定義層-docs移行 |

docs 移行の移行先と永続性を、共通文書 13 枚について確定した。判断の軸は「納品リポジトリへ永続的に残す情報か」である。

| 群 | ファイル | 永続性 | 移行先 |
|---|---|---|---|
| 調査 | アーキテクチャ調査書.md | 永続（再リバース時に更新） | `docs/common/` |
| 設計 | 共通設計書.md、基盤設計.md、データ設計.md、UI共通設計.md、DESIGN.md、メッセージ定義書.md | 永続 | `docs/common/` |
| 規約採録 | コーディング規約.md、命名規約.md、ディレクトリ構成規約.md、コンポーネント設計規約.md | 廃止（Markdown の採録をやめる） | 生成しない |
| 記録 | 作業記録.md、サンプル記録.md | 非永続（リバース作業の経過記録） | `verification/`（納品対象外、Phase A確定当時の決定。後述の注記参照） |

判断の根拠を 3 つ記す。調査書を永続とするのは、規約提案と各ページの証跡（sourceRef）が参照先として指しており、消すと証跡の実在検査が壊れるためである。規約採録の廃止は、確定済みの提案方式（規約は空雛形、観測は規約提案の HTML、取り込みは現場の判断）の帰結である。観測を Markdown と HTML の 2 箇所へ出すと、同じ内容の 2 つ目の実体が生まれ、片側編集の穴になる。記録の非永続化は、リバース作業の経過が対象プロジェクトの定義ではないためである。検証記録の置き場について、この Phase A 確定時点では「`verification/`（docs と同階層で納品対象外）を現状維持する」と判断した。この判断は後に「検証出力の外部化」の決定（「確定した決定」表を参照）で上書き済みである。現行の方針はプロジェクト内に `verification/` を作らず、作成前に外部の保存先を対話で確認し、確認できなければ停止する方式である。

この確定に伴う追従作業を「定義層-docs移行」の工程に含める。追従作業は 3 点である。`output-layout.json` の該当キー（workRecordDoc と sampleRecordDoc）を納品配置から除外する。`check-common-docs.sh` の必須ファイル一覧から規約 4 枚を除外する。共通文書の採録工程（規約 4 種）を提案出力へ置き換える。

宣言の実体を先に決めておく。新規に `delivery-payload/references/output-layout.json` を宣言として置き、`generation-engine/scripts/output-layout.sh` を共通関数として追加する。解決規則は既存の `generation-engine/scripts/unit-axes.sh`（433 行）に倣う。同スクリプトは `resolve_unit_axes`（120〜154 行）で解決し、`unit_axes_merge_files`（36〜49 行）が `jq -s` の reduce で合成する。探索先はリポジトリ既定と、全種別共通の上書きと、種別別の上書きの 3 階層である。

rules 階層は親 7 と子 27 の 2 階層で構成する。単体で意味の取れない名前を禁止した命名で、全ページが `project-portal/規約/` と 1 対 1 で連動する。

| 親（英語キー / 表示名） | 子（英語キー / 表示名） |
|---|---|
| agent-operations / AIエージェント運用 | ai-behavior / AIエージェント行動規約、destructive-operation-safety / 破壊的操作の安全規約、session-management / セッション管理規約、ai-config-asset-management / AI設定資産の管理規約、routine-operations / 定型運用の規約 |
| development-process / 開発プロセス | development-flow / 開発フロー規約、tools-and-commands / ツールとコマンド実行の規約、development-environment / 開発環境規約、git-operations / Git運用規約、release-and-delivery / リリースとデリバリーの規約 |
| code-standards / コード規約 | coding-style / コーディング規約、naming / 命名規約、directory-structure / ディレクトリ構成規約、component-architecture / コンポーネント設計規約 |
| quality-assurance / 品質保証 | test-policy / テスト方針書、review-checklist / レビュー方針書 |
| documentation-standards / 文書化規約 | document-writing / ドキュメント作成規約、portal-maintenance / ポータル保守規約 |
| non-functional-requirements / 非機能要件 | security / セキュリティ要件、performance / 性能要件、availability / 可用性要件、scalability / 拡張性要件、observability / 監視要件 |
| business-domain / 業務ドメイン規約 | glossary / 用語定義、business-rules / 業務規則、state-transitions / 状態遷移の制約、calculation-rules / 計算規則 |

旧設計からの主な変更を記す。既存 6 分類の並列維持をやめ、コード系 4 分類は code-standards の下へ、テストとレビューは quality-assurance の下へ入れる。セキュリティは非機能要件の子とする。コミュニケーションは廃止する（単体で対象を特定できず、中身は Git 運用規約とレビュー方針書に吸収されるため）。予約子分類の方式（物理ディレクトリを切らず rule.md 内の表で宣言）は廃止し、最初から全子のフォルダと空雛形を物理生成する。rule.md が実体になるため git の空ディレクトリ問題は起きない。

規約の出自は 2 区分とする。2026-08-14 以降、27 子すべてを本文入りで納品し、区分は本文の中の節で表す。プロジェクトが決める規約は「このプロジェクトの規則」の節が受け、ツールが定める運用規約（`rule-taxonomy.json` で `toolDefined` を宣言する子）は「規則」の節が持つ。前者の中身は 3 点である。ポータルと一覧 HTML は生成物であり直接編集しない。直すときは定義を直して再生成する。ずれは台帳の検査で検知する。後者の中身は 2 点である。docs が定義であり `.claude/` と `.cursor/` と `.codex/` は派生である。変更は docs 側から行い、適用操作で各ツールへ反映する。保守スキルはこの `toolDefined` の規約が定めた内容を実行する道具であり、規約が根拠、スキルが実行、台帳が検査という三点で閉じる。`toolDefined` を宣言する子はツール更新で再納品され、手作業の編集はずれ検知の対象に含める。

置き換えの規模は当初の見積りより小さい。異なりパスパターンは 53 件だが、本番経路は 17 件で、残りは自己テストのフィクスチャである。`build-portal.sh` の 64 件のうち本番は 1 件だけで、63 件が自己テストである。

可変部分の決定箇所は 2 つに集中している。ここを一本化する。

- `resolve-flow-state.sh` の 58〜66 行の `KIND_LABEL()` の case 文（screen から画面への対応をハードコードしている）
- `test-e2e-portal.sh` の 99 行の bash 配列リテラル（一覧種別 9 件を列挙している）

どちらも既存の `unit-axes.json` を参照していない。同宣言のトップレベルの鍵は `specVersion` と `axes` と `columns` の 3 つで、`appliesTo` は英語の種別キーだけを持ち、日本語ラベルやパスの宣言を持たない。よってラベルとパスの宣言は新規の `output-layout.json` 側に置く。

`generation-engine/scripts/render-template.sh`（51 行）は `{{KEY}}` の文字列置換だけを行い、パス解決を担っていない。宣言化はこの外側で行う。

テンプレート内に埋め込まれる相対リンクは、上記 197 件の範囲外である。対象は次の 3 群である。

- `delivery-payload/templates/unit-list/` 配下の 3 テンプレート
- `delivery-payload/templates/matrix/traceability-template.html`
- `delivery-payload/templates/リバース検証/画面/詳細設計/` 配下の 2 ファイル

これらは別途あわせて置き換える。

### Phase B: 入口の構えの変更

| キー | 内容 | 前提 |
|---|---|---|
| 統括-モード分岐 | 入口の機械判定とモードの分岐を統括スキルへ実装する。現行のリバース工程はリバースモードの下位に収める | Phase A |
| 統括-改称 | `orchestrating-ai-development-setup` へ改称し、参照元 74 ファイルを追従させる | 統括-モード分岐 |
| 順序-初見者向け導線 | 画面構築の手順を知らない利用者が入口から最後まで辿れることを実走で確認し、工程の順序と前提の記述を詰まった箇所に合わせて直す | 統括-モード分岐 |
| 品質-スキルテスト文書 | スキルごとの `references/test-cases.md` を新設し、既存スキル 39 件分を整備する。観点は意味語キーで書き、機械検証（self-test 等）との対応列を持つ | なし |

統括スキルの新しい名前は `orchestrating-ai-development-setup` に確定した。AI 駆動開発のセットアップという役割をそのまま名乗るためである。候補には `orchestrating-project-docs-setup` と `orchestrating-design-portal-setup` もあった。前者は文書整備が主だと読め、後者は成果物であるポータルが名前に出るが、いずれもセットアップという役割の広さを表せないため採らなかった。

旧名は着手直前の再実測で 94 ファイルに出現していた（当初は全体ガイドと README と契約と公開先の 4 種と見積もり、次いで 74 ファイルまで実測を進めたが、それでも足りないことが判明した）。実際に追従させたのは 91 ファイルで、残り 3 ファイル（`docs/ledgers/` 配下の記録）は過去の事実を述べる記述として旧名のまま残した。94 ファイルの内訳は次のとおり。

- 子スキルの `SKILL.md` が約 30 本
- 各スキルの guide HTML
- `generation-engine/scripts/check-runbook-presence.sh`
- `generation-engine/scripts/tests/test-python-facts-flow.sh`
- `generation-engine/scripts/tests/check-phase-step-structure.test.sh`
- `AGENTS.md` と `RUNBOOK.md` と `改善課題タスク一覧.md`
- `delivery-payload/references/リバース工程設計.md`

モードの判定は次のとおり。判定はサブプロジェクト単位でも行う。モノレポではバックエンドだけのサブプロジェクトがありうるため、リポジトリ全体で 1 つのモードに決めない。

| 判定 | モード | 動作 |
|---|---|---|
| コードなし、または設計書のみ | セットアップのみ | 各 AI ツールの設定フォルダと定義の骨組みを作り、ポータルは空のカードで作る |
| コードあり、画面あり | リバース全工程 | 現行の工程をそのまま実行する |
| コードあり、画面なし | リバース縮退 | 画面に依存する工程を飛ばし、画面カードは選べない状態で表示する |

判定に使える既存資産がある。`check-architecture-survey.sh` は 1178 行ある。同スクリプトの `check_project_form`（475〜540 行）は、プロジェクト形態を 2 値で判定する。値は「単独プロジェクト」と「モノレポ」である。同じスクリプトの `check_directory_coverage`（333〜472 行）は、対象リポジトリの実ファイル走査結果と文書の記述を突合する。サイト単位の扱いも既にある。`generating-cross-views-for-reverse-docs` は `sites_path` と `site_key` を引数に取る。

実在種別は `unit_kinds_present` で決まる。この値を返すのは `surveying-architecture-for-reverse-docs` である（同 `SKILL.md:145`）。対象外種別は `excluded-kinds.json` に記録される。形は `allKinds` と `presentKinds` と `excludedKinds` である。読むのは `resolve-flow-state.sh` の `check_list_ungenerated`（217〜233 行）である。この仕組みは構造上 screen も他の 5 種別と対称に扱える。

### Phase C: 出力の拡張

| キー | 内容 | 前提 |
|---|---|---|
| アダプター-三ツール設定生成 | `.claude/` と `.cursor/` と `.codex/` を、`docs/` の定義を指す派生として用意する。同じ形式は symlink、違う形式は変換で扱う。状態表示と適用と復旧の 3 操作に分ける | Phase A |
| ポータル-画面なし縮退 | 画面カードを選べない状態で表示する。カタログに有効と無効を表す鍵を新設し、ポータル規約へ観点キーを追加する | Phase A |
| 一覧-画面0件の対称化 | 画面 0 件のハード停止を、他 5 種別と同型の「該当なし」記録へ変える | なし |
| 設計書-機能設計書 | 機能単位の集約設計書を追加する。内訳は下記の 3 作業 | なし |
| 規約-提案出力 | コードから観測した実装慣行はリポジトリ外の指定先へ規約提案として出力し、提案 UI を設計する。用語候補は別契約のproposal YAMLとdiagnosticsだけを対象repo外へ出力する。旧 `generating-glossary-for-reverse-docs` の自動採録カードは削除する。用語辞書カードには、`managing-semantic-glossary` が承認済み意味用語YAMLだけを投影する。未承認候補をポータルへ混在させない | Phase A |
| 納品-保守スキル同梱 | 保守スキル 2 本（`syncing-derived-artifacts`、`importing-rule-proposals`）を対象リポジトリへ生成する（2026-08-11 時点、上記「納品スキルの構成」を参照）。あわせて、ずれ検知台帳の対象を HTML 以外の派生物（スキル本体、`AGENTS.md`、`.mdc`）へ広げる | アダプター-三ツール設定生成 |

規約の扱いの思想を記す。判定原則（コードから業務目的や規範を確定しない）を、記述の注意ではなく配置で保証する。`docs/rules/` の本文は役割と方針の水準に留め、対象リポジトリを観測して確定する具体は書かない（2026-08-14 に全 27 子を本文入りへ移行した）。コードから観測した実装慣行は規約提案という別の成果物へ出す。提案の出力先はリポジトリ外とする。起動時に外部パスの指定を必須とし、既定値を持たない。リポジトリ内のパスは拒否する。リバースの検証記録（verification）と同じ思想で、規範候補は納品物に混ぜない。スキルが観測由来の規範候補を `project-portal/` へ直接書くことも禁止する。ポータルに載るのは、現場が取り込みを判断して定義になった内容だけである。提案の UI は設計課題として工程に含める。最低要件は、対象規約（親と子）との対応、根拠（sourceRef）、取り込み手順の提示である。提案を規約へ昇格させる判断は現場のエンジニアに残す。取り込みスキルは納品物の一部として対象リポジトリへ配る。これにより「納品されるスキル」という成果物種別が新たに生まれる。取り込み後は適用操作により派生へ反映される。

納品する保守スキルの設計を確定した。構成は 2 本である（2026-08-11 時点。当初検討した `enabling-new-units`＝後から現れた画面や種別を対象範囲へ加え内部で適用へ委譲するスキルは、配布経路 `scaffold-rule-definitions.sh` の配布対象がこの2本で確定済みのため現行スコープに含めない）。`syncing-derived-artifacts` は状態表示と適用と復旧を 1 本で担い、モードは既定値なしの必須引数とする。`importing-rule-proposals` は規約提案の取り込みを担う。取り込み元はリポジトリ外の提案ファイルである。実体の置き場は `.claude/skills/` とし、docs 側には索引と保守手順書を置く。skills は Claude Code だけが持つ機構であり、片側実効の層の扱いに一致する。`docs/skills/` に実体を置いて symlink で参照させる案は採らない。Claude Code が symlink 経由で `SKILL.md` を読めるかが未検証で、読めない場合に無言で不発になるためである。Codex の利用者は `AGENTS.md` の保守索引から、Cursor の利用者は front matter を設定した `.mdc` から、同じ保守手順書と同じスクリプトへ到達する。納品スキルはツール群から見れば派生物である。ツール群の更新で再納品され、手作業の編集はずれ検知で検出する。再納品は上書き前にバックアップを取り、復旧で戻せる。

`.codex/` は MCP サーバー設定から始める。規約と指示は `AGENTS.md` へ集める。Codex は `AGENTS.md` を各階層で探索して連結するため、これで届く。当初は agents-sync のコードの記述を根拠に「Codex が読むのは `AGENTS.md` だけ」と判断した。しかし Codex 公式ドキュメントは、リポジトリ単位の `.codex/config.toml` の読み込みを明記している。信頼されたプロジェクトではリポジトリ内 hooks も読む。よって hooks の自動反映先として `.codex/` を使える。`.cursor/` は rules（`.mdc` 生成）と `mcp.json` と hooks を対象にする。

ポータルの縮退表示について、生成側は壊れないことを確認した。`portal-catalog.mjs`（331 行）の `renderCatalog`（191〜260 行）は出力ディレクトリを実走査し、カタログ宣言の glob と照合する。一致が 0 件ならそのカードを出さず、カテゴリ全体が 0 件なら「生成済み資料はありません」を設定する。`build-portal.sh`（2371 行）の 839〜855 行には、全ゼロのフィクスチャで空のカード表示を検証する自己テストがある。

したがって「選べない状態で表示する」には追加が必要になる。`portal-catalog.json` のトップレベルの鍵は `schemaVersion` と `categories` である。カード 1 件を表す blueprint の鍵は次の 10 個である。

- `kind`
- `label`
- `icon`
- `desc`
- `dir`
- `generator`
- `unit`
- `countFormat`
- `group`
- `discovery`

有効と無効を表す鍵は存在せず、カードの表示可否は実ファイルの有無だけで決まる。よって鍵の新設と、`.claude/rules/scoped/portal/page-conventions/rule.md` への観点キー追加をあわせて行う。

画面 0 件の扱いを対称化する。現状は `generating-screen-list-for-reverse-docs/SKILL.md:84` が 0 件でハード停止する（exit 3）。API とテーブルとバッチと帳票と外部連携の 5 種別は `一覧/<種別ラベル>一覧（該当なし）.md` を生成して工程を続ける。この非対称を解消し、画面も同型にする。画面の捏造を防ぐという現状の意図は、「該当なし」の記録に理由を残すことで保つ。

機能設計書の設計を改めた。当初は「機能詳細設計書」としてテンプレートの追加だけで足りると見積もったが、反証で 3 つの欠落が判明した。

1. `unit_kind` の契約列挙に機能がない。列挙は screen、batch、report、external の 4 つである（`generating-reverse-basic-design/SKILL.md:27`）
2. `generating-reverse-detailed-design` は `unit_kind` 引数を持たない。引数は screen_dir、facts_ref、mode 等である
3. 機能単位の facts を供給する経路がない。詳細設計は facts だけを情報源とし、原本の読み取りを禁じる。しかし facts 抽出は `profile=screen|python` のみ実装である。根拠は `extracting-unit-facts-from-code/SKILL.md`

この 3 点を踏まえ、facts 抽出への機能プロファイル追加を前提とする案は採らない。
機能は `feature-detection.md` が定めるとおり、コードから直接検出する単位ではなく既存一覧の派生グルーピングである。
機能に固有のファイル集合は存在せず、構成要素のファイル集合の和にしかならない。
よって機能プロファイルを足しても新しい事実は 1 件も生まれない。
必要なのは抽出器ではなく集約である。

したがって成果物を「機能詳細設計書」から、集約設計書としての「機能設計書」へ改める。
本工程は 3 つの作業を含む。
機能一覧マニフェストと構成要素の個別設計書から集約する機能設計書テンプレートの新設、章の役割キーの `chapter-map.md` への登録、画面を持たない対象でも機能一覧を生成できるようにする入力条件の緩和である。
`unit_kind` 列挙への追加と詳細設計スキルへの引数導入は、機能を詳細設計の対象としないため不要になる。

集約設計書は往復検証の対象にしない。
機能には対応する原本ファイルが存在せず、突合の相手がないためである。
品質は、構成要素の個別設計書が往復検証を通ることと、集約時の参照実在の検査で担保する。

### Phase D: 保守

| キー | 内容 | 前提 |
|---|---|---|
| コミット値-単一化 | 表示コミットの出所を 1 つに定め、設計書の `source_ref` と揃える | なし |
| 保守-派生値ずれ検知 | 定義から導出される値が手作業の編集でずれた状態を検知する。画面名と表示コミットの両方を同じ仕組みで扱う | コミット値-単一化 |
| 保守-再生成の入口 | ずれを検知した箇所を定義から再生成する操作を用意する | 保守-派生値ずれ検知 |

調査で分かった事実を先に記す。当初は「設計書の値と基準タグの値の一致を検査する」ことを最小の追加と見積もったが、前提が誤っていた。

**統一前の調査時点では、ポータルに表示されるコミット値は設計書の `source_ref` ではなかった。** 当時の `generation-engine/scripts/build-portal.sh` は、ポータル生成時に対象リポジトリの `git rev-parse --short HEAD` を都度取得し、設計書の `source_ref` は HTML に表示していなかった。

**現在は `source_ref` へ統一済みである。** ポータル全体の表示コミットは設計書frontmatterの`source_ref`を集計し、画面ページは画面固有の値を表示する。生成時の HEAD を直接読む経路は廃止済みである。

**比較の相手が実装されていない。** 基準タグを作る `git tag -af` は `syncing-reverse-env/SKILL.md:193` の手順記述だけで、スクリプト実装がない。同スキルの `scripts/audit-doc-consistency.sh`（349 行）にもタグ発行とコミット値の埋め込みはない。さらに、`SKILL.md:193` の例文にはコミット値が含まれていないのに、同スキルの guide HTML は「基準タグメッセージには検証時の `source_ref` を記録する」と説明している。記述の食い違いである。

**調査時点では表示コミットの値ずれ検知が未実装であった。** `validate-page-data.sh` の 515〜574 行（検査 7）が見る `sourceRef` は証跡のパスと行番号であり、コミット値ではない。`audit-consistency.sh` と `test-portal-conventions.sh` にも、表示コミットと`source_ref`の値レベル突合はなかった。現在は `generation-engine/scripts/check-derived-values.sh` が画面名と表示コミットの 2 つを検査する。

したがって次の作業は、統一済みの`source_ref`と表示値のずれを検知することである。判定には agents-sync と同じフィンガープリント方式を使い、ファイルの更新時刻は使わない。

検知の対象は 2 つに限定する。画面名は `screen-manifest.json` の値と、一覧 HTML および画面詳細ページの表示値の一致を検査する。表示コミットは設計書の `source_ref` との一致を検査する。

画面名については、画面一覧では既に仕組みが立っている。`generation-engine/scripts/unit-list/build-screen-list.sh` の 454 行に自己検査がある。「確定画面名は埋め込みマニフェストを単一表示源として再描画」という検査であり、表示はマニフェストから描き直される。検知の追加対象は画面詳細ページ側である。

統一の際に触らないものを明示する。`sourceRef`（370 箇所）は証跡のパスと行番号であり別概念のため、統一の対象外とする。`baseline_tag` と `baseline_tag_status` は統括スキルの契約が「改変しない」と定めた返却フィールド名のため、名前を変えない。`target_branch` はブランチ名であり無関係である。

既存の検査が同型の仕組みを既に持つ。よって新しい概念を導入せず、これらを拡張する。対象は次の 3 つ。

- `generation-engine/scripts/tests/test-portal-conventions.sh`
- `generation-engine/scripts/unit-list/validate-manifest.sh`
- `generation-engine/scripts/unit-list/check-manifest-persistence.sh`

横断検査スクリプトの置き場には先例がある。`generation-engine/scripts/audit-consistency.sh` は直下に置かれ、複数スキルの `SKILL.md` から `audit_script_path` として起動される。自己テスト系は `generation-engine/scripts/tests/` に集約され、スキルが実行時に呼ぶ検査は `generation-engine/scripts/` に残る。`generation-engine/scripts/unit-list/check-manifest-persistence.sh` はサブディレクトリに置かれ、7 種別の一覧フォルダを横断検査する。

Phase D は定義層の完了を前提としないが、Phase A と同じファイルを触る。次の 2 本が Phase A の置き換え対象にも含まれる。

- `generation-engine/scripts/tests/test-portal-conventions.sh`（該当箇所に `samples/一覧/API一覧/API一覧.html` の直書き）
- `generation-engine/scripts/tests/test-e2e-portal.sh`（該当箇所に `一覧/` の直書き）

よって Phase D と Phase A を同時には走らせず、着手順を先に決める。Phase D を先に着地させる場合、Phase A で同じファイルを再度触ることを見込む。

## 1 項目あたりの作業範囲

このリポジトリで「スキルを 1 つ追加する」は 1 ファイルでは終わらない。見積りは次の構成を前提とする。

| 構成要素 | 根拠 |
|---|---|
| `SKILL.md` | frontmatter に name、description（TRIGGER when と SKIP を含む）、invocation が必須 |
| `scripts/` | 機械検査と生成の実体 |
| `references/guide.html` | スキルガイド HTML 統一規約。メタテーブルは対応 OS、検証状況、依存、関連資料の 4 行のみ。§1 概要の直後に §2 出力を置く |
| 規約ファイル | 合格基準を機械強制する場合 |
| サンプルの再生成 | テンプレートを変更した場合、同じコミットにサンプルの変更を含める |

## 全 Phase 共通の完了条件

- 各 Phase の最初の作業として `generation-engine/scripts/tests/test-portal-conventions.sh` を実行し、失敗件数を記録する。この値を当該 Phase の完了判定の基準にする
- テンプレートを変更した場合、`generation-engine/samples/` のサンプルを同じコミットで再生成する。再生成しても差分が生じない場合はその事実を緊急口の理由文へ明記する
- 定義のコミット、`payload/reverse-docs-skills/` への同期、公開先の統合までを完了させる。手順の定義は `CLAUDE.md` と `RUNBOOK.md` である
- スキルを追加または変更した工程では、当該スキルの `references/test-cases.md` を同じコミットで更新する

## 触らない範囲

| 種別 | 対象 | 理由 |
|---|---|---|
| 共通処理 | `generation-engine/scripts/seal-facts.sh`、`generation-engine/scripts/audit-consistency.sh`、`generation-engine/scripts/canonicalize-facts-scalars.py` | facts の封印と監査の判定規則。定義層の移行はパスの解決先だけを変える |
| 共有コンポーネント | `delivery-payload/templates/partials/` 配下の共通シェルの見た目 | 見た目の刷新は本構想の対象外 |
| 共有スタイル | `delivery-payload/templates/tokens.css` のカラートークン値 | ポータル規約が旧値の再出現を不合格と判定する |
| 共有設定 | `.claude/rules/scoped/portal/page-conventions/rule.md` の既存観点キー、`delivery-payload/references/unit-axes.json` の既存宣言 | 追加のみ行う。既存の削除と緩和は検査の弱体化になる |
| 共有スクリプト | `generation-engine/scripts/render-template.sh` | 汎用の置換エンジン。パス解決の宣言化はこの外側で行う |
| 語彙 | `sourceRef`、`baseline_tag`、`baseline_tag_status`、`target_branch` | コミット値と別概念、またはスキル間契約が固定した名前 |

当初は `generation-engine/scripts/shell-injection.sh` も触らない範囲に挙げた。調査の結果、該当箇所の直書きは自己テストのフィクスチャであり生成物への埋め込みではないと判明した。ただし本番経路の置き換え対象に含まれるかは着手時に再確認する。

## 判断を要する事項

| 事項 | 選択肢 | 決め手 |
|---|---|---|
| Phase の着手順 | Phase A から順に進める ／ Phase D を先に着地させる | 重点項目（保守）をどれだけ早く手に入れたいか。どちらを選んでも検査スクリプト 2 本の二度触りが生じる |

## 実装前の明確化3点

1. symlinkの代替: Claude Code、Cursor、Codexのいずれかでsymlink経由の読み込みが実測で失敗した場合、その対象だけ実体生成へ切り替える。ずれ検知の台帳で同一性を守る。判断はPhase Cの着手時の実測で行う。
2. 納品スキルの初回形態: SKILL.mdとscriptsとreferencesを含む完全形態で対象リポジトリへ生成する。容器だけの配置はしない。ツール群から見れば派生物であり、再納品で上書きされる。
3. 取り込み後の反映の流れ: importing-rule-proposalsが承認分をdocs/rules/へ書き込む。続けてsyncing-derived-artifactsの適用がproject-portal/規約/と各AIツール形式を再生成する。この2段で提案からポータル反映までが閉じる。

## 未検証の事項

- 設定ファイルが symlink の場合に Cursor と Codex が追従するかは、両者の公式ドキュメントに記述がない。着手時に実測する
- Claude Code が symlink 経由で `SKILL.md` を読めるかも未検証である
- `.cursorrules`（Cursor の旧形式）が非推奨である旨の一次情報は見つからなかった。コミュニティの報告だけである
- `excluded-kinds.json` の `excludedKinds` に screen が記載された実例は見つからなかった。構造上は可能だが実例の証拠がない
- 直書き 197 件のうち 4 ファイルについて、本番経路と自己テストの区分が未確認である。対象は次の 4 件である
  - `check-overview-consistency.sh`
  - `check-screen-manifest-consistency.sh`
  - `prepare-screen-rebuild-sample-fixture.sh`
  - `validate-message-manifest.sh`
- agents-sync の `init` が既存の `CLAUDE.md` と `AGENTS.md` を上書きするか退避するかを直接示すコードは得られなかった
- 「並行して設計すると互いに矛盾する答えが生まれる」は反実仮想であり、一次情報での検証はできない

## 未解決の課題

配線もれの再配線が残っている。参照ゼロで孤立していた検査 3 本がある。対象は `check-portal-catalog.sh` と `test-screen-doc-markdown-renderer.cjs` の 2 本である。もう 1 本は `test-sequence-diagram-splitting.mjs` である。第 2 波で `generation-engine/scripts/tests/` へ整理した後、自己テストの束へ配線する。フォルダ構築とファイル移動までが本セッションの作業範囲であり、配線の追加は次の作業とする。

## 改善課題台帳との関係

台帳（`改善課題タスク一覧.md`）は 2026-08-16 時点で未解消の項目を持たない。過去に登録した 13 件はいずれも対応の記録を伴って残しており、うち 1 件は作業環境で再現できず、1 件は解消したものの実例で未確認である。今後追加される項目を先に列挙できないため、本構想は工程を固定列挙せず、追加項目が後から入る安定した工程の枠（Phase A から D）を与える形をとる。
