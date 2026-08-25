# screen-doc-templateの目次生成が要素欠落時に例外を投げる問題を直す指示書

**状態**: 着手できる
**優先度**: 高
**前提**: なし
**元の指摘**: 1-71

## この指示書は何か

`screen-doc-template.html`の目次生成スクリプトを直す。
`common-doc-template.html`と同じ要素存在確認のガードを追加する。
対象要素（`doc-content`・`dp-hero-title`・`toc-list`）が出力されていないページでも、未捕捉の例外を投げずに処理を終えるようにする。

## なぜ必要か

1-71の修正は`common-doc-template.html`にのみ適用された。
`screen-doc-template.html`は放置されたままだった。

`grep`で両ファイルを比較した。
`common-doc-template.html`は目次生成の直前にガード文を持つ。
文言は`if (!container || !heroTitle || !tocList) return;`である。
`screen-doc-template.html`には同じガード文が無い。

`screen-doc-template.html`は3つの要素を取得する。
`doc-content`・`dp-hero-title`・`toc-list`である。
取得したあと、確認なしに子要素へアクセスする。
`container.querySelector('h1')`・`tocList.appendChild(li)`・`tocList.querySelector('.toc-link')`を呼ぶ。

実際にNode.jsのスタブで確かめた。
対象は`screen-doc-template.html`の該当scriptブロックである。

- `toc-list`が無く、かつ本文にh2見出しが無い入力: `Cannot read properties of null (reading 'querySelector')`
- `toc-list`が無く、かつ本文にh2見出しがある入力: `Cannot read properties of null (reading 'appendChild')`

いずれも指摘が報告する2種類の例外文言と一致する。

既存の回帰検査は`common-doc-template.html`だけを検査対象にしている。
検査名は`generation-engine/scripts/tests/verify-element-guard.cjs`である。
`screen-doc-template.html`は検査対象に含まれていない。
そのため、この不整合は検査をすり抜けていた。

## やること

1. `screen-doc-template.html`の目次生成ブロックへガードを足す。対象は3つの要素を取得している箇所である。`doc-content`・`dp-hero-title`・`toc-list`の3つである。`common-doc-template.html`と同じガードを追加する。文言は`if (!container || !heroTitle || !tocList) return;`である
2. 同ファイル冒頭の2箇所も書き換える。1箇所目は178行目付近の`doc-md`のtextContent参照である。2箇所目は376行目付近の`doc-content`のinnerHTML代入である。取得結果を変数へ入れてから存在確認するガードへ直す。`common-doc-template.html`の同等箇所に揃える。あちらは`sourceElement`・`contentElement`を取得してから`if (!sourceElement || !contentElement) return;`する形である
3. `verify-element-guard.cjs`の走査対象へ`screen-doc-template.html`を加える。既存の`common-doc-template.html`向け検査と同じ2ブロックを繰り返し検査する形にする。対象は目次生成ブロックと`.toc-link`操作ブロックである
4. 修正後、2種類の合成入力で`verify-element-guard.cjs`を実行する。要素が欠落した入力と、要素が揃った入力である。前者で例外が出ないこと・後者で目次が組み立てられることを確認する

## 完了の判定

1. `node generation-engine/scripts/tests/verify-element-guard.cjs`が終了コード0で終わる
2. `grep -c "return;" delivery-payload/templates/screen-doc-template.html`が1以上を返す
3. `grep -c textContent delivery-payload/templates/screen-doc-template.html`の値が、修正前より1件少なくなる。直接チェーンの参照が変数経由へ変わったことを示す
4. `verify-element-guard.cjs`が`screen-doc-template.html`のパスを含む文字列を持つ（走査対象へ追加されたことの確認）

## 触らない範囲

- `common-doc-template.html`側の既存のガード実装。今回は参照元として読むだけで変更しない
- 目次の入れ物となる要素が出力されない原因そのもの（生成経路側の問題）。1-71の完了条件が明記するとおり、本項目の対象外とする
- `screen-doc-template.html`の目次生成以外のロジック（テーブル装飾・スクロールキュー等）

## 決めていないこと

| 何を決めるか | 既定（迷ったらこれを選ぶ） | 覆すときの条件 |
|---|---|---|
| ガードの文言を`common-doc-template.html`と同じにするか、`screen-doc-template.html`固有の変数名に合わせるか | 固有の変数（`screen-nav-title`等）は保持する。ガード条件式の形（`if (!a || !b || !c) return;`）だけを揃える | 揃えると既存の`screen-nav-title`関連処理が壊れる場合、その変数だけ別のガードへ分離する |
| `verify-element-guard.cjs`を2ファイル共通の1本にするか、ファイルごとに関数を分けるか | 対象ファイルのパスを配列で持つ。同じ検証関数を繰り返し呼ぶ形にして重複コードを避ける | ファイルごとにガードの実装形が大きく異なる場合、個別の検証関数へ分離する |

## 他の指示書との関係

なし。この指摘は今回の再判定で初めて具体的な修正指示書として起票した。

## この指示書の位置づけ

確立済みのガードパターンを横展開する作業である。
土台は`common-doc-template.html`が持つ。
展開先は同じ目次生成ロジックを持つ`screen-doc-template.html`である。
修正対象が1ファイルの1箇所に限定されており、独立して着手・完了できる。

## 対応の記録

### 判定の充足状況

| 判定 | 確かめる手段 | 状態 | コミット | 確かめた内容 |
|---|---|---|---|---|
| 1. verify-element-guard.cjsの終了コード | `node generation-engine/scripts/tests/verify-element-guard.cjs` | 完了 | 146f0b5 | — |
| 2. screen-doc-template.htmlがガードを持つ | `bash docs/scripts/check-screen-doc-template-guard.sh` | 完了 | 146f0b5 | — |
| 3. 直接チェーンの呼び出しが残らない | `bash docs/scripts/check-screen-doc-template-guard.sh --no-direct-chain` | 完了 | 146f0b5 | — |
| 4. 検査対象へ追加されている | `grep -c "screen-doc-template" generation-engine/scripts/tests/verify-element-guard.cjs` | 完了 | 146f0b5 | — |

### 判断の記録

| 何を決めたか | 選んだもの | 選んだ理由 | 覆すと何が変わるか |
|---|---|---|---|
