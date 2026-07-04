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

スロット割当手順: 兄弟 worktree（`original-code-*` / `reverse-code-*`）を走査し、各ルート直下の `.reverse-port-slot`（番号 1 行）を読んで使用中スロットを把握する → 空いている最小番号を両 worktree のルートに書き込む（割当は `.reverse-slot-lock.d` の mkdir 原子ロックで排他する）。開発用 worktree のスロットファイル `.port-slot` とは誤カウント防止のため別名にしている。`max_slots`（既定 5）を超えて空きがない場合は ERROR。

互換注記: 旧固定表（frontend = オリジナル 9101 / リバース 9111）は廃止し、既定の slot 1 では frontend = オリジナル 9100 / リバース 9110 になる（稼働中環境が存在しないため移行措置は設けない）。

## mode とオプション

| mode | 局面 | 動作 |
|---|---|---|
| `setup` | 初回 | 両 worktree を作成し、パス・ブランチ・確定ポートを返す。比較しない |
| `sync`（既定） | 2 回目以降 | 検証 → 差分があれば整列 → 一致で基準タグ更新 |
| `teardown` | 検証終了時 | 当該 scope のスロット帯（連続 20 ポート）kill + worktree 削除。**ユーザーの明示依頼がある時だけ** |

sync のオプション: `dry-run`（整列・タグ更新なし）/ `reset-first`（開始前に `git reset --hard reverse-baseline/<scope>` で基準状態へ復帰）。

- **dry-run の無副作用対象**は「リバースコード環境の **git 管理内容**」と「基準タグ」の 2 つ。Phase 5（起動と観測）は dry-run でも実行し、静的比較が FAIL でも L1〜L4 まで計測して診断情報を最大化する。オリジナルコード環境の `source_ref` 復元（プリフライト）と証跡（スクリーンショット等の計測成果物）の書き出しは、無副作用の例外として dry-run でも行う。node_modules・バンドラキャッシュ等 git 管理外の生成物の修復（npm ci・キャッシュ削除）は dry-run でも行う
- **teardown の明示依頼確認**: 人間の直接起動なら AskUserQuestion で最終確認する。呼び出し元スキル経由なら args の `user-approved`（ユーザー依頼発話の引用）を必須とし、無ければ削除を実行せず status=ERROR（前提不成立）で差し戻す

入力は `design-doc`（画面詳細設計書パス）のみ必須（**全 mode 共通**。teardown でも `<scope>` 導出に使う）。任意: `mode` / `dry-run` / `reset-first` / `user-approved`（teardown 時のユーザー依頼発話の引用）/ `scenarios`（省略時は設計書 frontmatter の `scenarios`。旧 `route`（単一パス）は後方互換で `[{path: <パス>}]` に正規化する）/ `max-loop`（既定は config.yml の値）。mode 別の必須 args 検証は Phase 1 で行い、Phase 2 以降は環境操作に徹する。

## ツールリファレンス

| ツール | 用途 |
|---|---|
| Bash（`git worktree add/remove` / `diff -r` / ポート走査（lsof / ss。OS 別解決は guide §5） / `find -type l` / `git commit` / `git tag` / `git reset`） | worktree 物理作成・削除・静的比較・環境同一性チェック・基準コミットとタグ操作 |
| Playwright（MCP / node-script。config.yml の `playwright_exec.mode` で選択。詳細は guide §5・§7-3） | 動的比較 L1〜L4 |
| Read（`config.yml` / 設計書 frontmatter） | 可変値と検証パラメータの取得 |

## 基本ワークフロー

### Phase 1: 起動契約解決

args を検証し、本スキルフォルダの `config.yml` を Read する。設計書 frontmatter から `<system>`・`<画面ID>`・`<scope>`・`source_repo`・`source_ref`・`scenarios`（`name`/`path`/`query`/`path_params`/`ready`/`assert`/`mask` を持つ画面単位の正本。旧 `route` 単一パスは `[{path: <パス>}]` に正規化）を導出する。`doc_id` が `screen-` 接頭辞を持たない場合は ERROR（前提不成立）で停止する。config.yml の `projects` 上書きはスキーマ検証する（services 非空・各 service に launch・services 数 ≤ reverse_offset。違反は ERROR）。
完了条件: mode・design-doc・config 値・`<scope>` がすべて確定している

