# 運転規約（RUNBOOK）

本リポジトリ（スキル群）を実行環境に配置し、無人モードで走行させるための運転規約。本ファイルは配布物の一部であり、実行環境ごとに複製して使う。

このスキル群が何をするものかは `README.md` に書いてある。初めて読む場合はそちらを先に読む。

文書で使う言葉の説明は `README.md` の「言葉」の節にある。

## 0. 前提環境

本リポジトリのスクリプト群を実行するには以下のツールが必要。

| ツール | 最低バージョン | 用途 | 不在時の挙動 |
|---|---|---|---|
| bash | 3.2 以上 | 全スクリプトの実行環境 | 実行不可 |
| jq | 1.5 以上 | code-metrics.json の構築・解析（build-portal.sh 等） | 実行不可（起動時にエラー終了） |
| node | 22.16 で動作確認 | 出力配置の解決・ポータルの組み立て・設計トークンとアイコンの抽出（output-layout.sh 等 14 本と .mjs / .cjs 17 本） | 実行不可。output-layout.sh の出力配置の解決が 6 種別すべて失敗し終了コード 1 で止まる。縮退する仕組みを持つのは 3 本のみで、残る 11 本は止まる |
| git | 2.0 以上 | 計測鮮度の算出・worktree 操作・コミットガード | 鮮度計算をスキップ。worktree 操作不可 |
| python3 | 3.6 以上 | 相対パス算出（build-portal.sh 内） | フォールバック値 `../docs` で動作するが、PORTAL_DIR と DOCS_ROOT の位置関係が異なる場合にリンク切れの可能性 |
| python3（`profile=python`限定） | 3.8 以上 | Python facts抽出・独立再計数 | AST終了位置が必須。抽出器・再計数器は3.7以下をexit 2で拒否する。既存screen経路の最低版は3.6のまま |
| python3.13 + venv（用語候補検証限定） | 3.13 系ちょうど | 用語候補（semantic glossary）のスキーマ検証（`validate-semantic-glossary.sh`／`generating-glossary-for-reverse-docs`が使用） | `.venv` 未構築・依存不足時は「required dependency is unavailable」等を明示してexit 2。3.13系以外のインタプリタも同様にexit 2で拒否する |

`node` の最低限必要な版は未検証である。22.16 での動作だけを確認している。

ブラウザを使う検査の実行環境（`node_modules`）も配布物に同梱しない。配布物は `package.json` を持たないため、`npm install` だけでは依存を用意できない。初回利用前に次の手順で構築する。

```bash
npm init -y
npm install --no-save playwright playwright-core
npx playwright install chromium
```

この手順を踏まない場合、次の2本は判定不能（終了コード2）となる。実行環境の制約であり、成果物の欠陥ではない。

- `generation-engine/scripts/tests/test-semantic-glossary-page.cjs`
- `generation-engine/scripts/tests/test-unit-list-format.cjs`

用語候補検証の実行環境（`.venv`）は配布物に同梱しない（`generation-engine/scripts/glossary/.gitignore` で除外）。初回利用前に次の手順で構築する。

