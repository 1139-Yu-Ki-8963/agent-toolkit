---
name: syncing-reverse-env
description: |
  リバース元/設計書2環境同期・検証・基準コミット確立。
  TRIGGER when: setup/sync/teardown・baseline操作。
  SKIP: 設計書修正（→rebuilding-code-from-docs）。
invocation: syncing-reverse-env
type: orchestration
allowed-tools: [Bash, Read, Write, Edit, Grep, Glob, AskUserQuestion]
---

# リバース環境同期スキル

オリジナルコード環境（リバース元・常に「正」）と、リバースコード環境（設計書だけから再構築）の 2 つの worktree を用意・名前管理し、「ポート番号以外は完全同一」であることを検証して、一致証明済みの基準コミット（基準タグ `reverse-baseline/<scope>`）を確立する。共有アプリを画面単位で最大 5 画面まで並行検証できるよう、worktree・ブランチ・基準タグ・ポートはすべて `<scope>`（`<system>-<画面ID>`）単位で管理する。

仕様の正は `references/syncing-reverse-env-guide.html`（確定仕様）。設計判断（ADR）の記録は `references/syncing-reverse-env-concept.html`。

## 使用タイミング

- rebuilding-code-from-docs スキルが Skill ツールで呼び出す。args 全量指定・**対話ゼロで完走**が契約（AskUserQuestion を発行しない）
- 人間が直接起動する。`design-doc` だけ渡せば起動できる
- worktree のパスは引数で受け取らない。環境は本スキルが命名規則から導出・確保する

## 環境と用語

| 名前 | 実体 |
|---|---|
| `<system>` | 設計書 frontmatter の `source_repo` 末尾のリポジトリ名（`.git` 除去）から機械的に導出する |
| `<画面ID>` | 設計書 frontmatter `doc_id: screen-<画面ID>` から `screen-` 接頭辞を除去して導出する |
| `<scope>` | `<system>-<画面ID>`。worktree・ブランチ・基準タグ・ポートスロットの管理単位（共有アプリを画面単位で最大 5 画面まで並行検証するため） |
| オリジナルコード環境 | worktree 名 `original-code-<scope>`。設計書 frontmatter の `source_repo` / `source_ref` から用意する読み取り専用コピー。内容を変更しない |
| リバースコード環境 | worktree 名 `reverse-code-<scope>`、ブランチ `feature/reverse-code-<scope>`。容器は本スキルが用意し、中身は rebuilding-code-from-docs スキルが書く |
| 基準タグ | annotated tag `reverse-baseline/<scope>`。基準コミットの唯一の記録。タグメッセージに検証日と判定サマリを持つ |

## ポートモデル（`config.yml` が正・プロジェクト非依存）

worktree は初回に一度だけ作成し、teardown まで使い回す。ポートは `<scope>` ごとに動的割当てするスロット単位で決まる:

```
slot k = 1..5（動的割当）
original = band_start + slot_stride×(k-1) + サービス index
reverse  = original + reverse_offset
既定: band_start=9100, slot_stride=20, reverse_offset=10
→ slot k の占有帯 = [9100+20(k-1), 9119+20(k-1)]（連続 20 ポート）
```

サービス index は `config.yml` の `services` 配列の並び順（既定 `[frontend]` → index 0）。

スロット割当手順: 兄弟 worktree（`original-code-*` / `reverse-code-*`）を走査し、各ルート直下の `.reverse-port-slot`（番号 1 行）を読んで使用中スロットを把握する → 空いている最小番号を両 worktree のルートに書き込む。開発用 worktree のスロットファイル `.port-slot` とは誤カウント防止のため別名にしている。`max_slots`（既定 5）を超えて空きがない場合は ERROR。

互換注記: 旧固定表（frontend = オリジナル 9101 / リバース 9111）は廃止し、既定の slot 1 では frontend = オリジナル 9100 / リバース 9110 になる（稼働中環境が存在しないため移行措置は設けない）。

## mode とオプション

| mode | 局面 | 動作 |
|---|---|---|
| `setup` | 初回 | 両 worktree を作成し、パス・ブランチ・確定ポートを返す。比較しない |
| `sync`（既定） | 2 回目以降 | 検証 → 差分があれば整列 → 一致で基準タグ更新 |
| `teardown` | 検証終了時 | 当該 scope のスロット帯（連続 20 ポート）kill + worktree 削除。**ユーザーの明示依頼がある時だけ** |

sync のオプション: `dry-run`（整列・タグ更新なし）/ `reset-first`（開始前に `git reset --hard reverse-baseline/<scope>` で基準状態へ復帰）。

- **dry-run の無副作用対象**は「リバースコード環境の内容」と「基準タグ」の 2 つ。Phase 5（起動と観測）は dry-run でも実行し、静的比較が FAIL でも L1〜L4 まで計測して診断情報を最大化する。オリジナルコード環境の `source_ref` 復元（プリフライト）と証跡（スクリーンショット等の計測成果物）の書き出しは、無副作用の例外として dry-run でも行う
- **teardown の明示依頼確認**: 人間の直接起動なら AskUserQuestion で最終確認する。呼び出し元スキル経由なら args の `user-approved`（ユーザー依頼発話の引用）を必須とし、無ければ削除を実行せず status=ERROR（前提不成立）で差し戻す