### Phase 2: 環境確保 + プリフライト

命名規則で両 worktree を検出し、無ければ `git worktree add` で本スキルが直接作成する（初回のみ。以後は再発見して使い回す。オリジナルは `--detach` で `source_ref` 固定、リバースは `-b feature/reverse-code-<scope>`。配置は `source_repo` の親ディレクトリ直下。通常開発用の worktree 管理の仕組みとは命名・配置規約が異なるため委譲しない）。再発見時は `git worktree list --porcelain` で prunable/破損を検出したら prune → 再作成で修復する。あわせてスロット割当手順（用語表のポートモデル節）で `<scope>` のスロット番号を確定する（割当は親ディレクトリの `.reverse-slot-lock.d` を mkdir する原子ロックで排他する）。`source_repo` はローカルリポジトリのパスを想定し、リモート URL の場合は clone を済ませてから worktree 化する。仕様書 §5 のプリフライト全項目（キー: design-doc-contract 〜 baseline-tag-exists）を検証し、NO-GO なら停止・報告する（`runtime-deps-ready` の依存インストール確認は sync のみ適用。setup 直後の空容器では Playwright 可用性の確認だけ行う）。worktree 名・ポートは常に本スキル自身の命名規則（`original-code-<scope>` / `reverse-code-<scope>`・動的スロット計算ポート）に従い、他スキルの固定名・固定ポートに合わせない。config.yml の `allow_mnt_fs` / `node_modules_strategy` / `playwright_exec.mode` / `node_path` は既定 `auto`（`node_path` は `null`）で、本 Phase が `fs-location`（drvfs 判定 → `allow_mnt_fs` を自動解決。`node_modules_strategy=auto` は drvfs 検出時も常に `npm_ci` に解決し、独立性を犠牲にする `symlink_main` への自動切替は行わない。drvfs 検出時は「`symlink_main` で高速化できるが node_modules の独立性の証明対象から外れる」旨を WARN 報告するに留める）・`runtime-deps-ready`（Playwright MCP 可用性 → `playwright_exec.mode` を自動解決。node-script 側は `node_path` を ① reverse worktree での `require.resolve('playwright')` 成功時のその解決先 → ② `npm root -g` 配下に playwright/ があればその node_modules → ③ npx キャッシュの実探索（`find "${npm_config_cache:-$HOME/.npm}/_npx" -type d -path '*/node_modules/playwright'` のヒット先の親 node_modules）→ ④ いずれも不在なら `runtime-deps-ready` を NO-GO とし人間に `node_path` 明示を促す、の順で自動解決する）で実行時検出して具体値へ解決する。明示値は auto の解決を上書きし、解決結果は Phase 8 の報告に含める。既定 auto のままなら projects への手入力は不要（`symlink_main` を使いたい場合のみ人間が明示指定する）。

- `mode=setup`: 両環境のパス・ブランチ・確定ポートを返して終了
- `mode=teardown`: 明示依頼を確認（人間なら AskUserQuestion、スキル経由なら args の `user-approved`）できた場合のみ、当該 `<scope>` のスロット帯（連続 20 ポート）を一括 kill → worktree を削除して終了（基準タグとブランチは残す＝基準コミットは消えない）。確認できなければ何も削除せず status=ERROR で差し戻す
- `mode=sync`: 基準タグの有無を確認（`git tag -l` + 参照先実在。なし・参照先不明は初回扱い）。`reset-first` 指定かつタグありなら `git reset --hard reverse-baseline/<scope>` してから Phase 3 へ。基準タグと reverse HEAD の乖離を検出したら件数を `baseline_tag` に付記する（reset-first は従来どおり opt-in）

完了条件: 両環境が存在し、プリフライト全項目がすべて GO

### Phase 3: 静的比較