```bash
cd generation-engine/scripts/glossary
python3.13 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

`GLOSSARY_PYTHON` 環境変数で別の Python 3.13 系インタプリタを指す場合も、同じ `requirements.txt`（PyYAML>=6,<7、jsonschema[format]>=4.23,<5）の依存が必須。`pip install` はネットワーク接続を要するため、ネットワーク制限下の実行環境では事前に許可を得てから実行する。

## 1. 推奨配置

- 検証専用フォルダ配下に `.claude/skills` を作り、本リポジトリのスキル群を配置または参照させる
- プロジェクトごとのサブフォルダを成果物ルート（docsの出力先）として分離する
- 例: `<検証専用フォルダ>/.claude/skills/`（本リポジトリのスキル一式）、`<検証専用フォルダ>/<プロジェクト名>/docs/`（成果物）

## 2. 起動規約

- 作業フォルダ（成果物ルートの親、`.claude/skills` が見える階層）を CWD にしてから起動する
- ヘッドレス CLI の起動オプションで設定読み込みをスキップするフラグを付けない。付けるとスキル発見が無効化され、本リポジトリのスキルが一切ロードされない
- リポジトリを bare 相当で扱うオプションも同様の理由で使わない

## 3. 安全柵（絶対厳守・逐語）

本節の禁止事項は、配布先で本スキル群を無人モードで走行させる実行側（実行環境）に向けたものである。このリポジトリ自身（reverse-docs-skills）を保守・改善する側には及ばない。改善側が従うべき規約は、リポジトリ直下の `CLAUDE.md` が定める公開完遂フローと公開完遂規約（このリポジトリ自身の規約。配布対象外）である。

- git push は絶対禁止
- 対象リポジトリの main ブランチへの直接操作は禁止
- コード検証用 worktree のうち、オリジナル系（変更前コードを保持する worktree）への commit は禁止
- リバース検証系（開通・検証作業用の worktree）への commit は許可するが、push は常に禁止
- 本リポジトリ（配布物）への書き込みは一切禁止。本リポジトリの更新は改善セッションの領分であり、実行側は指示書への起票のみを行い、実行側から本リポジトリへの直接反映（転写含む）はしない。同期は「指示書→改善セッション→本リポジトリ→実行側の配備先への取り込み」の一方通行のみ

## 4. 無人モード（headless実行）の実行規約

無人モードにおける安全規約の詳細な正本は、統括スキルの契約文書（`orchestrating-ai-development-setup/references/contract.md`）の「無人モード仕様」節である。本節はその要点のみを示す。

- 無人モードでは、いかなる工程でも Agent ツールのバックグラウンド起動（`run_in_background: true`）を使用しない。サブエージェントは同期（フォアグラウンド）起動に統一し、並列に処理したい場合は Skill ツールによる逐次実行へ切り替える。理由: headless実行では既定のバックグラウンド待機上限（`CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS`。既定600秒）でバックグラウンドプロセスが切断されることが実測されている
- 上記の禁止は無人モード限定であり、対話モードでの並列サブエージェント起動（バックグラウンド起動）まで禁止するものではない
- 専用のワーカー種別（固有名を持つサブエージェント）が実行環境に存在しない場合は、汎用エージェントにモデルを明示指定した上で代替起動してよい。この規定は無人モード限定ではなく、専用ワーカー種別が無い実行環境全般に適用される

## 5. コミット保護ガードのフック登録手順

本リポジトリに同梱するコミット保護ガードスクリプト（`generation-engine/scripts/check-worktree-commit-guard.sh`）を実行環境の PreToolUse（Bash 呼び出し前）に登録する。設定断片の例:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash <本リポジトリの配置パス>/generation-engine/scripts/check-worktree-commit-guard.sh"
          }
        ]
      }
    ]
  }
}
```

`<本リポジトリの配置パス>` は実行環境ごとの配置先（§1 推奨配置を参照）に置き換える。ガードスクリプト自体の許可・拒否判定はスクリプト本体の self-test を参照。

## 依存 agent-home スキル

orchestrating-ai-development-setup が Skill ツールで呼び出す agent-home スキル。公開完遂規約（このリポジトリ自身の規約。配布対象外）が定める main-未反映検査（コミット直後に自動発火する PostToolUse hook）で agent-toolkit の sync-manifest.json への登録有無を検査する。

| スキル名 |
|---|
| surveying-local-environment |
| counting-code-lines |

新しい agent-home スキルを追加した場合はこの表にも追記する。

## 依存 agent-home スクリプト（任意・環境変数で指定）

Skill ツールを介さず、agent-home 配下のスクリプトを直接実行する依存。同期定義（sync-manifest.json）への登録の対象ではなく、実行環境にそのスクリプトが在ることが前提になる。固定の絶対パスは本体に持たず、環境変数で指定する（このリポジトリ自身の自立の判定（配布対象外の検査）が、固定パスの直書きを実行マシン固有の依存として検出するため）。

