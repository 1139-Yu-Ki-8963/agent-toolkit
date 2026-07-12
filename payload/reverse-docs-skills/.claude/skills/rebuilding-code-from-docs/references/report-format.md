# 修正指示書・最終報告の書式

Phase 8（修正指示書）と Phase 9（最終報告）の書式の正。配置先は `<verification_dir>/screen-<画面ID>/<timestamp>/`（`verification_dir` は docs と同階層の `verification/`。正本は `../references/contract.md` の「プレースホルダ定義」）。生証跡（スクリーンショット・テストログ・返却ブロック全文）も同じ `<verification_dir>/screen-<画面ID>/<timestamp>/` 配下に同梱し、指示書・報告からは同ディレクトリ内の相対パスで参照する。設計書リポジトリ外のセッション記録フォルダへの配置・参照は廃止。

## 修正指示書（Phase 8）

ファイル名: `<verification_dir>/screen-<画面ID>/<timestamp>/修正指示書.md`

```markdown
# 修正指示書

## 対象設計書パス

<設計書の相対パス>

## NG 一覧

| 失敗クラス | 帰着（役割・既定§） | 修正指示 | 根拠となる証跡パス |
|---|---|---|---|
| <ng-classification.md の失敗クラスキー> | <役割キー（既定 §番号）> | <具体的に何をどう書き足すか> | <verification_dir>/screen-<画面ID>/<timestamp>/ 配下の証跡ファイルパス |

NG が 0 件の場合は「NG なし」と明記し、上記表は省略する。

## テンプレート改善提案（あれば）

| 提案内容 | 対応する test-item-patterns.md エントリ |
|---|---|
| <テンプレート側に足すべき記載パターン> | <パターンキー> |

該当なしの場合は「テンプレート改善提案なし」と明記する。
```

### 記入時の注意

- 修正指示は「設計書の該当章に何を書き足せば実装が一意に定まったか」を具体的に書く。抽象的な「もっと詳しく書け」は禁止
- コード修正・設計書修正は本書には含めない（本書自体が指示書であり実行物ではない）
- 根拠となる証跡パスは必ず実在するファイルを指す（Phase 7 の返却ブロック・Playwright スクリーンショット等）
- 帰着章が対象設計書に未存在の場合、指示書には「当該章を新設して書き足す」内容として記述する（設計書自体は修正しない）

## 最終報告（Phase 9）

ファイル名: `<verification_dir>/screen-<画面ID>/<timestamp>/最終報告.md`

```markdown
# 最終報告

## 判定

PASS / FAIL / INCOMPLETE（`DESIGN-INCOMPLETE` または `DYNAMIC-UNVERIFIED` 由来。往復検証未完了として扱い PASS 扱いにしない）/ 無効（凍結検証失敗時）

## 著述スコープ

完全著述 / 部分著述（対象ファイル<n>件/全<m>件）

## 凍結コミットハッシュ

<Phase 6 で確定したハッシュ>

## 各 Phase の実行結果

| Phase | 結果 | 備考 |
|---|---|---|
| Phase 1 | 実施 | <基準タグ確認結果> |
| Phase 2 | 実施 | <内部整合性監査結果> |
| Phase 3 | 実施 | <白紙化コミットハッシュ> |
| Phase 4 | 実施 / [未実行] | <実装結果> |
| Phase 5 | 実施 / [未実行] | <検証結果> |
| Phase 6 | 実施 / [未実行] | <凍結コミットハッシュ> |
| Phase 7 | 実施 / [未実行] | <compare_result 要約> |
| Phase 8 | 実施 | <修正指示書パスまたは「NG なし」> |
| Phase 9 | 実施 | 本報告自体 |

`[未実行]` が 0 件であることを明示する（Phase 2 で内部矛盾により Phase 4 以降をスキップした場合は、その旨と理由をここに明記した上で `[未実行]` として扱う）。

## テスト実行結果

配置・納品された全テストの実行結果を、テストファイルが公開する識別子（test 名 / id）ごとに列挙する。連番 ID を発明せず、テストファイルが持つ識別子をそのまま使う。

| テストケース識別子（test 名 / id） | 種別（単体/結合/E2E） | 結果（PASS / FAIL / 未実施） |
|---|---|---|
| <テストファイルが公開する識別子> | <単体 / 結合 / RT / SM / IT / CMP> | <PASS / FAIL / 未実施> |

- 未実施が 1 件でもあれば `status=PASS` にできない（部分実装のまま PASS 報告することを禁止する）
- 納品されていない E2E 系スクリプトは「未実施」として計上し、PASS 判定の根拠に数えない

## compare_result 要約

- status: <PASS/FAIL/ERROR/DESIGN-INCOMPLETE/DYNAMIC-UNVERIFIED>
- static_diff: <3 分類の集計>
- dynamic: <L1〜L5 の判定（render-ready 到達可否・assert.tables/texts の内容一致・L5 操作シーケンス後の postContent 一致を含む。L5 は operations を持つ画面のみ）>
- env_check: <全項目の通過数>
- env_check 実施水準: <完全（正式13項目チェックリストを全実施）／簡略（一部項目のみ実施）／未実施>。完全以外は判定を `DYNAMIC-UNVERIFIED` として扱う
- hint: <あれば>
- incomplete_reason: <status が DESIGN-INCOMPLETE または DYNAMIC-UNVERIFIED の場合のみ内訳を記入（例: scenarios の query/path_params 不足によるスピナー未到達／MCP・Playwright とも不在）>

## 凍結検証結果

`scripts/check-freeze.sh` の実行結果（PASS/FAIL）。FAIL の場合は判定を「無効」とし、理由（HEAD 不一致 / 作業ツリー汚染）を明記する。

## 証跡パス一覧

| 証跡種別 | パス |
|---|---|
| Phase 7 返却ブロック全文 | <verification_dir>/screen-<画面ID>/<timestamp>/ 配下のパス |
| Playwright スクリーンショット | <verification_dir>/screen-<画面ID>/<timestamp>/ 配下のパス |
| テストログ | <verification_dir>/screen-<画面ID>/<timestamp>/ 配下のパス |
```

### PASS 時の基準タグ更新

本スキルは基準タグ更新を実行しない。PASS かつ凍結検証 PASS の場合、最終報告に「基準タグ更新は管理者が比較エンジンの本番実行（非 dry-run）で行う」旨を明記する。
