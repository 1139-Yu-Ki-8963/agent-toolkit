---
name: creating-new-project
description: "新規プロジェクトセットアップ（Next.js / React+Vite+FastAPI）。 TRIGGER when: 「新規プロジェクト」「プロジェクト作成」「アプリ新規作成」「セットアップ」と言われた時。 SKIP: 既存機能追加（→orchestrating-dev-flow）。"
invocation: creating-new-project
type: orchestration
allowed-tools: Bash, Read, Write, Edit
---

# creating-new-project

`~/Projects/` に新規プロジェクトを作成し、Claude Code 連携基盤・ドキュメント体系・プロジェクトポータル・CI/CD・QA までを一括セットアップするスキル。

テンプレートの具体内容は `references/project-structure-reference-model.md` を参照。各 Phase の詳細手順は `references/phase-*.md` に分離してある。

## 前提条件

- Node.js がインストール済みであること
- `gh` CLI が認証済みであること
- `~/Projects/` ディレクトリが存在すること

## Phase 一覧

| Phase | 名前 | 概要 | 詳細参照 |
|---|---|---|---|
| 1 | ヒアリング | プロジェクト骨格（目的・機能・画面・スタック・ユーザー種別）を収集 | `references/phase-1-hearing.md` |
| 2 | スキャフォールド | create-next-app + 画面別ルーティング + docs/REQUIREMENTS.md | `references/phase-2-4-scaffold-docs.md` |
| 3 | Claude Code 基盤 | .claude/rules 実体構築（rules: domain / project / always（project-context に許可リスト節・layers.yml も含む）・settings.json） | `references/phase-2-4-scaffold-docs.md` |
| 4 | ドキュメント体系 | docs/ 番号付き 4 カテゴリ + 初期設計書 | `references/phase-2-4-scaffold-docs.md` |
| 5 | プロジェクトポータル | project-portal/ SPA 一式（index.html・data/・src/） | `references/phase-5-portal.md` |
| 6 | CI/CD・品質基盤 | .github/・.husky/・.config/・qa/ | `references/phase-6-10-finalize.md` |
| 7 | ルート設定 | CLAUDE.md・Makefile・.gitignore・.gitattributes | `references/phase-6-10-finalize.md` |
| 8 | ポート割当登録 | port-management-rules にテーブル追加 | `references/phase-6-10-finalize.md` |
| 9 | Git + GitHub | 初期化・初回 commit・リモート作成・push | `references/phase-6-10-finalize.md` |
| 10 | 検証 | dev server・ポータル・構造の完全性検証 | `references/phase-6-10-finalize.md` |

---

## Phase 1: ヒアリング

AskUserQuestion で `project_name` / `purpose` / `stack` / `features[]` / `screens[]` / `user_roles[]` / `base_port` を収集する。ベースポートは `~/.claude/rules/always/local-environment/port-management/rule.md` から未使用の最小値を自動検出する。

詳細な質問文・選択肢・バリデーションは `references/phase-1-hearing.md` を参照。

完了条件: ヒアリング結果のサマリをユーザーに提示し、承認を得た。

## Phase 2: スキャフォールド

`create-next-app`（または `React + Vite + FastAPI` 選択時は frontend/backend 分離構成）でプロジェクトを生成し、Phase 1 の画面一覧からページファイルを生成、`docs/REQUIREMENTS.md` を配置する。

詳細コマンド・テンプレートは `references/phase-2-4-scaffold-docs.md` を参照。

## Phase 3: Claude Code 基盤

`.claude/rules/` を実体ディレクトリとして作成し、rules（domain / project / always）・settings.json を構築する。domain・project カテゴリの正本は `~/agent-home/templates/project-claude-rules/` からコピーし、プレースホルダを置換する。スタックに無いスコープ（FE のみ構成なら backend/db 等）は削除する。flow 系 rules は scaffold しない（フロー進行の管理は orchestrating-dev-flow の管轄）。プロジェクト標準構成規約（`~/.claude/rules/scoped/agent-config/project-structure/rule.md`）に従い、`.claude/rules/always/project-context/rule.md`（`## ルート直下許可ディレクトリ` 節を含む）・`flow-values.yml` の必須 2 ファイルを生成する（旧 `.claude/skills/flow-config/flow-context.yml` および専用 `placement/directory-structure/rule.md` はこの体系に吸収済み・互換レイヤなし）。レイヤー別コマンド体系を定義する `layers.yml` も `.claude/rules/always/project-context/layers.yml`（`.claude/skills/flow-config/` は廃止済み・跡地なし）に配置する。codebase-boundary の配置後に `templates/project-claude-rules/project/codebase-boundary/rule.md` を `.claude/rules/project/codebase-boundary/rule.md` へ複製し、paths をプロジェクトの実構成に合わせて書き換える。最後に `scaffolding-flow-structure.md` のプリフライトチェックで flow 前提構造の go/no-go を検証する。no-go の場合は FAIL 項目を修正してから Phase 4 に進む。