config.yml の `diff_exclude` を除外して全ファイルを diff し、残差分行にポート正規化判定を適用する（オリジナル側の値をサービス index へ逆引きし、リバース側の同位置の値が `reverse = original + reverse_offset` の期待値と一致する場合のみ許容。数字が違うだけでは許容しない）。結果を「一致 / ポート差のみ / 実差分」の 3 分類で集計する。
完了条件: 3 分類の集計とファイル別内訳が記録されている

### Phase 4: 整列（実差分あり かつ dry-run でない時のみ）

① リバース側のポート設定ファイル群を退避 ② オリジナル → リバースへミラーコピー（削除同期あり・除外は Phase 3 準拠・`*.lock` は転写対象（除外しない）。git 操作ではなく**ファイル転写**で行い、両ブランチの歴史を混ぜない） ③ 当該 `<scope>` のスロットから算出したリバース側ポートでポート設定を再生成 ④ `node_modules_strategy`（`auto` は常に `npm_ci` に解決済み。`symlink_main` は人間が明示指定した時のみ発生する）分岐で依存を再構築（`npm_ci`: `install_command`（既定 npm ci）で各環境に独立インストール／`symlink_main`（明示指定時のみ）: source_repo の node_modules へ symlink を張る＝drvfs での npm ci 低速回避。独立性の証明対象からは除外＝§7-2 参照。失敗 = lock 不整合は ERROR） ⑤ `bundler_cache_dirs` のキャッシュを削除。
完了条件: 転写・ポート再生成・依存再構築が完了している

### Phase 5: 環境同一性チェック + 動的比較

起動前チェック → 両環境を固定ポートで起動 → 起動後チェック → scenario 単位の render-ready 到達確認 + 内容一致 + Playwright 4 層の順に実行する。判定基準の正は仕様書 §7。

- 環境同一性チェック（全項目とキーの正は guide §7-2。ポート帰属・混入・待受・symlink・依存ツリー・ランタイム・環境変数・env ファイル・ファイルモード・node_modules 健全性・キャッシュ鮮度・プロセス独立・ストレージ分離）
- scenario ごとに URL を構築する: `http://127.0.0.1:<port>` + `path`（`path_params` の `:名` を置換）+ `?` + `query`。`path`/`query` は両環境で同一、port だけスロット確定値に差し替える
- readiness gate（render-ready 到達確認）: navigate 後、scenario の `ready.selector` が可視になるまで待つ（`ready_timeout_ms`。無ければ `settle_wait_ms` フォールバック）。`loading_selectors`（config.yml 既定 ∪ `ready.not`）のいずれかが可視で残っていれば `NOT_RENDERED`（未到達）と判定する
- 内容抽出と **L2' 内容一致**: scenario の `assert.tables` / `assert.texts` 各セレクタの innerText を正規化して両環境で突合する。DB 内容・乱数・日時等は `mask` で除外する
- 動的比較 4 層: L1 起動（起動 かつ render-ready 到達）/ L2 構造スナップショット（ARIA。一次スクリーニングで単独では PASS 条件にしない）/ L3 画素比較（config.yml の閾値）/ L4 コンソールエラー集合
- 動的比較の実行手段は `playwright_exec.mode`（`auto` は Phase 2 で解決済みの `mcp` / `node-script` に従う）分岐。両手段は同一の内容 JSON 契約（`rendered`/`reason`/`tables`/`texts`）を出力する
  - `mcp`: `browser_navigate` → `browser_wait_for`（ready）→ `browser_evaluate` で loading 不可視確認と `assert.tables`/`assert.texts` の innerText 抽出 → `browser_take_screenshot` → `browser_snapshot` → `browser_console_messages`
  - `node-script`: scenario（url・readySelector・loadingSelectors=`loading_selectors` ∪ `ready.not`・assertTables・assertTexts）を JSON で一時ファイルに書き `CAP_SCENARIO` で渡す。config.yml の `command_template` を Bash 直実行し、`CAP_CONTENT` に内容 JSON（rendered/reason/tables/texts）を出力させる
