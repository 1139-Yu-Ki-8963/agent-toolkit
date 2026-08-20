# preflight-check（orchestrating-dev-flow 内部モジュール）

orchestrating-dev-flow の Phase 1 冒頭で毎回呼ばれ、プロジェクトの前提条件を検証して go/no-go を返すゲートモジュール。既定動作は検出と案内のみで、OS・プロジェクト環境を変更する導入操作はユーザーの明示承認後だけ実行する。

## 基本ワークフロー

### Step 1: プロジェクト初期化状態の確認

最初に呼び出し元の共通 handoff を JSON 化し、次を実行する。`{}` や必須7キー・型が不足する handoff は no-go。

```bash
node ~/agent-home/skills/orchestrating-dev-flow/scripts/validate-handoff-coverage.mjs schema <handoff.json>
```

schema mode は対応表作成前に実行でき、Goal や publication の完了は判定しない。

`.claude/rules/always/project-context/flow-values.yml` が存在するか確認する。

- **存在しない** → **WARN** を返し、標準値（review gate なし・ドメイン用語なし・既定 classify）で Step 2 へ進む。プロジェクト固有設定が必要なら後続で配置を提案する
- **存在する** → YAML として Read を試行する
  - **Read 成功** → Step 2 に進む
  - **Read 失敗（パースエラー）** → **no-go** を返す。「flow-values.yml の YAML 構文エラー」と報告する

**incident ルートの最小モード:**
orchestrating-dev-flow から `mode: minimal` で呼ばれた場合、Step 2 は CRITICAL ツールのみ確認し、Step 3・Step 4 をスキップして Step 5 に進む。

### Step 2: ツール可用性チェック + 導入案内

各ツールを確認し、FAIL の場合は OS・バージョン管理方法・プロジェクトの package manager / 仮想環境を確認して導入案を提示する。`brew`・`curl`・`npm`・`pip` 等による導入は自動実行しない。ユーザーが具体的な導入操作を明示承認した場合だけ実行し、再チェックする。

**CRITICAL（1 つでも最終 FAIL → no-go）:**

| チェック | 確認コマンド | PASS 条件 | 導入案内例（自動実行禁止） |
|---|---|---|---|
| Node.js | `node --version` | v18 以上 | 既存の version manager または OS package manager を特定して案内 |
| npm | `npm --version` | 存在すること | Node.js の導入方法と package manager 方針を確認して案内 |
| Python | `python3 --version` | v3.10 以上 | 既存の version manager・仮想環境・OS package manager を特定して案内 |
| git | `git --version` | 存在すること | OS の開発ツールまたは package manager を特定して案内 |
| gh CLI | `gh auth status` | 認証済み | 公式導入方法を案内。未認証は対話操作が必要（後述） |

**OPTIONAL（最終 FAIL → WARN。go は返す）:**

| チェック | 確認コマンド | PASS 条件 | 導入案内例（自動実行禁止） |
|---|---|---|---|
| textlint 設定 | `test -f ~/agent-home/tools/linter/.textlintrc.json` | 存在すること | agent-home の整合性問題として案内 |
| lychee | `lychee --version` | 存在すること | OS・プロジェクトに合う公式導入方法を案内 |
| gitleaks | `gitleaks version` | 存在すること | OS・プロジェクトに合う公式導入方法を案内 |
| Playwright MCP | ToolSearch で `mcp__playwright__browser_navigate` が解決可能か | 解決できること | MCP 設定の問題として案内 |

**導入判断の手順:**

1. 全チェック項目を実行し、FAIL 一覧を収集する
2. OS、既存のバージョン管理方法、lockfile、package manager、仮想環境を検出する
3. 環境に合う導入案と影響範囲を提示し、ユーザーの明示承認を得る
4. 承認された具体的なコマンドだけを実行する。承認のない Homebrew 導入や `npm install` / `pip install` は行わない
5. 実行後、当該項目のチェックを再実行する
6. 拒否・失敗時は、そのツールを使わない安全な既存モジュールへ縮退できるなら WARN で続行する。完了条件に必要で縮退不能なら blocked / no-go として不足条件を報告する

**自動変更できない場合:**

gh CLI が未認証（`gh auth status` が FAIL）の場合、対話的な OAuth 認証が必要であり Claude では代行できない。以下の NO-DELEGATION-ABORT 形式で報告し、**no-go** を返す:

```
[NO-DELEGATION-ABORT]
操作: gh auth login（GitHub CLI の OAuth 認証）
理由: 対話的なブラウザ認証が必要であり、Claude では代行不可
代替案: 環境変数 GH_TOKEN にパーソナルアクセストークンを設定すれば対話なしで認証可能
```

