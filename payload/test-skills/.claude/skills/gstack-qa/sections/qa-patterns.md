# ブラウザの QA のやり方

AI は、この節を、選んだブラウザの面にだけ使う。AI は、プローブの前に、diff とソースからページを対応づける。探索は、外から見るだけで行い、原因の調べは呼び出し元が持つ。

探索の節の繰り返しが、走らせる順を持ち、この節の Phase は技法を持つ。探索の節のチェックポイントの決まりは、baseline のあとのすべてのプローブ(向きを決める確かめ、リンク、そのままの再生、足した証拠)に当てはまる。AI は、チェックポイントをまたいでまとめて走らせない。

ブラウザの道具は、Playwright の MCP の道具(`mcp__playwright__browser_*`)とする。使い方の決まりは、ブラウザの準備の節にある。

## モード

AI は、Full、Quick、Regression のどれかを選ぶ。深さの指定がぶつかるときは、プローブの前に聞く。呼び出し元がほかの skill かエージェントのときは、その呼び出し元の短い確かめと計画の範囲を保つ。diff による絞り込みは範囲を決めるもので、別の周回ではない。時間の上限は、チェックポイントと証拠の時間を含む。上限に達したら、AI は、プローブを止め、終わらなかった範囲を報告し、チェックポイントを飛ばさない。

### diff による絞り込み(URL のない feature branch で自動)

`main` は、見つけた base のブランチに置き換える。

```bash
git diff main...HEAD --name-only
git log main..HEAD --oneline
```

AI は、変わった controller、route、view、component、model、service、style を、ページに対応づける。AI は、コミットと PR の意図を確かめ、関係する TODO のバグをテスト計画に足す。静的なページは、直接開く。ブラウザの面の中の API は、ページの中から `mcp__playwright__browser_evaluate` で確かめる。

```js
async () => {
  const r = await fetch("<base-url>/api/...", { method: "GET" });
  return { status: r.status, body: (await r.text()).slice(0, 4000) };
}
```

AI は、ブラウザの面を選び、隔離を決めたあとで、URL がないときは、手元のアプリを探す。

```bash
for p in 3000 4000 8080; do curl -sI --max-time 3 "http://localhost:$p" >/dev/null 2>&1 && echo "Found app on :$p"; done
```

AI は、渡された URL か、最初に答えたもの、staging、preview を使い、どれもないときは聞く。AI は、変わったページと流れと、その隣をテストする。TODOS.md にない新しいバグは、Phase 6 の報告で知らせる。

**対応するページが見つからないとき:** バックエンド、設定、インフラの変更でも、AI は、Quick と、見つけた操作を使う。

### Full(URL があるときの既定)

AI は、たどれるすべてのページを訪れる(5〜15 分)。AI は、Health Score を付け、証拠のある問題を 5〜10 件書き、問題を作り上げない。

### Quick(`--quick`)

3 分: トップのページと、ナビゲーションの上位 5 つの行き先。AI は、読み込み、コンソール、壊れたリンクを確かめ、Health Score の採点の基準で採点する。細かい問題と点検表は飛ばしてよいが、探索の節の繰り返しの関門は飛ばさない。

### Regression(`--regression <baseline>`)

AI は、Full を走らせ、直った問題と新しい問題と、スコアの差を書き足す。渡された前の baseline は残す。baseline がないか読めないときは、足りない前提とし、比べることを blocked にするが、Full の実行は止めない。

## 作業の流れ

### Phase 1: 始める

AI は、ブラウザの準備の節で確かめた Playwright の MCP と、決めた証拠の置き場を使い、足りない準備だけを、呼び出し元の権限の中で行う。時間の上限は、呼び出し元の残りの時間を越えないようにする。

### Phase 2: 認証する(要るとき)

AI は、ブラウザの準備の節の「サインインが要るページ」に従う。ユーザーがサインイン、2 段階の認証、一回限りのコード、CAPTCHA を終えたあとで、手順をやり直す。AI は、認証情報を扱わず、cookie、トークン、localStorage を見せない。

### Phase 3: 向きを決める

AI は、問題を探す前に、成功する baseline を示す。AI は、ページか操作の期待した結果と状態を見て、読み込めたことだけで済ませない。

**読み取りと流れ:** 操作を確かめるときは、操作ありで、次の手順の操作と待ちを、確かめる操作に置き換える。AI は、1 つの流れを続けて行い、最後に開いたタブを閉じる。

1. `mcp__playwright__browser_navigate` で `<target-url>` を開く。
2. `mcp__playwright__browser_snapshot` で、操作できる要素の木を取る。
3. `mcp__playwright__browser_take_screenshot` で画像を撮る。操作なしは `initial.jpg`(`fullPage: true`)、操作ありは `issue-001-step-1.jpg` とする。
4. 操作ありのときだけ:
   1. `mcp__playwright__browser_click`(snapshot の ref、例 `e12`)などで操作する。ページを開き直すか移動すると、snapshot の ref が変わるので、AI は、開き直したあとは、手順 2 の `mcp__playwright__browser_snapshot` を取り直してから、その新しい ref で押す。
   2. `mcp__playwright__browser_wait_for`(`time: 0.5` か、出るはずの文)で待つ。
   3. `mcp__playwright__browser_snapshot` を取り直し、手順 2 の木と比べて、変わった所を書く。
   4. `issue-001-result.jpg` を撮る。
