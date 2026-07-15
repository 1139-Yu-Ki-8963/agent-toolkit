# Phase 1: ヒアリング（詳細手順）

> `creating-new-project/SKILL.md` の Phase 1 詳細。AskUserQuestion の質問文・選択肢・バリデーションを定義する。

AskUserQuestion を使い、プロジェクトの骨格を収集する。

## Step 1-1: 基本情報

**質問 A: プロジェクト名**

- header: `プロジェクト名`
- question: `プロジェクト名を入力してください（kebab-case、例: my-awesome-app）`
- options:
  - `my-new-app` — 汎用的なアプリ名の例
  - `project-name` — プレースホルダー例

**バリデーション:**
- kebab-case（`^[a-z][a-z0-9]*(-[a-z0-9]+)*$`）
- `~/Projects/<name>/` が存在しないこと

**質問 B: プロジェクトの目的**

- header: `目的`
- question: `このプロジェクトは何のためのアプリですか？（1〜2文で）`
- options:
  - `業務管理ツール` — 社内業務の効率化
  - `ポートフォリオサイト` — 個人の作品・実績公開

## Step 1-2: 技術スタック

- header: `スタック`
- question: `技術スタックを選んでください`
- options:
  - `Next.js (App Router) のみ` — フロントエンドのみ。API Routes で軽量バックエンド
  - `Next.js + Supabase` — フルスタック。Supabase で DB + Auth
  - `React + Vite + FastAPI` — フロントとバックを分離。Python バックエンド

選択に基づき以下を決定する:

| スタック | FE | BE | DB | テスト | Lint |
|---|---|---|---|---|---|
| Next.js のみ | Next.js + TS | API Routes | — | Vitest | Biome |
| Next.js + Supabase | Next.js + TS | — | Supabase | Vitest | Biome |
| React + Vite + FastAPI | React + Vite + TS | FastAPI | Supabase | Vitest + pytest | Biome + Ruff |

## Step 1-3: メイン機能

- header: `メイン機能`
- question: `主要な機能を教えてください（Other で自由入力可）`
- options:
  - `CRUD 管理画面` — データの登録・編集・削除・一覧表示
  - `ユーザー認証` — ログイン・サインアップ・権限管理
  - `ダッシュボード` — 統計・グラフ・概要表示

機能が「未定」の場合はフォールバック:
- AskUserQuestion で「汎用テンプレート（トップページのみ）で進めるか」を確認
- Yes → 共通画面のみ（`/` + `/about`）で構成

## Step 1-4: 主要画面

Step 1-3 の機能から画面候補を推論し、AskUserQuestion で確認する。

推論ロジック:
1. 各機能に対して典型的な画面を列挙（例: 「CRUD 管理」→ 一覧・詳細・作成）
2. 共通画面（トップページ・設定画面）を追加
3. 過不足を確認

- header: `画面構成`
- question: `以下の画面構成で進めてよいですか？不足・変更があれば Other で入力してください`
- options:
  - `提案通り` — 推論された画面構成をそのまま採用
  - `画面を追加したい` — 追加する画面名を Other で入力
  - `画面を減らしたい` — 不要な画面名を Other で入力

## Step 1-5: ユーザー種別

- header: `ユーザー種別`
- question: `このアプリのユーザー種別を選んでください`
- multiSelect: true
- options:
  - `一般ユーザー` — メインのエンドユーザー
  - `管理者` — 管理機能にアクセスできるユーザー
  - `ゲスト` — 未ログインでもアクセス可能

## Step 1-6: ベースポート自動検出

`~/.claude/rules/always/local-environment/port-management/rule.md` を Read し、使用済みベースポートを抽出する。

1. テーブルから `| NNNN |` パターンで使用済みポートを抽出
2. 8000, 8100, 8200, ..., 8900 のうち未使用の最小値を選択
3. ユーザーに「ベースポート: NNNN を割り当てます」と提示

## ヒアリング成果物

以下の値を Phase 2 以降で使用する:
- `project_name` — kebab-case
- `purpose` — 目的（1〜2文）
- `stack` — 技術スタック選択
- `features[]` — 機能リスト
- `screens[]` — 画面リスト（name, path, feature）
- `user_roles[]` — ユーザー種別
- `base_port` — ベースポート（100 刻み）