- navigate 先の URL は必ず `127.0.0.1` を使う（`localhost` だと WSL2 の Chromium が名前解決待ちでタイムアウトする）
- `command_template` の `{nav_timeout}` / `{ready_timeout}` / `{settle_wait}` は config.yml の `playwright_exec.nav_timeout_ms` / `ready_timeout_ms` / `settle_wait_ms` から展開される。タイムアウト・L3 閾値・max_loop 等、プロジェクト毎に調整したい数値は `projects.<system>` で defaults を上書きできる（有効値 = defaults ← projects の深いマージ、projects 優先。画面単位はさらに設計書 frontmatter が優先）
- L1 失敗時は段階診断: ①ログ収集 → ②ポート再確認 → ③navigate を 1 回再試行 → ④なお失敗なら dev サーバープロセスを kill → 再起動して再試行（navigate 再試行だけでは直らない dependency re-optimize 起因のケースがあるため）→ ⑤それでも失敗で ERROR
- MCP も node-script（Playwright 実行環境）も利用不能な場合は動的検証そのものが実行不能。静的一致のみで PASS を宣言せず `DYNAMIC-UNVERIFIED` として Phase 6 へ渡す
- 起動した両環境は報告後も停止しない（定型文の確認 URL で人間がそのまま見比べられる状態を維持する）
- **静的一致・ARIA 構造一致だけでは PASS にしない**。両環境が同一スピナーで止まっていても（render-ready 未到達）PASS ではない

完了条件: env_check 全項目・全 scenario の render-ready 到達可否・内容一致・L1〜L4 の判定がすべて記録されている

### Phase 6: 収束判定

結果を PASS / FAIL / DESIGN-INCOMPLETE / ERROR / DYNAMIC-UNVERIFIED の 5 分類に落とす。

- **PASS**: 実差分 0 ∧ env_check 全通過 ∧ 全 scenario で両環境が render-ready 到達 ∧ 内容一致（L2'）∧ L2（ARIA）一致 ∧ L4 ∧ L3 閾値内。Phase 7 へ
- **FAIL**: 内容・構造・挙動のいずれかが食い違う。reverse 側だけ render-ready 未到達（reverse のみ NOT_RENDERED）も FAIL（再構築未完）。Phase 3 へ戻る（上限 `max_loop`。dry-run は 1 周で確定しループしない。同一の実差分集合が 2 周連続で残存したら上限を待たず FAIL 確定）
- **DESIGN-INCOMPLETE**: 両環境が同様に render-ready 未到達（引数不足でスピナー等のまま停止）。設計書 frontmatter の `scenarios` に `query`/`path_params`/`ready` の追加を促す hint を付けて呼び出し元へ差し戻す
- **ERROR**: 起動不能・依存不足など環境起因。FAIL と区別して報告する
- **DYNAMIC-UNVERIFIED**: MCP も node-script も利用不能で動的検証が実行不能。静的一致は報告するが PASS は宣言しない（「コードは同一の可能性が高いが描画・データ未検証」と明記）

完了条件: PASS 確定・FAIL 確定（上限到達）・DESIGN-INCOMPLETE・ERROR・DYNAMIC-UNVERIFIED のいずれかに到達している

### Phase 7: 基準確立（PASS かつ dry-run でない時のみ）

リバースコード環境の変更を `git add -A` → `git commit` で直接コミットし（メッセージは日本語 prefix 規約に従う。例: `【機能追加】整列結果を反映`）、基準タグを打つ。整列が走らず新規コミット対象が無い場合（最初から完全一致）はコミットをスキップし、リバースコード環境の現 HEAD に基準タグを打ち直す:

```bash
git tag -af "reverse-baseline/<scope>" -m "<検証日> 検証PASS: 実差分0 env_check 全項目PASS L1-L4全一致"
```

完了条件: 基準タグが新しい基準コミットを指している

### Phase 8: 結果報告