入力は `design-doc`（画面詳細設計書パス）のみ必須（**全 mode 共通**。teardown でも `<scope>` 導出に使う）。任意: `mode` / `dry-run` / `reset-first` / `user-approved`（teardown 時のユーザー依頼発話の引用）/ `routes`（省略時は設計書 frontmatter の `route`）/ `max-loop`（既定は config.yml の値）。mode 別の必須 args 検証は Phase 1 で行い、Phase 2 以降は環境操作に徹する。

## ツールリファレンス

| ツール | 用途 |
|---|---|
| Bash（`git worktree add/remove` / `diff -r` / `lsof -i` / `find -type l` / `git commit` / `git tag` / `git reset`） | worktree 物理作成・削除・静的比較・環境同一性チェック・基準コミットとタグ操作 |
| Playwright MCP（navigate / snapshot / screenshot / console_messages） | 動的比較 L1〜L4 |
| Read（`config.yml` / 設計書 frontmatter） | 可変値と検証パラメータの取得 |

## 基本ワークフロー

### Phase 1: 起動契約解決

args を検証し、本スキルフォルダの `config.yml` を Read する。設計書 frontmatter から `<system>`・`<画面ID>`・`<scope>`・`source_repo`・`source_ref`・`routes` を導出する。`doc_id` が `screen-` 接頭辞を持たない場合は ERROR（前提不成立）で停止する。
完了条件: mode・design-doc・config 値・`<scope>` がすべて確定している

### Phase 2: 環境確保 + プリフライト

命名規則で両 worktree を検出し、無ければ `git worktree add` で本スキルが直接作成する（初回のみ。以後は再発見して使い回す。オリジナルは `--detach` で `source_ref` 固定、リバースは `-b feature/reverse-code-<scope>`。配置は `source_repo` の親ディレクトリ直下。通常開発用の worktree 管理の仕組みとは命名・配置規約が異なるため委譲しない）。あわせてスロット割当手順（用語表のポートモデル節）で `<scope>` のスロット番号を確定する。`source_repo` はローカルリポジトリのパスを想定し、リモート URL の場合は clone を済ませてから worktree 化する。仕様書 §5 のプリフライト 7 項目を検証し、NO-GO なら停止・報告する（#6 の依存インストール確認は sync のみ適用。setup 直後の空容器では Playwright 可用性の確認だけ行う）。

- `mode=setup`: 両環境のパス・ブランチ・確定ポートを返して終了
- `mode=teardown`: 明示依頼を確認（人間なら AskUserQuestion、スキル経由なら args の `user-approved`）できた場合のみ、当該 `<scope>` のスロット帯（連続 20 ポート）を一括 kill → worktree を削除して終了（基準タグとブランチは残す＝基準コミットは消えない）。確認できなければ何も削除せず status=ERROR で差し戻す
- `mode=sync`: 基準タグの有無を確認（`git tag -l` + 参照先実在。なし・参照先不明は初回扱い）。`reset-first` 指定かつタグありなら `git reset --hard reverse-baseline/<scope>` してから Phase 3 へ

完了条件: 両環境が存在し、プリフライト 7 項目がすべて GO

### Phase 3: 静的比較

config.yml の `diff_exclude` を除外して全ファイルを diff し、残差分行にポート正規化判定を適用する（オリジナル側の値をサービス index へ逆引きし、リバース側の同位置の値が `reverse = original + reverse_offset` の期待値と一致する場合のみ許容。数字が違うだけでは許容しない）。結果を「一致 / ポート差のみ / 実差分」の 3 分類で集計する。
完了条件: 3 分類の集計とファイル別内訳が記録されている

### Phase 4: 整列（実差分あり かつ dry-run でない時のみ）

① リバース側のポート設定ファイル群を退避 ② オリジナル → リバースへミラーコピー（削除同期あり・除外は Phase 3 準拠。git 操作ではなく**ファイル転写**で行い、両ブランチの歴史を混ぜない） ③ 当該 `<scope>` のスロットから算出したリバース側ポートでポート設定を再生成 ④ 依存を再インストール。
完了条件: 転写・ポート再生成・依存再構築が完了している

### Phase 5: 環境同一性チェック + 動的比較

起動前チェック → 両環境を固定ポートで起動 → 起動後チェック → Playwright 4 層の順に実行する。判定基準の正は仕様書 §7。

- 環境同一性 10 項目: ポート占有の帰属（lsof）/ 相手帯域ポートの混入（相互 grep）/ 実際の待受ポート / symlink の実態（find + realpath）/ 依存ツリー / ランタイム / 環境変数 / ファイルモード / プロセス独立性 / ストレージ分離
- 動的比較 4 層: L1 起動 / L2 構造スナップショット（完全一致・一次判定）/ L3 画素比較（config.yml の閾値）/ L4 コンソールエラー集合
- 起動した両環境は報告後も停止しない（定型文の確認 URL で人間がそのまま見比べられる状態を維持する）