| 呼び出し元 | 環境変数 | 呼び出す先（例） | 用途 |
|---|---|---|---|
| `generation-engine/scripts/rule-proposal/build-rule-proposal.sh` | `REVERSE_DOCS_RULE_PROPOSAL_VERIFY_SCRIPT` | `~/agent-home/skills/reviewing-explanatory-html/scripts/verify-html-static.mjs` | 生成した規約提案 HTML の静的検査 |

環境変数を未設定にした場合、または指すパスが不在の場合でも規約提案の生成そのものは通る。`build-rule-proposal.sh` の `run_static_verify()` が環境変数の未設定・スクリプトの不在を検出すると警告を標準エラーへ出すだけで、静的検査の段を飛ばして処理を続ける（exit しない）。

## 依存する実行環境の場所

Claude Code 自身が使う保存場所への依存であり、このスキル群が作る場所ではない。

| 場所 | 使う道具 | なぜ依存するか |
|---|---|---|
| `~/.claude/projects/` | `running-reverse-screen-batch`（無人バッチ） | `claude -p` が既定でセッション記録を書き込み続けるため、大量呼び出しで肥大化しディスクと起動時間へ影響する。`--no-session-persistence` で抑止する |

この場所は Claude Code が決めるものであり、実行環境によって異なりうる。

## 詳細ページの再生成

テンプレート（`delivery-payload/templates/detail-pages/` 配下）を更新した場合、既に生成済みの HTML ファイルは旧テンプレートのままになる。以下のコマンドで再生成する。

```bash
bash generation-engine/scripts/detail-pages/build-detail-page.sh <page-data.json> <output-dir> --page <kind>
```

| --page | 出力ファイル名 | 入力 JSON の pageKind |
|---|---|---|
| glossary | 用語辞書.html | glossary |
| techstack | 技術スタック.html | techstack |
| transition | 画面遷移図.html | transition |
| er | ER図.html | er |
| env | 環境構築手順.html | env |

`page-data.json` は各スキル（`generating-*-for-reverse-docs`）が生成する中間データであり、テンプレートとは独立して管理される。テンプレートのみ変更した場合は、同じ `page-data.json` を入力として再生成すれば更新が反映される。

## 機械検証の所要時間

第1層の機械検証（`generation-engine/scripts/verification/run-layer-machine-checks.sh`）は、引数なしで起動すると対象を自動で集めて最後まで走る。

```bash
bash generation-engine/scripts/verification/run-layer-machine-checks.sh
```

実測（コミット `645377f31c32532f95286fa9a4084331d01e3efa` 時点）では、対象132本・総ケース数1444件を、所要時間1819秒（約30分）で完走した。成功114本・失敗17本、打ち切り0本・途中停止の疑い0本だった（宣言済み長時間1本を含む）。既定の設定のまま完走しないと記録されていた状態は、1本あたりの時間上限が入ったことで解消している。待ち時間の目安は、この実測値（約30分）をそのまま使う。

失敗17本のうち、実行環境に依存して落ちるものが含まれる。実行した環境の問題か、検査そのものの問題かを切り分けるときは、まず失敗した検査が次の2種のいずれかに当てはまるかを確認する。

- ブラウザを使う検査（`generation-engine/scripts/tests/` 配下の `.cjs` のうち、実描画を伴うもの）。ブラウザを起動できない環境では失敗する
- 一時領域を作れない環境で落ちる検査（`add-sync-entry.sh`・`tests/check-portal-catalog.sh`・`unit-list/detect-screens.sh`）。これらは引数なしの `mktemp` を使っており、書き込みを拒む環境では失敗する

上記2種に当てはまる失敗は実行環境側の制約であり、検査そのものの不具合ではない。当てはまらない失敗は検査本体か対象コードの問題である可能性があるため、個別に確認する。

## 生成が途中で止まったとき

生成の途中でプロセスが止まった場合の戻し方を、実際に途中で止めて確かめた内容に基づいて示す。対象は `generation-engine/scripts/verification/run-layer-full-pipeline.sh`（第3層・一気通貫の生成連鎖。10段で構成する）。

### 1. どこまで進んだかを知る方法