機械向け返却ブロック（`status` / `mode` / `scope` / `screen_id` / `slot` / `ports`（サービス別 original/reverse 実値） / `original_code` / `reverse_code` / `baseline_tag` / `static_diff` / `dynamic` / `env_check` / `artifacts` / `hint`）と、ユーザー向け定型文（確認 URL・検証内容・環境情報・再起動手順・片付け方法）の両方を出力する。`status` は `PASS` / `FAIL` / `ERROR` / `INCOMPLETE` のいずれかを取る。`INCOMPLETE` の内訳（設計書の引数・ready 不足による `DESIGN-INCOMPLETE` か、動的検証手段が無い `DYNAMIC-UNVERIFIED` か）はフィールドを増やさず `hint` に記す。`dynamic` には route/scenario 別に render-ready 到達可否と内容一致（L2'）の結果を含める。`DESIGN-INCOMPLETE` 時の `hint` には「`scenarios` に `query`/`path_params`/`ready` を追加」を出す。ユーザー向け定型文の環境情報には、Phase 2 で自動解決した `allow_mnt_fs` / `node_modules_strategy` / `playwright_exec.mode` / `node_path` の解決結果と根拠（drvfs 検出・MCP 可用性）を含める。`artifacts` の保存先は `<artifacts_root>/<scope>/<実行日時>/`（scenario 別サブディレクトリ）。書式の正は仕様書 §8。setup / teardown / ERROR の早期終了時も返却ブロックの形を保ち、未実施フィールドは「未実施」と記す。FAIL 時の `hint`（差分ファイル → 設計書章マップの対応推定）が rebuilding-code-from-docs スキルの修正ループ入力になる。
完了条件: 返却ブロックと定型文の両方が出力されている

## ループ設計

| 要素 | 内容 |
|---|---|
| 反復条件 | Phase 6 で FAIL（実差分・挙動差分が残存）なら Phase 3 へ戻って再比較する |
| 上限回数 | config.yml の `max_loop`（既定 3） |
| 停止条件 | ① 収束停止: PASS 到達で即確定（判定は決定的ツール出力のため連続確認は不要）② リソース上限: `max_loop` 到達で FAIL 確定 ③ 発散検知: 同一の実差分集合が 2 周連続で残存したら上限を待たず FAIL 確定 |

検証役の分離: 判定は diff・ポート走査（lsof / ss）・Playwright という決定的なツール出力のみで行い、生成役（整列処理）の自己申告では判定しない。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | mode・design-doc・config 値が確定 |
| Phase 2 | 両環境が存在しプリフライト全項目 GO（setup / teardown はここで正常終了） |
| Phase 3 | 差分の 3 分類集計が記録済み |
| Phase 4 | 転写・ポート再生成・依存再構築が完了 |
| Phase 5 | env_check 全項目・全 scenario の render-ready 到達可否・内容一致・L1〜L4 の判定が記録済み |
| Phase 6 | PASS / FAIL / DESIGN-INCOMPLETE / ERROR / DYNAMIC-UNVERIFIED のいずれかに確定 |
| Phase 7 | 基準タグが新基準コミットを指している |
| Phase 8 | 返却ブロックと定型文の両方を出力済み |
| **Goal** | 静的実差分 0 ＋ env_check 全通過 ＋ 全 scenario で render-ready 到達 ＋ 内容一致（＋ ARIA・L4・L3）が揃って初めて status=PASS で基準タグが確立している。静的一致のみ・ARIA 一致のみでは PASS にしない（FAIL / DESIGN-INCOMPLETE / ERROR / DYNAMIC-UNVERIFIED 時は原因分類と hint 付きで呼び出し元へ差し戻せている） |

## 重要な注意事項