完了条件: env_check 10 項目と L1〜L4 の判定がすべて記録されている

### Phase 6: 収束判定

PASS（実差分 0・env_check 全通過・L1∧L2∧L4 かつ L3 閾値内）なら Phase 7 へ。FAIL なら Phase 3 へ戻る（上限 `max_loop`。dry-run は 1 周で確定しループしない）。環境起因の問題は FAIL と区別して ERROR に分類する。
完了条件: PASS 確定・FAIL 確定（上限到達）・ERROR のいずれかに到達している

### Phase 7: 基準確立（PASS かつ dry-run でない時のみ）

リバースコード環境の変更を `git add -A` → `git commit` で直接コミットし（メッセージは日本語 prefix 規約に従う。例: `【機能追加】整列結果を反映`）、基準タグを打つ。整列が走らず新規コミット対象が無い場合（最初から完全一致）はコミットをスキップし、リバースコード環境の現 HEAD に基準タグを打ち直す:

```bash
git tag -af "reverse-baseline/<scope>" -m "<検証日> 検証PASS: 実差分0 env_check 10/10 L1-L4全一致"
```

完了条件: 基準タグが新しい基準コミットを指している

### Phase 8: 結果報告

機械向け返却ブロック（`status` / `mode` / `scope` / `screen_id` / `slot` / `ports`（サービス別 original/reverse 実値） / `original_code` / `reverse_code` / `baseline_tag` / `static_diff` / `dynamic` / `env_check` / `artifacts` / `hint`）と、ユーザー向け定型文（確認 URL・検証内容・環境情報・再起動手順・片付け方法）の両方を出力する。書式の正は仕様書 §8。setup / teardown / ERROR の早期終了時も返却ブロックの形を保ち、未実施フィールドは「未実施」と記す。FAIL 時の `hint`（差分ファイル → 設計書章マップの対応推定）が rebuilding-code-from-docs スキルの修正ループ入力になる。
完了条件: 返却ブロックと定型文の両方が出力されている

## ループ設計

| 要素 | 内容 |
|---|---|
| 反復条件 | Phase 6 で FAIL（実差分・挙動差分が残存）なら Phase 3 へ戻って再比較する |
| 上限回数 | config.yml の `max_loop`（既定 3） |
| 停止条件 | ① 収束停止: PASS 到達で即確定（判定は決定的ツール出力のため連続確認は不要）② リソース上限: `max_loop` 到達で FAIL 確定 ③ 発散検知: 同一の実差分集合が 2 周連続で残存したら上限を待たず FAIL 確定 |

検証役の分離: 判定は diff・lsof・Playwright という決定的なツール出力のみで行い、生成役（整列処理）の自己申告では判定しない。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | mode・design-doc・config 値が確定 |
| Phase 2 | 両環境が存在しプリフライト 7 項目 GO（setup / teardown はここで正常終了） |
| Phase 3 | 差分の 3 分類集計が記録済み |
| Phase 4 | 転写・ポート再生成・依存再構築が完了 |
| Phase 5 | env_check 10 項目と L1〜L4 の判定が記録済み |
| Phase 6 | PASS / FAIL / ERROR のいずれかに確定 |
| Phase 7 | 基準タグが新基準コミットを指している |
| Phase 8 | 返却ブロックと定型文の両方を出力済み |
| **Goal** | status=PASS で基準タグが確立している（FAIL / ERROR 時は原因分類と hint 付きで呼び出し元へ差し戻せている） |

## 重要な注意事項

- オリジナルコード環境の内容を変更しない。汚れ・ズレは `source_ref` へ自動復元する（worktree 自体・名前・ポートは保持）
- worktree は初回のみ作成し、削除は teardown（ユーザーの明示依頼）だけ。本スキルが自発的に削除することはない
- 画面スロット制のため最大 5 画面まで並行検証できる（slot 1〜5、各 20 ポート帯）。プロジェクト単位でベース帯域を変えたい場合は config.yml の `projects` 上書きを使う
- dry-run はリバースコード環境にも基準タグにも一切触れない（完全無副作用）
- ERROR（環境起因）と FAIL（差分）を必ず区別して報告する。混同すると呼び出し元が「設計書の不備」と誤解釈する

## Gotchas

- 「完全一致」の証明は独立した 2 環境が前提。symlink・プロセス・DB を共有していたら一致して見えて当然で、証明にならない（env_check の独立性 4 項目がこれを守る）
- 基準コミットの実体は worktree ではなくリポジトリ本体にある。teardown で worktree を消しても、基準タグが指す限り gc でも消えない
- ポート差の許容は「計算式どおりの original→reverse 対応」のみ。数字が違うだけの行を許容すると、ポートのハードコードミスを見逃す

## 参照資料

- `config.yml` — ポート計算式・サービス一覧・起動コマンド・diff 除外・L3 閾値・max_loop の可変値（本スキルフォルダ直下）
- `references/syncing-reverse-env-guide.html` — 確定仕様（プリフライト 7 項目・env_check 10 項目・報告書式の正）
- `references/syncing-reverse-env-concept.html` — 設計判断（ADR）と検討過程の記録