起動時のログに出る `[実行中] <段名>` は「その段を開始した」印であり、「その段が完了した」印ではない。各段の合否は最後の段（結果の集計）でまとめて出力する作りのため、途中で止めたログだけでは完了済みの段を判別できない。

完了済みの段は、出力先ディレクトリに実際に生成されたファイルで判別する。次の順で生成されるため、どこまで揃っているかで進み具合が分かる。

| 段 | 完了の目印 |
|---|---|
| 1. 出力先の用意 | `<出力先>` ディレクトリが存在する |
| 2. 疑似入力の配置 | `<出力先>/verification-source/` 配下に api・table・batch・report・external・feature の6ディレクトリが揃う |
| 3. 設計文書からのマニフェスト組み立て | `<出力先>/docs/manifests/` に非画面6種別の `<種別>-manifest.json` が揃う |
| 4. 種別別の抽出 | 同ディレクトリに `screen-manifest.json` が加わる |
| 5. 一覧の生成 | `<出力先>/project-portal/一覧/` 配下に画面・機能・API・テーブル・バッチ・帳票・外部連携の7つの `<種別>一覧/<種別>一覧.html` が揃う |

実測（コミット `a278bc57ada76ccfda3c738969b5c94aae54cf89` 時点）では、開始から約1分でプロセスを止めたところ、段5（一覧の生成）の途中、`外部連携一覧.html` だけが未生成の状態で止まっていた。他の6つの一覧HTMLと `docs/manifests/` 配下の全マニフェストは揃っていた。段6（マトリクスの生成）以降の目印は今回の実測では確認していない（下記「確かめられなかったこと」を参照）。

### 2. 全部やり直す手順

出力先を削除してから、同じコマンドを再実行する。出力先はリポジトリの外（`$TMPDIR` 配下など）に取る。リポジトリの中を指定すると起動時に拒否される。

```bash
rm -rf <出力先>
bash generation-engine/scripts/verification/run-layer-full-pipeline.sh --output <出力先>
```

途中で止めた場合、`${TMPDIR:-/tmp}/reverse-verification/verify-<番号>` にスクラッチ作業領域が残ることがある。本スクリプトは正常終了時にしか自分で片付けないため、やり直す前に残骸の有無を確認して削除する。

```bash
ls "${TMPDIR:-/tmp}/reverse-verification/"
rm -rf "${TMPDIR:-/tmp}/reverse-verification/verify-<残っている番号>"
```

プロセスがまだ動いている場合はスクリプト名で止める。実測では1回の起動で同名のプロセスが複数見えたため、番号を1つだけ指定して止めるより、名前一致で確実に止める方法をとる。

```bash
pkill -f run-layer-full-pipeline.sh
```

### 3. 一部だけ作り直す手順

各段は既存の決定的スクリプトを順に呼んでいるだけなので、途中の1段だけをやり直したい場合は、そのスクリプトを直接呼び直せば足りる。前の段が生成した中間データ（マニフェスト等）がすでに出力先に残っていれば、それを入力として使い回せる。出力先全体を消す必要はない。

実測で確認した例（段5「一覧の生成」のうち外部連携一覧だけが未生成だった場合）。

```bash
mkdir -p <出力先>/project-portal/一覧/外部連携一覧
bash generation-engine/scripts/unit-list/build-unit-list.sh \
  <出力先>/docs/manifests/external-manifest.json \
  <出力先>/project-portal/一覧/外部連携一覧/外部連携一覧.html \
  --unit-kind external
```

他の段・他の種別も同様に、`run-layer-full-pipeline.sh` 冒頭のコメント（段の構成）と `dependency_scripts` 関数を見比べれば、どのスクリプトを直接呼べばよいかが分かる。

### 確かめられなかったこと

- 段6（マトリクスの生成）以降（デザイン系ページ・規約定義の展開・ポータルの生成・結果の集計）で止めた場合の進み具合の目印と、その段だけの単体再実行は、今回の実測時間内では確認していない
- 「全部やり直す」手順は、出力先を削除して開始できることと段1が始まることまでを確認した。最後まで完走することは所要時間の都合で確認していない