`flow-values.yml` に `preflight.skip_tools: [gitleaks, lychee]` が設定されている場合、対象 OPTIONAL ツールのチェックをスキップする。CRITICAL ツールのスキップは不可。

### Step 3: プロジェクト構造チェック

flow-values.yml の内容を参照し、各フィールドの参照先ファイルの存在を確認する。不足がある場合は、作成・追記する対象、具体的なコマンドまたは差分、影響範囲を提示する。ユーザーがその変更を明示承認した場合だけ実行し、実行後に同じ条件を再検査する。未承認時は変更せず、後続工程が不要なら WARN で安全縮退し、完了条件に必要なら blocked / no-go とする。

**null フィールドの処理:** フィールドが null または未定義の場合はチェックをスキップし、WARN として報告する。

| チェック | パス | PASS 条件 | 対応 |
|---|---|---|---|
| layers.yml | `.claude/rules/always/project-context/layers.yml` | 存在すること | 生成案を提示。`creating-new-project` が利用可能なら候補にできるが、明示承認前は実行しない |
| DESIGN.md | `design_system` で指定されたパス | 存在すること | 生成案と配置差分を提示し、明示承認後だけ作成 |
| PR テンプレート | `pr.template` で指定されたパス | 存在すること | 生成案と配置差分を提示し、明示承認後だけ作成 |
| glossary | `domain_glossary` で指定されたパス | 存在すること | 生成案と配置差分を提示し、明示承認後だけ作成 |
| project-portal | `portal_dir` で指定されたパス | ディレクトリが存在すること | 生成案を提示し、明示承認後だけ作成 |
| 個別設計ディレクトリ | `design_docs` で指定されたパス | ディレクトリが存在すること | `mkdir -p <解決済みパス>` を具体案として提示し、明示承認後だけ実行 |
| .gitignore | `.gitignore` | `.flow-progress.json` と `.claude/markers/` を含む | 追記差分を提示し、明示承認後だけ編集 |

**DESIGN.md の構造検証:** DESIGN.md が存在する場合、`~/agent-home/tools/design/validate-design-md.sh` で構造を検証する。FAIL なら WARN として報告する。

### Step 4: レイヤー別コマンド検証

layers.yml を Read し、各レイヤーの lint / test / type_check コマンドの先頭コマンドが `which` で見つかるか確認する。

見つからない場合は、lockfile・package manager・仮想環境を確認して導入案を提示する。ユーザーが明示承認した場合だけプロジェクト環境へ導入し、再チェックする。拒否・失敗時は同等の既存コマンドへ安全に縮退できるか判定し、不能なら no-go とする。

レイヤーが 0 件の場合は WARN を出す。

### Step 5: 結果報告と判定

全項目を表形式で報告する。

- **CRITICAL 全 PASS**（承認済み導入後の再チェック含む） → **go**（WARN 一覧を併記）
- **CRITICAL に 1 つでも最終 FAIL** → **no-go**（FAIL 項目と原因を報告）

## 完了条件

| Step | 完了条件 |
|---|---|
| Step 1 | handoff schema が PASS。flow-values.yml 不存在なら WARN、存在するなら YAML パース成功 |
| Step 2 | CRITICAL ツールが全て使用可能。導入が必要な場合はユーザー承認と再チェック証拠がある |
| Step 3 | 参照先の検査が完了し、不足は承認済み変更後の再検査 PASS、WARN 付き安全縮退、または blocked / no-go のいずれかに確定している |
| Step 4 | 全レイヤーのコマンドが実行可能、または安全な縮退可否が確定している |
| Step 5 | go / no-go が報告されている |
| **Goal** | **CRITICAL 全 PASS で go を返し、orchestrating-dev-flow の Phase 1 が続行できる状態** |

## 予想を裏切る挙動

- gh CLI の認証は対話必須のため自動変更しない。GH_TOKEN 環境変数による代替を NO-DELEGATION-ABORT で提示する
- Playwright MCP は MCP サーバー設定の問題であり、brew install では解決しない
- Homebrew 自体を含め、OS 環境への導入は案内のみが既定。ユーザーの明示承認なしに実行しない
- `npm install` は lockfile と package manager を確認し、ユーザーが明示承認した場合だけ適切なディレクトリで実行する
- `pip install` は仮想環境とプロジェクトの依存管理方式を確認し、ユーザーが明示承認した場合だけ実行する
- flow-values.yml が存在しない場合は標準値で go。存在するが不正な場合だけ no-go
- flow-values.yml に `preflight.skip_tools: [gitleaks, lychee]` を設定することで OPTIONAL ツールのスキップが可能
- `creating-new-project` スキルの内部ステップから呼ばれた場合も同一ロジックで動作する
