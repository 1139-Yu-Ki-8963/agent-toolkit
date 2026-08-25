**状態**: 着手できる
**優先度**: 中
**前提**: なし
**元の指摘**: 1-205

## この指示書は何か

`build-portal.sh` の自己テストケース49（孤立HTMLの削除機構を検証する。1-205 対応）が使う固定パスがある。この固定パスは、1-208・1-209でproject-portal配下を英数字化した。英数字化した後の実際の出力先と一致しない。固定パスを現在の定義に合わせる。

## なぜ必要か

`bash generation-engine/scripts/build-portal.sh --self-test --case 49` を実行する。実行すると、49a〜49cはPASSする。49dで次のFAILが出て止まる。

```
FAIL: --self-test ケース49d（mdとhtmlの置き場が異なる共通文書を誤って削除した）
```

原因は `run_orphaned_html_self_test` 関数内の固定パスである。3変数が現在の定義と食い違っている。

- `separated_html`
  - 現在の値: `$test_portal/基盤/共通設計書.html`
  - 実際の出力先: `$test_portal/foundation/共通設計書.html`
- `old_screen_html`
  - 現在の値: `$test_portal/画面/screen-orphan/基本設計/画面基本設計書.html`
  - 実際の出力先: `$test_portal/screens/screen-orphan/基本設計/画面基本設計書.html`
- `release_notes_html`
  - 現在の値: `$test_portal/基盤/リリースノート.html`
  - 実際の出力先: `$test_portal/foundation/リリースノート.html`

`output-layout.json` の `layout.foundationDir` は `project-portal/foundation` である。`layout.screenViewRoot` は `project-portal/screens` である。どちらも1-208・1-209で英数字化済みである。

手動で合成フィクスチャを再現し、実際の生成物の置き場を確認した。生成先は次のとおりだった。

```
project-portal/foundation/共通設計書.html
project-portal/screens/screen-orphan/基本設計/画面基本設計書.html
```

一方、自己テストの `separated_html` は「基盤」のままである。`separated_html` は、mdとhtmlの置き場が異なる共通文書がある。削除ロジックが誤ってこれを消さないかを確かめる変数である。その存在確認は、実在しないパスを見に行く。このため49dは常にFAILする。

`old_screen_html` は逆の問題を持つ。この変数は「存在しないこと」だけを確認する。実在しないパスを見に行くため、確認は常に真になる。実際に削除すべき `project-portal/screens/...` を見ない。同じ条件式にあるWARN文字列の比較は正しい値を見ている。49dが直れば49fは見かけ上PASSしうる。ただし `old_screen_html` 自体は検証として機能していない。

放置すると、ケース49（1-205の唯一の自己テスト）を実行できないまま残す。孤立HTML削除機構に将来手を入れたときの回帰検知ができなくなる。49e以降（49e〜49i）も49dで停止する。実行されないまま埋もれている。

## やること

1. `generation-engine/scripts/build-portal.sh` に `run_orphaned_html_self_test` がある。この関数内に3変数がある。3変数とは `separated_html`・`old_screen_html`・`release_notes_html` である。これらを `output-layout.json` の現在の値に合わせて書き換える
2. `old_screen_html` を実際に削除対象になるパスへ直す。直したうえで確認する。`[ -e "$old_screen_html" ]` の確認が意味のある検証になっていることを確かめる
3. ケース49をa〜iまで通しで実行し、全件PASSすることを確認する
4. 同じ関数内に他の固定パスがある。対象は `old_html`・`new_html`・`orphan_html`・`late_orphan_html` である。これらは対象外とする。`common_dir`（`docs/design/common`）配下である。project-portal配下の英数字化とは無関係である

## 完了の判定

1. `bash generation-engine/scripts/build-portal.sh --self-test --case 49` を実行する。実行すると終了コード0で終わる
2. 出力に `PASS: --self-test ケース49a` から `ケース49i` までが、すべて現れる
3. `run_orphaned_html_self_test` 関数の行範囲を見る。project-portal配下のパスに使う「基盤」「画面」の直書きがあるかを見る。この直書きが0件になる

## 触らない範囲

- `remove_orphaned_common_html` 関数の本体ロジック
- `detect_stale_portal_placeholders`（1-209の検出関数）
- `detect_undefined_unit_phase_dirs`（1-210の検出関数）
- ケース3・7・8・9・12・13・25・48等がある。他の自己テストケースが使う旧名フィクスチャである。1-209で意図的に残すと判断済みである。あちらはフィクスチャの生成側での旧名使用である。本件のような実際の出力先との比較確認ではない
- `output-layout.json` の値そのもの
- `docs/tasks/` 配下、`delivery-payload/` 配下

## 決めていないこと

| 何を決めるか | 既定（迷ったらこれを選ぶ） | 覆すときの条件 |
|---|---|---|
| 固定パスの書き換え方法 | `output_layout_get` 等の既存ヘルパーは使わない。動的に値を取得せず、現在の定義値を直接埋め込む。他のフィクスチャ変数と同じ書き方に揃える。 | 今後、`foundationDir`・`screenViewRoot` の値が変わることがある。変わるたびに同じ修正が必要なら、動的取得へ切り替える |
| `old_screen_html` の検証強化の要否 | 3変数の書き換えだけを行う。`[ -e ]` チェックの追加強化は行わない。 | 書き換え後も49fが検証として機能していないと分かった場合 |

## 他の指示書との関係

1-209・1-210の作業がproject-portal配下のディレクトリ名を英数字化した。この変更に1-205の自己テストが追従できなくなった。本件はその追従だけを行う。

## この指示書の位置づけ

孤立HTML削除機構そのもの（`remove_orphaned_common_html`）は実装済みである。手動再現でも正しく動作することを確認済みである。本件は実装の不備ではない。自己テストのフィクスチャが、後続の変更（1-208・1-209）に追従していない。検証手段側の不備を扱う。この粒度に切り出した理由がある。実装の変更と検証の変更を同じコミットで混ぜないためである。混ぜると、どちらが原因で挙動が変わったのか追えなくなる。

## 対応の記録

### 判定の充足状況

| 判定 | 確かめる手段 | 状態 | コミット | 確かめた内容 |
|---|---|---|---|---|
| 1. 自己テストの通過 | `bash generation-engine/scripts/build-portal.sh --self-test --case 49` | 完了 | 74838867635e3c4a3e88d19ef26ae64feddad646 | rc=0。49a〜49iが全てPASS。 |
| 2. 全ケースPASS | `bash docs/scripts/check-case49-orphan-html.sh --count-pass` | 完了 | 74838867635e3c4a3e88d19ef26ae64feddad646 | PASS件数9/9。 |
| 3. 旧ディレクトリ名の直書きが無い | `bash docs/scripts/check-case49-orphan-html.sh --stale-paths` | 完了 | 74838867635e3c4a3e88d19ef26ae64feddad646 | 直書き0件。 |

### 判断の記録

| 何を決めたか | 選んだもの | 選んだ理由 | 覆すと何が変わるか |
|---|---|---|---|
| release_notes_htmlを作る時機 | post-build後に作る（--post-buildで生成する） | foundationへ揃えるとbuild本体のstale判定と衝突したため | 衝突が再発し、ケース49が49gの手前で停止する |
