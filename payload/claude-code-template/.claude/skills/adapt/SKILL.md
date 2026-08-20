---
name: adapt
description: |
  テンプレのプロジェクト適応。導入直後に代表者が 1 回実行する。
  TRIGGER when: /adapt と入力された時
  SKIP: 自動実行しない（disable-model-invocation: true）
invocation: adapt
disable-model-invocation: true
argument-hint: "引数なしで実行"
allowed-tools:
  - Read
  - Grep
  - Glob
---

# /adapt — テンプレートのプロジェクト適応

手順・判定基準・スニペットはこのファイルに書かれたものだけを使う。創作しない。

対話セッション必須（`.claude/` 配下の書き換えに承認が要るためヘッドレス `claude -p` では完遂できない）。

## 完了の定義

未適応の唯一の定義は ADAPT マーカー（正規表現 `<!--\s*ADAPT:`）の残存。
判定は独自 grep でなく必ず `node .claude/hooks/lib/check-adapt.mjs` を実行する（hook と同じ実装を使い判定ズレを防ぐ）。
マーカーは処理したら行ごと削除する（値を書いてマーカーを残す中間状態を作らない）。

## マーカー書式

- `<!-- ADAPT:detect:<id> | 指示 -->` — 自動判定して記入・削除
- `<!-- ADAPT:ask:<id> | 指示 -->` — 質問して反映・削除

## Step 0: 前提確認

1 つでも失敗したら中断する。

1. カレントがプロジェクトルートであること
2. Node.js 18 以上であること
3. `.claude/settings.json` が `JSON.parse` 可能であること
4. テンプレ由来ファイルがコミット済みであること（未コミットなら先に commit を促す。git 管理外なら削除は個別承認）
5. `node .claude/hooks/lib/check-adapt.mjs` を実行する。0 件ならメンテナンスモードへ

## Step 1: スタック検出

`node_modules` 等を除外し「マニフェスト依存 > 設定ファイル > 拡張子分布」の優先度で証拠収集する。

| スタック | 判定基準 |
|---|---|
| frontend | `package.json` に React/Vue/Angular/Svelte 等の依存。`tsconfig.json`・`vite.config.*`・`next.config.*` の存在。`.tsx`/`.jsx` ファイルの分布 |
| backend | `package.json` に Express/Fastify/NestJS 等の依存。`requirements.txt`/`Gemfile`/`go.mod` の存在。`server/`・`api/` ディレクトリ |
| database | `prisma/`・`migrations/`・`db/` ディレクトリ。`schema.prisma`・`knexfile.*` の存在 |
| testing | `jest.config.*`・`vitest.config.*`・`pytest.ini`・`.mocharc.*` の存在。`__tests__/`・`tests/`・`test/` ディレクトリ |
| infra | `Dockerfile`・`docker-compose.*`・`.github/workflows/`・`terraform/`・`k8s/` の存在 |

根拠ファイルパスを記録する。証拠ゼロ・矛盾時は推測せず質問に回す。

## Step 2: rules 適応計画（実行はまだ）

- `paths` は実在ディレクトリから導出し、書いた glob は Glob ツールで 1 件以上マッチすることを確認する（0 件マッチは書かない）
- 削除は「不存在の三点確認」がすべて成立した場合のみ（例: 10-frontend は依存なし・対象拡張子 0 件・ビルド設定なしの 3 点）
- `00-global.md` と `30-security.md` はいかなる検出結果でも削除・改名しない
- 未対応スタックは番号帯 60-89 で新規 rules を提案可

## Step 3: CLAUDE.md 処理案（実行はまだ）

各 ADAPT マーカーに対して記入する値を決定する。

## Step 4: 質問と承認

以下を 1 ブロックに集約して承認を得る。承認前に破壊的変更をしない。

- 検出サマリ（スタック × 証拠ファイル）
- rules 適応計画（paths 書き換え・ファイル削除の一覧）
- optional hooks 配線の推奨（監査ログが必要なチームのみ PostToolUse + ConfigChange）
- ask マーカーへの質問

## Step 5: 一括実行

- **settings.json は Edit ツールや自由作文で直接書き換え禁止**
- `optional/README.md` のスニペットを一字一句コピーする
- 使い捨て Node スクリプトで: 読込 → JSON.parse → 配列追加（同一 args があればスキップ = 冪等） → `JSON.stringify(obj, null, 2)` で書き戻し
- 書き戻し前に `.bak` 作成、書き戻し後に再検証、失敗時は復元
- 最後に CLAUDE.md の「Adapt 履歴」に記録形式で追記:
  ```
  - YYYY-MM-DD: 検出 [frontend, backend, ...] / 削除 [...] / 生成 [...] / hooks追加 [...] / template v0.1.0
  ```

## Step 6: 完了検証

1. `node .claude/hooks/lib/check-adapt.mjs` が exit 0 を返す（残マーカー 0 件）
2. `node -e "JSON.parse(require('fs').readFileSync('.claude/settings.json','utf8'))"` が成功
3. `node --test .claude/hooks/tests/guard.test.mjs` が通過
4. commit を提案し、rules のカナリアテスト案内を出す

## メンテナンスモード（マーカー残 0 件で起動時）

破壊的変更なしで以下を実施:

- paths の 0 件マッチ検出
- Adapt 履歴と突合した欠落ファイル確認（削除記録があれば再作成しない）
- 新スタック検出時は本家からの再取得案内
- 提案のみ

## 触ってはいけないもの

- `CLAUDE.local.md` と `.claude/settings.local.json`（個人ファイル）
- `.claude/hooks/**` と `.claude/skills/**`（テンプレ管理層）
