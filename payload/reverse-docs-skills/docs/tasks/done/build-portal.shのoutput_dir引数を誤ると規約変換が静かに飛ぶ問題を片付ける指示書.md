# build-portal.shのoutput_dir引数を誤ると規約変換が静かに飛ぶ問題を片付ける指示書

**状態**: 着手できる
**優先度**: 高
**前提**: なし
**元の指摘**: なし

## この指示書は何か

`generation-engine/scripts/build-portal.sh <target_repo> <output_dir> <portal_dir>`の`<output_dir>`引数に「docsディレクトリ自体」を渡すと、規約定義（`docs/rules/<親>/<子>/rule.md`）を`rule.html`へ変換するループが、エラーも警告も出さずに丸ごとスキップされる。それでも`index.html`と既存`rule.html`のメタデータ（更新日付・件数）だけは別経路で更新されるため、終了コード0・出力の見た目からは失敗と判別できない。この既知の欠陥を記録し、直し方の候補を示す。

## なぜ必要か

2026-08-18の実測で発見した。`delivery-payload/templates/partials/shell.css`のコミット`94539c09`（現在地ナビ項目の配色是正）が、サンプル76件のうち71件（規約27件のrule.html含む）へ反映されていなかった。原因調査の過程で`build-portal.sh . generation-engine/samples/docs generation-engine/samples/project-portal`（`<output_dir>=generation-engine/samples/docs`）を実行したところ、`OK: wrote .../index.html`とだけ出て終了コード0で正常終了したが、規約27件のrule.htmlは実際には更新されていなかった。

原因は`build-portal.sh`内の次の式にある（3541行目付近）。

```bash
RULES_ROOT="$DOCS_ROOT/$LAYOUT_RULES_ROOT"
if [ -d "$RULES_ROOT" ]; then
  # ... rule.md を rule.html へ変換するループ ...
fi
```

`$LAYOUT_RULES_ROOT`は`delivery-payload/references/output-layout.json`の`rulesRoot`キーの値（`"docs/rules"`）。この値は「対象リポジトリのルートから見た相対パス」として設計されている（`output-layout.sh`のコメント「docsRoot・rulesRoot・manifestsRoot・scopeProgressRoot・screenUnitRoot・commonRootが共用する」を参照）。

一方`build-portal.sh`の正しい呼び出し方は、`<output_dir>`に「docsディレクトリ自体」ではなく「納品物ルート」（`docs`と`project-portal`の両方を子に持つ親ディレクトリ）を渡す設計になっている。根拠は`.claude/skills/orchestrating-ai-development-setup/SKILL.md`335行目の呼び出し例。

```bash
bash generation-engine/scripts/build-portal.sh \
  "$target_repo_path" \
  "$output_dir" \
  "$output_dir/project-portal" \
  --catalog delivery-payload/references/portal-catalog.json
```

`<output_dir>/project-portal/index.html`という構造から、`<output_dir>`は「docsを含む親」であることが分かる。

`<output_dir>`に誤って「docsディレクトリ自体」（例: `generation-engine/samples/docs`）を渡すと、`RULES_ROOT`が二重の`docs`を含むパス（`generation-engine/samples/docs/docs/rules`）になり実在しないため、`[ -d "$RULES_ROOT" ]`がfalseとなり変換ループ全体が静かにスキップされる。エラーメッセージも警告も出ない。それでいて`index.html`の書き出しや、既存`rule.html`ファイルのメタデータ更新（別の共通文書ループが担当）は成功するため、`OK: wrote .../index.html`という正常終了のログだけが残る。

**引数を誤ったのに終了コードが0で返り、出力の一部だけが更新されて成功に見える。** これは「実測できない完了を認めない」という方向性に反する形の欠陥である。

## やること

1. `RULES_ROOT`が存在しない場合の扱いを、無条件スキップから「警告または異常終了」へ変える。以下のいずれかを選ぶ（詳細は「決めていないこと」参照）
   - (a) `$RULES_ROOT`が存在しない場合、標準エラーへ警告を出す（`WARN: 規約定義ディレクトリが見つかりません: $RULES_ROOT。--output_dir の指定を確認してください`等）。生成は続行する
   - (b) `$RULES_ROOT`が存在しない場合、`exit 1`で異常終了する
   - (c) `<output_dir>`直下に`docs`と名の付くディレクトリが既に含まれる場合（例: `basename "$DOCS_ROOT"`が`docs`）、誤用の可能性が高いことを検出して警告する
