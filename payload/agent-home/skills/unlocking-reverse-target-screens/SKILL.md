---
name: unlocking-reverse-target-screens
description: "設計書が無い画面をモックAPIでログイン後まで開通させ動作確認可能にする。 TRIGGER when: 画面開通、設計書皆無画面の動作確認、設計書着手前の下準備。 SKIP: 設計書がある画面の往復検証、環境同期。"
invocation: unlocking-reverse-target-screens
type: orchestration
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob]
---

# 設計書なし画面の開通スキル

このスキルは「作業者」であり、設計書がまだ無い画面を対象に既存コードを調査してモックAPIを適用し、ログイン後まで画面表示できる状態（開通）にする。開通完了後の記帳・基準タグ確立は行わない（それは管理者が担い、orchestrating-reverse-docs-flow が syncing-reverse-env をレジストリモードで起動する）。他スキルを呼び出さず、他スキルの設定ファイルに書き込まない。

## 使用タイミング

- 対象画面にまだ設計書が無く、既存コードがログインを要求するなどの理由でそのままでは動作確認できないとき
- 起動引数は system・screen_id・reverse_worktree・ports・docs_root の全量（管理者から渡される。単独起動時はユーザーが同じ引数を手渡せば動く）
- 設計書が既にある画面はこのスキルの対象外（`rebuilding-screen-unit-from-docs` / `rebuilding-code-from-docs` を使う）

## 実行手順

### Phase 1: 入力ロード + preflight

起動引数（system・screen_id・reverse_worktree・ports・docs_root）を受け取る。いずれかが渡されない場合は起動不可として status=ERROR で管理者へ差し戻す。`reverse_worktree` 配下で対象画面のソースコード一式（ルーティング定義・画面コンポーネント・関連APIクライアント）を Grep/Glob で特定し、実在を確認する。対象が見つからなければ status=ERROR で差し戻す。

完了条件: 対象画面のソースコード一式の所在が確認済み

### Phase 2: 既存コード調査

対象画面のルーティング定義・認証ガード（ログイン必須化のロジック）・外部API呼び出し箇所を Read/Grep で調査し、モックAPIで代替すべき箇所を特定する。この時点ではオリジナルコードの改変は行わない（調査のみ）。

完了条件: モックAPI適用が必要な箇所の一覧が記録されている

### Phase 3: モックAPI適用 + 動作確認

Phase 2 で特定した箇所に最小限のモックAPI（固定レスポンスを返すスタブ等）を Edit/Write で適用し、`reverse_worktree` 上でログイン後まで画面が表示されることを確認する。可能であれば起動して実機確認する。確認手段が無い環境では「静的確認のみ」と明記して続行する。この変更はコミットする（コミットメッセージ:「【機能追加】<画面名> をモックAPIで開通」）。

完了条件: 画面がログイン後まで表示可能であることを確認済み（実機確認または静的確認のいずれかで）、変更がコミット済み

### Phase 4: 証跡保存 + 返却

開通確認時点のコミットハッシュ（source_ref）、画面を表示確認できたURL（verification_url。ローカル起動できなければ「未実施」と明記）、今後の設計書の想定配置パス（design_doc_path。`docs_root` 起点で `<system>-<screen_id>` 相当のパスを組み立てる）を記録し、返却ブロックを返す。

完了条件: 返却ブロック（status・source_ref・verification_url・design_doc_path）が確定している

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 対象画面のソースコード一式の所在が確認済み |
| Phase 2 | モックAPI適用が必要な箇所の一覧が記録されている |
| Phase 3 | 画面がログイン後まで表示可能であることを確認済み、変更がコミット済み |
| Phase 4 | 返却ブロックが確定している |
| **Goal** | 対象画面がモックAPI経由でログイン後まで表示可能になり、返却ブロック（status=UNLOCKED・source_ref・verification_url・design_doc_path）が管理者に渡っている |

## サブエージェント委任仕様

該当なし。本スキルは他スキル・サブエージェントを呼ばず、単独でPhase 1〜4を完結させる。

## 重要な注意事項

- 本スキルは他スキル（syncing-reverse-env 等）を一切呼ばない。呼び出し・環境同期・基準タグ確立は管理者（orchestrating-reverse-docs-flow）が担う
- 他スキルの設定ファイル（`syncing-reverse-env/config.yml` 等）に書き込まない
- 開通済み画面の記帳（画面レジストリへの登録）は行わない。返却ブロックで管理者に情報を渡すのみ
- 責務は「画面の開通まで」。基準タグ確立・往復検証は本スキルの対象外（使用タイミングのSKIP参照）

## Gotchas

- 本スキルは「設計書がまだ無い」段階の画面が対象。設計書がある画面は `rebuilding-screen-unit-from-docs` / `rebuilding-code-from-docs` の対象であり本スキルは使わない
- モックAPIの適用範囲は「ログイン後まで表示可能にする」最小限に留める。往復検証相当の精緻な動作確認は行わない（それは後続工程の責務）

## 参照資料

- `~/agent-home/skills/orchestrating-reverse-docs-flow/references/contract.md` — 返却ブロック契約・args仕様・画面レジストリの正本
