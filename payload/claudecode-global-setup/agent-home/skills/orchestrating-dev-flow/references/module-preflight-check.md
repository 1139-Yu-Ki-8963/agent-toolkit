# preflight-check（orchestrating-dev-flow 内部モジュール）

orchestrating-dev-flow の Phase 1 冒頭で毎回呼ばれ、プロジェクトの前提条件を検証して go/no-go を返すゲートモジュール。FAIL 項目は可能な限り自動修復する。

## 基本ワークフロー

### Step 1: プロジェクト初期化状態の確認

`.claude/rules/always/project-context/flow-values.yml` が存在するか確認する。

- **存在しない** → **no-go** を返す。「このプロジェクトは orchestrating-dev-flow 未導入です。先に `Skill(creating-new-project)` を実行してください」と報告する。プリフライト内で scaffold を実行しない（scaffold はヒアリングを含むため、プリフライトの責務を超える）
- **存在する** → YAML として Read を試行する
  - **Read 成功** → Step 2 に進む
  - **Read 失敗（パースエラー）** → **no-go** を返す。「flow-values.yml の YAML 構文エラー」と報告する

**incident ルートの最小モード:**
orchestrating-dev-flow から `mode: minimal` で呼ばれた場合、Step 2 は CRITICAL ツールのみ確認し、Step 3・Step 4 をスキップして Step 5 に進む。

### Step 2: ツール可用性チェック + 自動インストール

各ツールを確認し、FAIL の場合は自動インストールを実行する。インストール後に再チェックし、PASS になったことを確認する。

**CRITICAL（1 つでも最終 FAIL → no-go）:**

| チェック | 確認コマンド | PASS 条件 | 自動修復コマンド |
|---|---|---|---|
| Node.js | `node --version` | v18 以上 | `brew install node` |
| npm | `npm --version` | 存在すること | Node.js と同梱。Node.js を修復すれば解決 |
| Python | `python3 --version` | v3.10 以上 | `brew install python@3` |
| git | `git --version` | 存在すること | `xcode-select --install`（macOS）/ `brew install git` |
| gh CLI | `gh auth status` | 認証済み | 未インストール: `brew install gh`。未認証: **自動修復不可**（後述） |

**OPTIONAL（最終 FAIL → WARN。go は返す）:**

| チェック | 確認コマンド | PASS 条件 | 自動修復コマンド |
|---|---|---|---|
| textlint 設定 | `test -f ~/agent-home/tools/linter/.textlintrc.json` | 存在すること | 自動修復不可（agent-home の整合性問題） |
| lychee | `lychee --version` | 存在すること | `brew install lychee` |
| gitleaks | `gitleaks version` | 存在すること | `brew install gitleaks` |
| Playwright MCP | ToolSearch で `mcp__playwright__browser_navigate` が解決可能か | 解決できること | 自動修復不可（MCP 設定の問題） |

**自動修復の実行手順:**

1. 全チェック項目を実行し、FAIL 一覧を収集する
2. Homebrew の存在を確認する: `which brew`
   - 存在しない場合: `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` を実行する（macOS のみ）
3. FAIL 項目ごとに自動修復コマンドを実行する
4. 修復後、当該項目のチェックを再実行する
5. 再チェック PASS → FAIL を取り消す
6. 再チェック FAIL → 最終 FAIL として記録する

**自動修復不可の場合:**

gh CLI が未認証（`gh auth status` が FAIL）の場合、対話的な OAuth 認証が必要であり Claude では代行できない。以下の NO-DELEGATION-ABORT 形式で報告し、**no-go** を返す:

```
[NO-DELEGATION-ABORT]
操作: gh auth login（GitHub CLI の OAuth 認証）
理由: 対話的なブラウザ認証が必要であり、Claude では代行不可
代替案: 環境変数 GH_TOKEN にパーソナルアクセストークンを設定すれば対話なしで認証可能
```