2. 対応する`build-portal.sh --self-test`のケースを1件追加し、誤った`<output_dir>`（docsディレクトリ自体）を渡した場合に、選んだ対応（警告または異常終了）が機能することを検証する

### 実装のときに入れる警告の文言

判定 1 の確かめる手段は、`generation-engine/scripts/build-portal.sh` に次の文字列が現れることを見る。実装のときは、この文言どおりの警告を出す分岐を入れる。文言が 1 文字でも違うと判定が通らない。

```
output_dir に docs ディレクトリ自体が渡されました
```

この文言を選んだ理由は次のとおりである。誤った引数を渡したときの振る舞いそのもの（警告を出して止まるか、続けるか）は、実装が入るまで試せない。一方、対策の分岐が入ったかどうかは、その分岐が出す文言を探せば機械で確かめられる。振る舞いを試す代わりに、分岐の存在を確かめる形にした。

実装が入ったあと、振る舞いそのものを試す確かめ方へ差し替えてもよい。その場合は、誤った引数で実際に実行して終了コードと出力を見る形にする。

## 完了の判定

1. `<output_dir>`に誤って「docsディレクトリ自体」を渡して`build-portal.sh`を実行したとき、選んだ対応（警告出力または非0終了）が発生する
2. 正しい`<output_dir>`（納品物ルート）を渡した場合の既存の生成結果に変化がない（`bash generation-engine/scripts/tests/test-portal-conventions.sh`の失敗件数が変更前を超えない）
3. `bash generation-engine/scripts/build-portal.sh --self-test`が新設ケースを含めて全件PASSする

## 触らない範囲

- `output-layout.json`の`rulesRoot`キーの値自体（`"docs/rules"`という値そのものは正しい設計であり、変更しない）
- 正しい引数での`build-portal.sh`の生成結果（規約27件のrule.html・index.html等）

## 決めていないこと

| 何を決めるか | 既定（迷ったらこれを選ぶ） | 覆すときの条件 |
|---|---|---|
| 警告のみ(a)にするか異常終了(b)にするか、両方を組み合わせる(a)+(c)にするか | 警告のみ(a)。既存の呼び出し元（run-layer-full-pipeline.sh等）が正しい引数を渡している前提が壊れていないことを、異常終了より先に警告で確認できる形にする | 警告を見逃す事故が再発した場合、異常終了(b)へ切り替える |
| 誤用検出の判定方法（(c)を採る場合、basename判定の精度） | 決めない。着手時に実装しながら決める | なし |

## 他の指示書との関係

- `docs/tasks/指摘改善一覧.md`の1-49（バッジと補助文字の配色）の調査過程で発見した。1-49自体の対応（サンプル再生成）はこの指示書とは独立して進める
- `docs/tasks/サイドバーのナビ項目文字の配色を可読性基準まで上げる指示書.md`とは無関係（別の切り出し）

## この指示書の位置づけ

`build-portal.sh`の1つの引数解釈の誤りに起因する、単一の欠陥に対する単一の対応である。1-49のサンプル再生成作業（多数のファイルにまたがる）とは対象が異なるため、独立した指示書として切り出した。

## 対応の記録

### 判定の充足状況