5. `mcp__playwright__browser_evaluate` で、`() => location.href` と `() => document.body.innerText.slice(0, 20000)` を取る。
6. `mcp__playwright__browser_console_messages`(`level: "error"`)で、コンソールのエラーを取る。
7. `mcp__playwright__browser_network_requests`(`static: false`)で、4xx と 5xx と失敗したリクエストを取る。

AI は、報告の根拠の行として、`URL=`、`CONSOLE_ERRORS=`、操作の前と後の違いを書く。AI は、撮ったすべての画像を Read で開く。AI は、報告と画像を消さない。

**リンク:** AI は、同じ origin の安全なパスだけを調べる。HEAD のリクエストは、手元の対象にだけ送る(リクエストは cookie を持つ)。AI は、`mcp__playwright__browser_evaluate` で次を走らせる。

```js
async () => {
  const links = [...new Set([...document.querySelectorAll("a[href]")].map(a => a.href))]
    .filter(h => new URL(h).origin === location.origin && !/logout|signout|delete|remove|cancel|unsubscribe/i.test(h));
  const local = /^(localhost|127\.0\.0\.1|0\.0\.0\.0|::1|\[::1\])$|\.(localhost|test)$/.test(location.hostname);
  const out = [];
  for (const l of links) {
    if (!local) { out.push("LINK ? " + l); continue; }
    const r = await fetch(l, { method: "HEAD" }).catch(e => ({ status: "ERR " + e.message }));
    out.push("LINK " + r.status + " " + l);
  }
  return out.join("\n");
}
```

`LINK` の 4xx と 5xx と `ERR` は、壊れたリンクとする。`LINK ?` は、確かめていないリンクとする。リンクに出てこない SPA のボタンとメニューは、snapshot で調べる。

**フレームワーク:** AI は、`mcp__playwright__browser_evaluate` で ページの HTML と読み込んだ資源を見て、決める。`__next` か `_next/data` は Next.js、`csrf-token` は Rails、`wp-content` は WordPress、再読み込みのない移動は SPA とする。

### Phase 4: 探る

AI は、前の結果から、次の候補を選ぶ。ページの 1 つごとに、「読み取りと流れ」の手順で `page-<name>.jpg` を撮る。AI は、この SKILL.md と同じフォルダの `references/issue-taxonomy.md` に従って、レイアウト、操作の部品、空の入力、不正な入力、端の入力のフォーム、ナビゲーション、空、読み込み中、エラー、あふれた状態を確かめる。AI は、中心の流れを、二次のページより先に確かめる。Quick では、この点検表を飛ばす。

**モバイル:**

1. `mcp__playwright__browser_resize` で `width: 375`、`height: 812` にする。
2. 300ms 待ち(`mcp__playwright__browser_wait_for`、`time: 0.3`)、`page-mobile.jpg` を `fullPage: true` で撮る。
3. タブレットが関係するときは、`width: 768`、`height: 1024` で同じことをする。
4. 元の幅に戻す。

Playwright の MCP の幅の変更は、画面の幅だけを変え、タッチの操作と、デバイスの画素の比はまねない。タッチだけの操作(スワイプ、長押し)は、確かめられなかった範囲として報告に書く。

### Phase 5: 書き残す

AI は、問題の 1 つずつを、探索の節の「そのままの再生」の決まりで 1 回やり直して確かめ、そのあと最小にして、すぐに画像の証拠を報告する。再生が終わる前に時間切れになったときは、確かめを終わっていないものとする。そのあとの時間切れでは、確かめた欠陥は残し、証拠か最小化を終わっていないものとする。

**操作の欠陥:** Phase 3 の手順を、操作ありで行う。操作の道具は、`mcp__playwright__browser_type`、`mcp__playwright__browser_fill_form`、`mcp__playwright__browser_select_option`、`mcp__playwright__browser_press_key`、`mcp__playwright__browser_hover`、`mcp__playwright__browser_wait_for` を使う。道具で書けない操作は、`mcp__playwright__browser_run_code_unsafe` で、`async (page) => { await page.getByRole("button", { name: "Save" }).click(); await page.waitForURL(/dashboard/); }` のように書く。AI は、再現の手順に、操作の前と後の画像をリンクする。

**静的な欠陥**(文、レイアウト、画像): AI は、印を付けた画像を 1 枚と、説明を残す。

1. `mcp__playwright__browser_evaluate` で、欠陥の要素(`target` に snapshot の ref)に、`(el) => { el.style.outline = "3px solid red"; el.scrollIntoView({ block: "center" }); }` を当てる。
2. `mcp__playwright__browser_take_screenshot` で `issue-002.png` を撮る(`type: "png"`)。
3. `mcp__playwright__browser_evaluate` で、`(el) => { el.style.outline = ""; }` を当てて、印を外す。