詳細なディレクトリ構成・テンプレートは `references/phase-2-4-scaffold-docs.md` を参照。

## Phase 4: ドキュメント体系

`docs/` 配下に番号付き 4 カテゴリを構築する。コピー元の正本は `~/agent-home/templates/project-docs/`。

- **4-1.** `~/agent-home/templates/project-docs/` を正本として以下の順に複製・置換する。
- **4-2.** 機能ごとに `templates/project-docs/01_機能基本設計/` の 3 ファイル（機能基本設計書.md・単体テスト観点表.md・結合テスト観点表.md）を `docs/01_機能基本設計/<機能名>/` へ複製し、`doc_id`・`feature_name` を Phase 1 の値で置換する。
- **4-3.** 画面ごとに `templates/project-docs/02_画面基本設計/` の 4 ファイルセット（画面基本設計書.md・DESIGN.md・単体テスト観点表.md・結合テスト観点表.md）を `docs/02_画面基本設計/<画面名>/` へ複製し、`doc_id`・`target_screen`・`route` を置換する。加えて `_共通/` 3 ファイル（DESIGN.md・メッセージ定義書.md・画面共通仕様.md）をプロジェクトに 1 セット `docs/02_画面基本設計/_共通/` へ配置する。
- **4-4.** 主要フローごとに `templates/project-docs/03_操作フロー設計/` の 2 ファイル（操作フロー設計書.md・E2Eテスト観点表.md）を `docs/03_操作フロー設計/<フロー名>/` へ複製し、`flow_name` を置換する。
- **4-5.** `templates/project-docs/04_開発プロセス設計/プロジェクト地図.md` を `docs/04_開発プロセス設計/` へ複製し、プロジェクト名・モジュール一覧を記入する。
- **4-6.** `templates/project-docs/設計書レビュー観点.md` を `docs/` 直下へ複製する（変更なし、参照専用）。

## Phase 5: プロジェクトポータル

vanilla JS SPA（ビルドツール不要、ES modules + hash routing）のプロジェクト管理ポータルを構築する。ファイル数が多いため、サブエージェント並列実行の対象（後述の「サブエージェント委任仕様」参照）。

詳細なディレクトリ構成・ファイル一覧は `references/phase-5-portal.md` を参照。

## Phase 6: CI/CD・品質基盤

`.github/`（PR テンプレート・issue テンプレート 3 種・CI・dependabot）・`.husky/`（pre-commit/pre-push）・`.config/`（gitleaks・lychee）・`qa/`（user-stories・qa-tracking）を配置する。

詳細テンプレートは `references/phase-6-10-finalize.md` を参照。

## Phase 7: ルート設定

`CLAUDE.md`（200 行以内）・`Makefile`・`.gitignore`・`.gitattributes` を配置し、`package.json` の `dev` スクリプトにポートを設定する。

詳細テンプレートは `references/phase-6-10-finalize.md` を参照。

## Phase 8: ポート割当登録

`~/.claude/rules/always/local-environment/port-management/rule.md` を Edit し、ベースポートテーブルと割当表セクション（スタックに応じた列構成）を追加する。

## Phase 9: Git + GitHub

`git init` → 初回 commit の後、AskUserQuestion で GitHub リポジトリ作成の要否を確認する（作成して push / ローカルのみ / 中止）。

## Phase 10: 検証

構造検証（ディレクトリ・ファイルの網羅確認）・dev server 起動確認（HTTP 200）・ポータル起動確認（HTTP 200）を実行し、完了報告テンプレートで結果を提示する。docs 構造検証では 4 カテゴリディレクトリ・`docs/02_画面基本設計/_共通/`（DESIGN.md・メッセージ定義書.md・画面共通仕様.md）・`docs/04_開発プロセス設計/プロジェクト地図.md`・`docs/設計書レビュー観点.md`・画面ごとの 4 ファイルセット（画面基本設計書.md・DESIGN.md・単体テスト観点表.md・結合テスト観点表.md）の存在を確認する。

詳細な検証コマンド・完了報告テンプレートは `references/phase-6-10-finalize.md` を参照。

---

## サブエージェント委任仕様

Phase 5（ポータル SPA）は生成ファイル数が多いため、以下を並列でサブエージェントに委任する。Phase 1-4・6-10 はメインエージェントが順次実行する。