`flow-values.yml` に `preflight.skip_tools: [gitleaks, lychee]` が設定されている場合、対象 OPTIONAL ツールのチェックをスキップする。CRITICAL ツールのスキップは不可。

### Step 3: プロジェクト構造チェック + 自動修復

flow-values.yml の内容を参照し、各フィールドの参照先ファイルの存在を確認する。存在しない場合は自動生成する。

**null フィールドの処理:** フィールドが null または未定義の場合はチェックをスキップし、WARN として報告する。

| チェック | パス | PASS 条件 | 自動修復 |
|---|---|---|---|
| layers.yml | `.claude/rules/always/project-context/layers.yml` | 存在すること | `Skill(creating-new-project)` で生成済みのはず。存在しなければ FAIL |
| DESIGN.md | `design_system` で指定されたパス | 存在すること | FAIL（`Skill(creating-new-project)` の Step 5 で生成する） |
| PR テンプレート | `pr.template` で指定されたパス | 存在すること | FAIL（`Skill(creating-new-project)` の Step 4 で生成する） |
| glossary | `domain_glossary` で指定されたパス | 存在すること | FAIL（`Skill(creating-new-project)` の Step 3 で生成する） |
| project-portal | `portal_dir` で指定されたパス | ディレクトリが存在すること | `Skill(creating-new-project)` で生成済みのはず。存在しなければ FAIL |
| 個別設計ディレクトリ | `design_docs` で指定されたパス | ディレクトリが存在すること | `mkdir -p` で自動作成 |
| .gitignore | `.gitignore` | `.flow-progress.json` と `.claude/markers/` を含む | 不足行を追記する |

**DESIGN.md の構造検証:** DESIGN.md が存在する場合、`~/agent-home/tools/design/validate-design-md.sh` で構造を検証する。FAIL なら WARN として報告する。

### Step 4: レイヤー別コマンド検証

layers.yml を Read し、各レイヤーの lint / test / type_check コマンドの先頭コマンドが `which` で見つかるか確認する。

見つからない場合、以下を試行する:
- npm 系コマンド（biome / vitest / eslint 等）: `npm install` を該当レイヤーの src ディレクトリの親で実行
- Python 系コマンド（ruff / pytest / mypy 等）: `pip install <tool>` を実行
- インストール後に再チェックする

レイヤーが 0 件の場合は WARN を出す。

### Step 5: 結果報告と判定

全項目を表形式で報告する。

- **CRITICAL 全 PASS**（自動修復後の再チェック含む） → **go**（WARN 一覧を併記）
- **CRITICAL に 1 つでも最終 FAIL** → **no-go**（FAIL 項目と原因を報告）

## 完了条件

| Step | 完了条件 |
|---|---|
| Step 1 | flow-values.yml が存在し YAML パースが成功している |
| Step 2 | CRITICAL ツールが全て使用可能（自動インストール含む） |
| Step 3 | flow-values.yml が参照する全ファイルが存在している（自動生成含む） |
| Step 4 | 全レイヤーのコマンドが実行可能（npm install / pip install 含む） |
| Step 5 | go / no-go が報告されている |
| **Goal** | **CRITICAL 全 PASS で go を返し、orchestrating-dev-flow の Phase 1 が続行できる状態** |

## 予想を裏切る挙動

- gh CLI の認証は対話必須のため自動修復不可。GH_TOKEN 環境変数による代替を NO-DELEGATION-ABORT で提示する
- Playwright MCP は MCP サーバー設定の問題であり、brew install では解決しない
- Homebrew 自体が未インストールの場合は先に Homebrew をインストールする
- `npm install` は package.json が存在するディレクトリで実行する。プロジェクトルートとは限らない
- `pip install` はプロジェクトの仮想環境（.venv）がある場合はその中で実行する
- flow-values.yml に `preflight.skip_tools: [gitleaks, lychee]` を設定することで OPTIONAL ツールのスキップが可能
- `creating-new-project` スキルの内部ステップから呼ばれた場合も同一ロジックで動作する