- オリジナルコード環境の内容を変更しない。汚れ・ズレは `source_ref` へ自動復元する（worktree 自体・名前・ポートは保持）
- worktree は初回のみ作成し、削除は teardown（ユーザーの明示依頼）だけ。本スキルが自発的に削除することはない
- 画面スロット制のため最大 5 画面まで並行検証できる（slot 1〜5、各 20 ポート帯）。プロジェクト単位でベース帯域を変えたい場合は config.yml の `projects` 上書きを使う（タイムアウト等の数値パラメータも同様に defaults を projects で上書きできる）
- dry-run はリバースコード環境の git 管理内容にも基準タグにも触れない（git 管理外生成物の修復＝npm ci・キャッシュ削除は許容）
- ERROR（環境起因）と FAIL（差分）を必ず区別して報告する。混同すると呼び出し元が「設計書の不備」と誤解釈する
- 静的一致・ARIA 構造一致だけでは PASS にしない。render-ready 到達と内容一致（L2'）が揃って初めて PASS の前提が成り立つ（両環境が同一スピナーで止まっていても PASS ではない）
- WSL2 では worktree を Linux ネイティブ FS（~/ 配下）に置くのが推奨。/mnt/* 配下（drvfs）は `allow_mnt_fs=auto`（既定）なら検出時に性能 WARN として自動で続行する（drvfs 上でも動くが低速）。`allow_mnt_fs: false` を明示した時だけ ERROR で止める。詳細は guide §5
- 環境固有値（allow_mnt_fs / node_modules_strategy / playwright_exec.mode / node_path）は既定 auto で自動検出されるため、WSL2 でも人間が config.yml に値を書く必要はない。projects の明示指定は auto の判定を強制的に上書きしたい時だけ使う

## Gotchas

- 「完全一致」の証明は独立した 2 環境が前提。symlink・プロセス・DB を共有していたら一致して見えて当然で、証明にならない（env_check の独立性 4 項目がこれを守る）
- 基準コミットの実体は worktree ではなくリポジトリ本体にある。teardown で worktree を消しても、基準タグが指す限り gc でも消えない
- ポート差の許容は「計算式どおりの original→reverse 対応」のみ。数字が違うだけの行を許容すると、ポートのハードコードミスを見逃す
- `node_modules_strategy=symlink_main` は node_modules/.vite も source_repo と共有するため、初回 navigate が dependency re-optimize 中の reload に巻き込まれてタイムアウトすることがある。navigate の再試行だけでは解消しないことがあり（実測: 6 回連続失敗）、その場合は dev サーバープロセス自体を kill → 再起動すると解消する（L1 失敗診断の段階手順で対応）
- 独立性を犠牲にする `symlink_main` は auto では自動選択されない。速度が必要なら人間が明示 opt-in する（drvfs 検出時は WARN で選択肢を提示するのみ）

## 設計判断

### audit-doc-consistency.sh

**必要性**: 本スキルの仕様は guide.html（正本）・SKILL.md・concept.html・config.yml の 4 ファイルに分散しており、検査項目キー（プリフライト・env_check）・config キー・返却フィールドの追従漏れが改訂のたびに発生しうる。キー突合・陳腐化表現（個数直書き・OS 依存コマンドの単独前提）・config 整合・返却ブロック契約の 4 検査を機械化し、改訂後に必ず実行する回帰ゲートとする。

**代替案を採用しなかった理由**:
- Bash ツール直叩き: 4 検査 × 対象 4 ファイルの grep/突合をセッション内で都度書くとトークン消費が大きく、検査の再現性が失われる
- 既存 Makefile ターゲット拡張: 本スキルはプロジェクト非依存のグローバルスキルであり、プロジェクト Makefile には置けない
- rebuilding-code-from-docs の audit-consistency.sh 拡張: 同スクリプトは設計書 .md の章マップ・観点表突合に特化しており、本スキルの HTML/YAML 構成とは検査対象も正本も異なる

**保守責任者**: 人手（ユーザー）。検査項目キー・config キー・返却フィールドの追加変更時に同時更新する。

**廃棄条件**: 仕様の正本が単一ファイルに統合されキー突合が不要になった時、または本スキルが廃止された時。

## 参照資料

- `config.yml` — ポート計算式・サービス一覧・起動コマンド・diff 除外・L3 閾値・max_loop の可変値（本スキルフォルダ直下）
- `references/syncing-reverse-env-guide.html` — 確定仕様（プリフライト全項目・env_check 全項目・報告書式の正）
- `references/syncing-reverse-env-concept.html` — 設計判断（ADR）と検討過程の記録
- `scripts/audit-doc-consistency.sh` — ドキュメント整合性監査（改訂後の回帰ゲート）