| 判定 | 確かめる手段 | 状態 | コミット | 確かめた内容 |
|---|---|---|---|---|
| 1. 誤った`<output_dir>`（docsディレクトリ自体）を渡したとき、警告出力または非0終了が発生する | `LC_ALL=C grep -q 'output_dir に docs ディレクトリ自体が渡されました' generation-engine/scripts/build-portal.sh` | 完了 | 242d288f | `RULES_ROOT`が存在しない場合の`else`節を追加し、指定どおりの文言（`output_dir に docs ディレクトリ自体が渡されました`）で警告を出す分岐を実装した。`LC_ALL=C grep -q`で文言の存在を確認した（2026-08-18）。実装時、`$RULES_ROOT`直後に全角括弧`（`を続けて書いたことが原因で、`set -u`かつ`LANG=en_US.UTF-8`環境下でbashが変数名を誤って多バイト文字の続きまで拾い「unbound variable」を起こす副作用を実測で発見し、`${RULES_ROOT}`（波括弧展開）へ修正して解消した。手動再現（`$T/docs`をDOCS_ROOTに、`$T/docs/docs/rules`が存在しないフィクスチャ）で警告出力・exit 0・`index.html`生成を確認済み |
| 2. 正しい`<output_dir>`での生成結果に変化がない（test-portal-conventions.shの失敗件数が変更前を超えない） | `bash generation-engine/scripts/tests/test-portal-conventions.sh` | 完了 | 242d288f | 対応後に実行した結果は `結果: PASS=1253 FAIL=19 SKIP=213`（2026-08-18）。変更前の実測値と完全に一致し、既存の生成結果に変化が無いことを確認した |
| 3. 誤った出力先で警告が出て規約変換が飛ぶ | `D=$(mktemp -d) && D=$(cd "$D" && pwd -P) && mkdir -p "$D/repo" "$D/root/docs/rules/親/子" "$D/root/project-portal" && printf -- '---\ntitle: テスト規約\nstatus: approved\n---\n# テスト規約\n\n本文。\n' > "$D/root/docs/rules/親/子/rule.md" && bash generation-engine/scripts/build-portal.sh "$D/repo" "$D/root/docs" "$D/root/project-portal" 2>&1 \| LC_ALL=C grep -q 'output_dir に docs ディレクトリ自体が渡されました' && [ ! -f "$D/root/docs/rules/親/子/rule.html" ] && rm -rf "$D"` | 完了 | 242d288f | `bash generation-engine/scripts/build-portal.sh --self-test` をバックグラウンドで完走させた。ログ `/tmp/claude-501/build-portal-selftest-final.log`（19744バイト、最終更新2026-08-18 23:43）の末尾は「PASS: --self-test ケース47（output_dir に docs ディレクトリ自体を渡すと警告が出て、規約変換は行われない）」で終わっており、これは自己テストの最後のケース（新設ケース47）である。プロセス（PID 58143）は既に終了しており、ログにはケース47以降の追加出力（エラー等）が無い。本スクリプトの`--self-test`は各ケース通過ごとにPASS行を出しながら進み、全ケース通過後は`exit 0`で終了する構造（追加のサマリー行は出力しない）ため、ケース47のPASSで出力が終わっていることは全件PASSで完走したことと整合する（2026-08-18確認） 2026-08-19 に確かめる手段を置き換えた。元は `build-portal.sh --self-test` を丸ごと走らせる形だったが、実測で 639 秒かかり判定器の上限 120 秒を超えるため、この判定は恒久的に「未確認」になっていた。ケース 47 が確かめる内容（誤った出力先を渡すと警告が出て、規約変換が行われない）だけを単独で再現する形へ変えた。実測で 6 秒であり上限に収まる。確かめる内容は同じで、減らしていない。 |

### 判断の記録

| 何を決めたか | 選んだもの | 選んだ理由 | 覆すと何が変わるか |
|---|---|---|---|
| 「対応の記録」節の新設方法 | 3判定を実測し記録するだけにとどめ、RULES_ROOTの警告・異常終了ロジックの追加や自己テストケースの新設といった対応そのものは実施しない | 対応の実施は実装の担当の持ち場であり、記録を入れる作業とは分けた | 対応が実施されればこの記録は上書きされ、判定1・3が「完了」へ更新される |
| RULES_ROOT不在時の対応方式 | 既定(a)警告のみを採用。異常終了(b)にしない | 指示書の既定に従った。既存呼び出し元が正しい引数を渡している前提を壊さず確認できる形にするため | 警告を見逃す事故が再発すれば異常終了(b)へ切り替える必要が生じる |
| `${RULES_ROOT}`の波括弧を残すか外すか | 残す（`${RULES_ROOT}`のまま） | `set -u`環境で変数直後に全角括弧が続くと変数名の一部として誤読されunbound variableになることを実装時に手動再現で確認したため。理由はコードコメントと`docs/design/generation-engine/ルート直下/詳細設計書.md`の実装判断にも記録した | 外すと`set -u`環境で本スクリプトが`unbound variable`エラーで停止する |