| 呼び出し箇所 | subagent_type | prompt 骨格 | 期待返却値 |
|---|---|---|---|
| Phase 5: index.html + style.css + src/ | worker-sonnet | プロジェクト名・機能/画面リスト・oradora-battle-base の `project-portal/` を参照元として渡し、index.html・style.css・src/ 一式を生成させる | 生成ファイルパス一覧 |
| Phase 5: data/ 全体 | worker-sonnet | Phase 1 のヒアリング値（機能・画面・スタック）を渡し、manifest.js・master-tables/* を生成させる | 生成ファイルパス一覧 |
| Phase 5: 定型ファイル | worker-haiku | sites/rules/index.html・tools/serve.py・mocks-archive/.gitkeep を定型テンプレートどおり作成させる | 作成ファイルパス一覧 |

## エラーハンドリング

| Phase | エラー | 対応 |
|---|---|---|
| 1 | プロジェクト名が重複 | AskUserQuestion で再入力 |
| 2 | create-next-app 失敗 | エラーログを表示し、AskUserQuestion で削除対象パスを提示・承認を得てから作成途中を `rm -rf` する |
| 3 | 設定ファイル Write 失敗 | ディスク容量・パーミッションを報告 |
| 5 | ポータル SPA のファイル数が多い | Phase 5 をサブエージェント並列で実行 |
| 8 | ポート範囲が枯渇 | AskUserQuestion でカスタムポート入力 |
| 9 | gh repo create 失敗 | gh auth status 確認、認証切れなら報告 |
| 10 | dev server 起動失敗 | ポート競合を lsof -i で診断 |

## 完了条件

| Phase | 完了条件 |
|---|---|
| 1 | 全ヒアリング値が非空 |
| 2 | `~/Projects/<name>/` 存在、画面分の page.tsx が存在 |
| 3 | .claude/rules/ 実体。rules（domain 2 + project 4 + always/project-context 1（許可リスト節含む）= rule.md 7 本目安）+ project-context/layers.yml + settings.json |
| 4 | docs/ に 4 カテゴリ + _共通 3 ファイル + プロジェクト地図 + 設計書レビュー観点 + 機能（3 ファイル）・画面（4 ファイルセット）設計書 |
| 5 | project-portal/ に index.html + data/ + src/ |
| 6 | .github/ + .husky/ + .config/ + qa/ |
| 7 | CLAUDE.md + Makefile + .gitignore + .gitattributes |
| 8 | port-management-rules にベースポート + 割当表 |
| 9 | GitHub リポジトリ作成・push 完了 |
| 10 | dev server HTTP 200 + ポータル HTTP 200 + 構造検証全 PASS |
| **Goal** | 全 Phase 完了。開発着手可能な状態 |

## 予想を裏切る挙動

- Phase 2 のエラー復旧で `rm -rf` する前に、必ず AskUserQuestion で削除対象パスをユーザーに提示し承認を得る。無承認の `rm -rf` は禁止
- `base_port` は port-management-rules から動的検出するため、並行して他セッションが新規プロジェクトを作成中だと同じベースポートを提案しうる。Phase 8 で Edit する直前に再度重複確認する
- Phase 3-8（`references/phase-2-4-scaffold-docs.md` 内）のプリフライトチェックが no-go を返した場合、Phase 4 に進んでも orchestrating-dev-flow が後続 Phase で動作しない。no-go を無視して先に進まない
- `rules/always/project-context/rule.md` の `## ルート直下許可ディレクトリ` 節はスタック（FE のみ / フルスタック）で許可ディレクトリが変わる。スタック選択と生成した許可リストの不一致は、後続の `mkdir` 時に advisory ノイズを生む
- Phase 5 はサブエージェント 3 体を並列委任するため、担当領域（src/・data/・定型ファイル）が重ならないよう prompt でファイルパスを明示する。重複するとファイル書き込みが競合する
- Phase 10 の dev server / ポータル起動確認はバックグラウンドジョブ（`&` + `kill %1`）に依存する。同一シェルセッション内で他のバックグラウンドジョブが `%1` を専有していると誤ったプロセスを kill する

## 完了報告

`managing-agent-configs/references/skills/completion-report-format.md` の共通骨格（作業報告型）に従う。詳細は `references/phase-6-10-finalize.md` の 10-4 を参照。

## 参照資料

- `references/project-structure-reference-model.md` — テンプレート・設計パターンの全詳細
- `references/phase-1-hearing.md` — Phase 1 ヒアリングの質問文・選択肢・バリデーション詳細
- `references/phase-2-4-scaffold-docs.md` — Phase 2〜4（スキャフォールド・Claude Code 基盤・ドキュメント体系）の詳細手順
- `references/phase-5-portal.md` — Phase 5（プロジェクトポータル）の詳細手順
- `references/phase-6-10-finalize.md` — Phase 6〜10（CI/CD・ルート設定・ポート登録・Git・検証）の詳細手順
- `references/scaffolding-flow-structure.md` — orchestrating-dev-flow 前提条件のプリフライトチェック手順