### Phase 6: まとめる

AI は、新しいプローブを走らせずに、残した証拠を、この SKILL.md と同じフォルダの `templates/qa-report-template.md` と、呼び出し元の置き場と、両方の面の報告の決まりで、報告の形にする。

AI は、次を報告する。

- スコア
- 重大度の順の、直すべき上位 3 件
- コンソールの状態
- 重大度ごとの件数
- 日付と、かかった時間
- ページの数と、画像の数
- フレームワーク

AI は、`baseline.json` を保存する。`baseline.json` は、`date`(YYYY-MM-DD)、`url`、`healthScore`、`issues`(`id`、`title`、`severity`、`category`)、`categoryScores` を持つ。Regression では、前にだけあるものを直ったもの、今だけあるものを新しいものとする。

## Health Score の採点の基準

AI は、分類ごとのスコア(0〜100)を計算し、そのあとで重みを付けた平均を取る。

### 数え方

- AI は、ページをまたいだ同じ原因の問題を 1 件にまとめる。分類は、次の順で最初に当てはまる 1 つとする: Links(ナビゲーション)、Accessibility(使えなくする壁)、Functional(振る舞い)、Performance(速さ)、Visual(レイアウト)、Content(文)、UX(手間)、Console(残るエラー)。同じ問題で 2 回引かない。
- **untested**(テストしていない)の分類は除く。一部だけのスコアには、範囲を添えて **provisional**(仮)のラベルを付ける。どれもテストしていないときは "not scored" とする。範囲が同じものだけを比べる。

### Console(重み: 15%)

AI は、再現するエラーと例外を、ページをまたいで、メッセージと出どころで 1 件にまとめる。警告、情報、ほかの分類で採点した欠陥は除く。
- エラー 0 件 → 100
- エラー 1〜3 件 → 70
- エラー 4〜10 件 → 40
- エラー 11 件以上 → 10

### Links(重み: 10%)

AI は、壊れた行き先を、クライアント側の route を含めて、重ねずに数える。壊れた行き先は、くり返し出る 4xx と 5xx、ない route か anchor、時間切れとする。期待した認証のリダイレクトと、資源と API のリクエストは除く。
- 壊れたもの 0 件 → 100
- 壊れたリンク 1 件ごとに → -15(最小は 0)

### 分類ごとの採点(Visual、Functional、UX、Content、Performance、Accessibility)

100 から始め、見つけたもの 1 件ごとに引く:
- Critical の問題 → -25
- High の問題 → -15
- Medium の問題 → -8
- Low の問題 → -3

下限: 0。

AI は、当てはまる重大度のうち、いちばん高いものを使い、影響と回避の方法を記録する:
- **Critical:** データが失われる、セキュリティかプライバシーが漏れる、すべてのユーザーにとってアプリの中心が使えない。
- **High:** 中心か大きな作業が止まり、回避の方法がない。
- **Medium:** 作業はしにくいが、回避の方法がある。
- **Low:** 見た目、文、手間の問題で、作業は終えられる。

Console と Links は、重大度でなく件数を使う。

### 重み

| 分類 | 重み |
|----------|--------|
| Console | 15% |
| Links | 10% |
| Visual | 10% |
| Functional | 20% |
| UX | 15% |
| Performance | 10% |
| Content | 5% |
| Accessibility | 15% |

### 最後のスコア

AI は、重みを小数(15% = 0.15)で使う: `score = Σ (category_score × weight) / Σ tested weights`。四捨五入は、最後のスコアにだけ行う(0.5 は切り上げる)。

---

## フレームワークごとの注意

- **Next.js:** hydration のエラー(`Hydration failed`、`Text content did not match`)、`_next/data` の 404、リンクを押したときの route の移動(`browser_navigate` だけで済ませない)、動く中身によるレイアウトのずれ(CLS)。
- **Rails:** 開発環境の N+1 の警告、フォームの CSRF、Turbo と Stimulus の遷移、flash の表示と消え方。
- **WordPress:** プラグインの JS の衝突、サインインしたときの管理バー、`/wp-json/`、混在するコンテンツ。
- **SPA:** snapshot でのナビゲーション、戻ったときの古い状態、戻ると進むの履歴、長く使ったあとのリークのコンソールの兆し。

## ブラウザのテストの決まり

**ブラウザの探索の間は、AI はソースコードを読まない。** AI は、実際に近い端から端までの流れを使い、操作のたびにコンソールを確かめる。押す対象が snapshot で見つからないときは、印を付けた画像で位置を確かめ、そのあとで ref か CSS のセレクタで押す。

AI は、認証情報を `[REDACTED]` と書く。AI は、ブラウザの準備の節の安全の決まりに従う: 手元でない対象の変える操作は、実行ごとに 1 回、行う前に並べて聞く。見ることは、変えることではない。

**選んだブラウザの面では、AI はブラウザを使うことを断らない。** バックエンドだけの変更でも使う。テストと curl は、ブラウザの代わりにならない。API、CLI、ジョブ、ワーカー、webhook の対象は、ブラウザの面を選ぶ理由にならない。
