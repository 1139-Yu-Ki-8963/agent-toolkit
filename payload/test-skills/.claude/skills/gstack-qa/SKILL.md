---
name: gstack-qa
description: "サイト、API、CLI をテストし、見つけたバグを直して、直ったことを確かめる。ブラウザでの確かめは Playwright の MCP で行い、報告と証拠は作業フォルダの test-reports/gstack-qa/ に置く。Use for: qa test this, find bugs on site, test the site."
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
  - mcp__playwright__browser_navigate
  - mcp__playwright__browser_navigate_back
  - mcp__playwright__browser_snapshot
  - mcp__playwright__browser_take_screenshot
  - mcp__playwright__browser_click
  - mcp__playwright__browser_type
  - mcp__playwright__browser_fill_form
  - mcp__playwright__browser_select_option
  - mcp__playwright__browser_press_key
  - mcp__playwright__browser_hover
  - mcp__playwright__browser_evaluate
  - mcp__playwright__browser_resize
  - mcp__playwright__browser_console_messages
  - mcp__playwright__browser_network_requests
  - mcp__playwright__browser_wait_for
  - mcp__playwright__browser_tabs
  - mcp__playwright__browser_run_code_unsafe
---

# gstack-qa: テスト → 直し → 確かめ

この skill は、選んだ対象(ブラウザの画面、API、CLI、ジョブ、ワーカー、webhook)を調べ、再現したバグを、回帰テストを先に書いてから直し、直ったことを確かめて報告する手順です。ブラウザの画面の確かめは Playwright の MCP で行い、API、CLI、ジョブの確かめは Bash で行います。報告、画像、基準値(`baseline.json`)、履歴は、調べる対象のリポジトリ(作業フォルダ)の `test-reports/gstack-qa/` に置きます。

---

## 全体の決まり

AI は、この skill のすべての手順で、次の決まりを守る。

### 聞き方

- AI は、ユーザーに聞くときは、短い問いと、2〜4 個の候補と、勧める 1 つの候補とその理由で聞き、答えを待つ。
- AI は、同じ問いを 1 回だけ聞く。答えが来るまでは、あとの報告の中で、待っている問いとして 1 行で示す。
- AI は、自分で確かめられることを、聞く前に確かめる。
- 影響の大きい曖昧さ(アーキテクチャ、データモデル、壊す範囲、欠けている文脈)に当たったときは、AI は止まり、曖昧な点を 1 文で述べ、利点と欠点を添えた 2〜3 個の候補を示して聞く。

### 主張と証拠

- 「この API ではできない」「この操作には認証情報が要る」のような制限の主張は、エラーの文そのもの、文書の記述、実際に走らせた確かめのどれかを持つ。AI は、聞く前か止まる前に、確かめを走らせる。
- 走らせたと書くコマンドは、AI が結果を見たものとし、コマンドと、リビジョンか中身の指紋を書く。stderr を捨てたコマンドを根拠にしない。
- 証拠の種類(静的な読み、単体テスト、fixture か再生、実際の実行、本番)を書き、ほかの種類として扱わない。モックは、実際の確かめではない。
- 読む人の結論を変える失敗と、確かめていない範囲は、すべて書く。「終わったが、確かめていない」は「終わった」ではない。
- 確かめて何も見つからなかった結果は、成功として書く。同意した複数のエージェントの答えと、同じ出どころの読み直しは、1 つの証拠として数える。

### 秘密の扱い

- AI は、環境変数の全体、git の設定の全体、引数を含むプロセスの一覧を出力しない(`env`、引数なしの `printenv`、`set`、`export -p`、`declare -p`、`set -x`、`git config --list`、`ps aux`、`ps -ef` を使わない)。値は、名前を指して 1 つずつ読む(`git config --get <name>`、`[ -n "${NAME:-}" ] && echo set`)。
- 認証情報、cookie、トークン、localStorage の値は、読まず、出力せず、報告に書かない。報告では `[REDACTED]` と書く。
- 渡すファイルは、開いて、TODO、`<fill in>`、仮の文、壊れたリンクと画像を消してから渡す。

### 直し方

- 新しいコードを書く前に、AI は、次の順に探し、最初に使えるものを使う。
  1. このリポジトリにすでにある補助関数、ユーティリティ、パターン
  2. 標準ライブラリ
  3. プラットフォームが元から持つ機能(JS より CSS、アプリのコードより DB の制約、日付選択のライブラリより `<input type="date">`)
  4. すでに入っている依存。数行で済むことのために、新しい依存を足さない。
- バグの直しは、症状でなく、原因を直す。AI は、呼び出し側を grep し、すべての呼び出しが通る共有の関数で 1 回だけ直す。
- AI は、おかしく見えるものを見つけたら、依頼の範囲の外でも、気づいたこととその影響を 1 文で知らせる。範囲の外のものは、直さずに知らせるだけとする。

### 終わりの状態の報告

AI は、skill を終えるときに、次のどれか 1 つで状態を報告する。

- **DONE**: 最後の入力に対して有効な証拠を持って終わった。使い回した証拠と、別に確かめていないものを書く。
- **DONE_WITH_CONCERNS**: 終わったが、懸念がある。懸念を並べる。
- **BLOCKED**: 先へ進めない。妨げているものと、試したことを書く。
- **NEEDS_CONTEXT**: 情報が足りない。要るものを書く。

3 回試して失敗したとき、セキュリティに関わる変更に確信がないとき、確かめられない範囲があるときは、AI は `STATUS`、`REASON`、`ATTEMPTED`、`RECOMMENDATION` の形で報告して止まる。

---

## Step 0: git のホスティングと base のブランチを決める

**git のリポジトリかを確かめる。** AI は、どの git の手順よりも前に、作業フォルダで次を走らせる。

```bash
git rev-parse --is-inside-work-tree 2>/dev/null
```

このコマンドが失敗したとき(作業フォルダが git のリポジトリでないとき)は、AI は、この skill と節の文書のすべての git の手順(この Step 0 の残り、作業ツリーの確かめ、diff による絞り込み、8d のコミット、8e の revert、Phase 10 の `{user}` と `{branch}`、テストの枠組みの準備の `git ls-files`、`git log`、コミット)を飛ばし、報告の冒頭に「git のリポジトリでない」と書く。範囲は、依頼か、テスト計画で決める。直しの手順は、8b、8d、8e の「git のリポジトリでないとき」に従う。

AI は、git のリポジトリのときに、リモートの URL から、git のホスティングのプラットフォームを決める。

```bash
git remote get-url origin 2>/dev/null
```

- URL が "github.com" を含むとき → プラットフォームは **GitHub**
- URL が "gitlab" を含むとき → プラットフォームは **GitLab**
- どちらでもないときは、AI は CLI が使えるかを確かめる:
  - `gh auth status 2>/dev/null` が成功する → **GitHub**(GitHub Enterprise を含む)
  - `glab auth status 2>/dev/null` が成功する → **GitLab**(自前で立てたものを含む)
  - どちらも成功しない → **unknown**(git だけのコマンドを使う)

AI は、この PR/MR が向かうブランチを決める。PR/MR がないときは、リポジトリの既定のブランチを使う。以降のすべての手順で、その結果を「base のブランチ」と呼ぶ。

**GitHub のとき:**
1. `gh pr view --json baseRefName -q .baseRefName` が成功したら、その結果を使う。
2. `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` が成功したら、その結果を使う。

**GitLab のとき:**
1. `glab mr view -F json 2>/dev/null` の `target_branch` の欄が取れたら、その結果を使う。
2. `glab repo view -F json 2>/dev/null` の `default_branch` の欄が取れたら、その結果を使う。

**git だけで決めるとき(プラットフォームが unknown のときか、CLI のコマンドが失敗したとき):**
1. `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||'`
2. 失敗したら、`git rev-parse --verify origin/main 2>/dev/null` が通れば `main` を使う。
3. それも失敗したら、`git rev-parse --verify origin/master 2>/dev/null` が通れば `master` を使う。

すべて失敗したら、`main` を使う。

AI は、決めた base のブランチの名前を表示し、以降の `git diff`、`git log`、`git fetch`、`git merge`、PR/MR を作るコマンドで、「base のブランチ」と `<default>` を、その名前に置き換える。

---

## 節の文書の一覧: その場面が来たら読む

AI は、指示された場面で、節の文書を全文で読み、記憶に頼って作業しない。節の文書は、この SKILL.md と同じフォルダの `sections/<名前>.md` にある。

| いつ | 読む節 |
|------|-------------------|
| 対象を準備するか調べる前(この呼び出しで、面と隔離をまだ決めていないとき) | この SKILL.md と同じフォルダの `sections/scope.md` |
| ブラウザの面を選んだときの準備(機能だけの対象では読まない) | この SKILL.md と同じフォルダの `sections/web-setup.md` |
| 選んだ対象の baseline と探索のプローブを走らせるとき | この SKILL.md と同じフォルダの `sections/exploratory.md` |
| API、CLI、ジョブ、ワーカー、webhook の面を、リポジトリが対応している道具で調べるとき | この SKILL.md と同じフォルダの `sections/system-functional.md` |
| 再現したブラウザの欠陥を、直したあとに確かめ直すとき(機能だけの直しでは読まない) | この SKILL.md と同じフォルダの `sections/web-verify.md` |
| 準備の中で、ブラウザの対象のテストの枠組みを確かめるとき(機能だけの対象では読まない) | この SKILL.md と同じフォルダの `sections/test-bootstrap.md` |
| ブラウザの baseline(Phase 1〜6)を走らせるとき。モードの選び方、段階ごとの手順、Health Score の採点の基準、フレームワークごとの注意、ブラウザのテストの決まり | この SKILL.md と同じフォルダの `sections/qa-patterns.md` |

節の文書がないか読めないときは、AI は、準備の妨げとして報告し、その節に頼るプローブを blocked とし、ほかの安全なプローブ(独立した機能の確かめと静的な確かめ)を続ける。

**Playwright の MCP の確かめ:** ブラウザの面を選んだときだけ、AI は、この SKILL.md と同じフォルダの `sections/web-setup.md` の最初の手順で、Playwright の MCP があるかを確かめる。機能だけの対象では、この確かめをしない。

---

## 準備

> **止まる。** 対象を準備するか調べる前に、この呼び出しで面と隔離をまだ決めていないときは、この SKILL.md と同じフォルダの `sections/scope.md` を全文で読み、それに従う。

**AI は、ユーザーの依頼から、次のパラメータを読み取る:**

| パラメータ | 既定 | 上書きの例 |
|-----------|---------|-----------------:|
| 対象 | 依頼かリポジトリから推し量るか、ユーザーに聞く | ブラウザの URL、API のルート、CLI のコマンド、ジョブ、ワーカー、webhook |
| 直しの段階 | Standard | `--quick`, `--exhaustive` |
| 探索のモード | Full | `--quick`, `--regression <前の報告か baseline>` |
| 出力先のフォルダ | `test-reports/gstack-qa/` | `Output to /tmp/qa` |
| 範囲 | 選んだ対象(または diff で絞った範囲) | `Focus on duplicate webhook delivery` |
| 認証 | 機能のプローブには、隔離した合成の ID を使う | ブラウザのセッションの扱いは、ブラウザの準備の節が持つ。チャットで認証情報を求めない |

**直しの段階は、どの問題を直すかを決める:**
- **Quick:** critical と high の問題だけを直す。
- **Standard:** medium の問題も直す(既定)。
- **Exhaustive:** low と見た目の問題も直す。

`--quick` は、直しの段階を Quick にし、探索も Quick にする。`--exhaustive` は、直しの段階だけを変える。Regression のモードは、選んだ直しの段階を保つ。`--quick` と `--regression` の両方が渡されたときは、AI は、準備とプローブの前に、どちらの探索のモードを使うかをユーザーに聞く。この問いは探索のモードだけに関わり、選んだ直しの段階は保つ。

**範囲の指定がない feature branch では:** AI は、変わった振る舞いと、その隣の振る舞いを、diff を元にテストする。AI は、最初に面を選ぶ。URL がないことは、ブラウザを使う理由にならない。

**作業ツリーがきれいかを確かめる:**

```bash
git status --porcelain -- . ':!test-reports/gstack-qa'
```

git のリポジトリでないときは、AI は、この確かめを飛ばす。この skill の報告のフォルダ `test-reports/gstack-qa/` は、確かめから外す。ほかの変更があるときは、AI は**止まり**、きれいな作業ツリーが QA の直しを 1 件ずつのコミットに保つことを説明して、次の候補で聞く。
- A) 今の変更を、内容が分かるメッセージでコミットしてから QA を始める(勧める)。
- B) 変更を stash し、QA を走らせ、そのあと stash を戻す。
- C) 手で片付けるために、止める。

AI は、ユーザーが選んだものだけを行ってから、準備を続ける。

**ブラウザの準備の前に、報告の置き場を用意する。** AI は、渡された前の報告と baseline のパスを、書く前に決める。AI は、出力先の上書きか `test-reports/gstack-qa/` を選び、なければ作る。そのフォルダが空のときだけ、そのフォルダを `REPORT_DIR` とする。空でないときは、UTC の `run-YYYYMMDDTHHMMSSZ` の名前で、新しい実行のフォルダを作り(名前がぶつかるときは後ろに番号を足す)、`REPORT_DIR` とする。手元の証拠は、すべて `REPORT_DIR` に置く。AI は、前の報告、baseline、画像、探索のメモを上書きしない。

**ブラウザの面だけ:** 準備の節を読む。機能だけの実行では、この節を飛ばす。

> **止まる。** ブラウザの面を選んだときは、準備の前に、この SKILL.md と同じフォルダの `sections/web-setup.md` を全文で読み、それに従う。

**ブラウザの面だけ:** テストの枠組みを確かめ、要るときは、枠組みを入れることを申し出る。機能の対象は、リポジトリにあるテストを使うか、テストがないことを報告し、この枠組みの準備を読まず、CI も作らない。

> **止まる。** ブラウザの対象のテストの枠組みを準備の中で確かめるときは、この SKILL.md と同じフォルダの `sections/test-bootstrap.md` を全文で読み、それに従う。

---

## テスト計画を読む

AI は、作業フォルダにテスト計画があれば、git diff より優先して読む。

1. **作業フォルダのテスト計画:** AI は、Glob で `**/*test-plan*.md`、`**/*テスト計画*.md`、`test-reports/gstack-qa/*-test-outcome-*.md` を探し、最も新しいものを読む。`node_modules/` と `.git/` の下のものは除く。
2. **会話の中のテスト計画:** この会話の中に、テスト計画か、テストケースの一覧があれば、それを使う。
3. 1 と 2 の両方があるときは、中身の多いほうを使う。どちらもないときだけ、git diff を使う。

---

## Phase 1〜6: QA の baseline

AI は、探索の節の準備の順に従い、そのあとで、探索の節のプローブの繰り返しを走らせる。その繰り返しの中で、ブラウザの実行は、qa-patterns の Phase 1〜6 を技法として使い(タッチの画面は、`mcp__playwright__browser_resize` で幅を変えてから、クリックで確かめる)、機能の実行は、system-functional の契約の表を使う。どちらも、別の作業の流れではない。

> **止まる。** 選んだ対象の baseline と探索のプローブを走らせる前に、この SKILL.md と同じフォルダの `sections/exploratory.md` を全文で読み、それに従う。

AI は、直す前に、baseline の結果を報告する。ブラウザのスコアと、機能の結果は、分けておく。

---

## 出力の形

AI は、`REPORT_DIR` の下に、`qa-report-{target}-{YYYY-MM-DD}.md` と、ブラウザの `baseline.json` を書く。ブラウザの `{target}` は、ファイルの名前に使える形のホスト名とする。ブラウザの証拠の画像は `screenshots/` に置く。

- `initial.jpg`
- `issue-NNN-step-N.jpg`
- `issue-NNN-result.jpg`
- 欠陥の要素に印を付けた `issue-NNN.png`
- `issue-NNN-after.jpg`

直す前の証拠は Phase 5 のものとする。機能の報告は、安全なコマンドかサービスのラベルと、機微な値を除いたコマンド、リクエスト、状態の証拠を使う。

---

## Phase 7: 問題の仕分け

AI は、問題を重大度の順に並べ、選んだ直しの段階を当てる。段階より低い問題と、ソースから直せない問題(サードパーティのウィジェット、インフラ)は、"deferred" とする。

---

## Phase 8: 直しの繰り返し

**報告だけの権限のとき:** ほかの skill かエージェントがこの skill を呼んだときと、呼び出し元が分からないとき(`sections/scope.md` の「呼び出し元による権限」)は、AI は、Phase 8 から 11 を飛ばし、「出力の形」の報告を `REPORT_DIR` に書いて終える。報告は、見つけた問題と、テストの提案を持ち、直しの状態を持たない。

AI は、直せる問題の 1 件ごとに、重大度の順に、次を行う。

### 8a. 原因を調べ、再現する

AI は、探索の節の、原因の仮説と、最小にした再現を使い、編集の前に、実際の振る舞いと、文書にある振る舞いを記録する。変えるのは、原因のファイルだけとする。環境の失敗と、はっきりしない契約は、直す理由にならない。

### 8a.5. 直す前の回帰テスト

**テストの価値の基準。** AI は、テストを書くか提案する前に、再現したバグが答えている「何を守るか」「何で失敗するか」に加えて、次の 2 つに答える。

1. 今あるテストが、なぜそのバグを捕まえていないか。似たテストを足すより、今ある表のテストか共有の fixture に 1 行足すことを優先する。
2. 本番のどの呼び出し元も要らない、テストのためだけの継ぎ目(export、フラグ、ラッパー、差し込みの口)が要るか。要るときは、継ぎ目を作らず、実際の境目でテストする。

価値のカード: `Value: protects=<...>; fails_when=<...>; why_new=<...>; seam=none; no_claim=<...>`

- `seam`: `none` か、継ぎ目の名前。
- `no_claim`: テストが緑でも証明しないことと、どの fixture かモックが何の代わりかを 1 文で書く(例: `no_claim=provider acceptance (mocked provider; unit only)`、`no_claim=none beyond protects`)。要る実際の確かめを省く理由にはならない。
- 各欄は、ここでは UTF-8 で 160 バイトまでとする(超えるときは 157 バイトに切り、`...` を付ける)。JSON に書くときは、全文を持つ。
- AI は、カードを 8e.5 の記録に入れる。上流のカードがないときは止めずに、AI が作る。知らない欄は無視する。

例: `Value: protects=refundPayment rejects an empty reason; fails_when=the reason guard is removed or inverted; why_new=billing.test.ts covers processPayment only; seam=none; no_claim=provider acceptance (mocked provider; unit only)`

断った例(covered_elsewhere): 「checkout renders」は checkout.e2e.ts:15 が確かめているので、新しく書かず、そのテストを広げる。

AI は、今ある表か fixture が境目を確かめているときは、それを広げる。テストのために本番の継ぎ目を足さない。AI は、近くの 2〜3 本のテストの名前の付け方、import、アサーション、fixture に合わせ、それらを走らせるコマンドを見つける。AI は、新しいテストで失敗を再現し、直す前に、そのコマンドを走らせる。AI は、失敗の原因が欠陥であり、誤った fixture、import、サービスでないことを確かめる。AI は、その言語のコメントの書き方で、出どころを書く。

```text
// Regression: ISSUE-NNN — short defect description
// Found by gstack-qa on YYYY-MM-DD
// Report: test-reports/gstack-qa/qa-report-{target}-{date}.md
```

はっきりしていて健全な、テストのない契約には、製品のコードを変えずに、通るテストを足してよい。

AI は、探索の節の、単体、結合、E2E の決まりを当てる。CSS だけの欠陥は、ブラウザの証拠を使ってよい。テストの仕組みがないことは、テストの負債として報告に残す。

テストのファイルの名前は、部品の名前と、その言語の拡張子を使い、`{name}.regression-N.test.{ext}` とする。N は、今ある番号の最大に 1 を足した数とし、1 から始める。今あるファイルを置き換えない。AI は、正しい赤の回帰テストを残す。fixture かテストの誤りと証明できたときだけ、その誤りを狭く直し、そうでないときは、直せなかったバグとして報告する。

### 8b. 直す

AI は、周りのソースを読み、**最小の直し**をする。関係のないリファクタリングと機能の追加はしない。

**git のリポジトリでないとき:** AI は、直す前に、変えるファイルの 1 つずつを、作業フォルダからの相対のパスを保って、`REPORT_DIR/originals/ISSUE-NNN/<相対のパス>` に `cp` で写し、写したファイルの一覧を報告に書く。

### 8c. テストし直す

AI は、回帰テストと、元の失敗したプローブと、隣の正常な流れを走らせ直し、それぞれの最後の状態を調べる。ワーカーの直しは、受け付けられたことだけでは確かめたことにならない。確かめ直しが失敗したか走らせられなかったときは、未解決のままとし、最小の直しを 1 回だけ見直して試す。それでも通らないときは、reverted とする。

ブラウザの欠陥だけ:

> **止まる。** 再現したブラウザの欠陥を、直したあとに確かめ直すときは、この SKILL.md と同じフォルダの `sections/web-verify.md` を全文で読み、それに従う。機能だけの直しでは読まない。

### 8d. 確かめた直しをコミットする

```bash
git add <確かめたソースと回帰テストのファイルだけ>
git commit -m "fix(qa): ISSUE-NNN — short description"
```

AI は、確かめた直しを、その回帰テストとともに 1 件ずつコミットし、関係のない直しを混ぜない。未解決の直しと、正しい赤の回帰テストと証拠は、コミットせずに残し、残したものをユーザーに伝える。

**git のリポジトリでないとき:** AI は、コミットを飛ばし、報告の問題の項目に、コミットの SHA の代わりに「git のリポジトリでない」と、変えたファイルと、8b の写しの置き場を書く。

### 8e. 直しの状態を分ける

- **verified**: 8c を通った(使えるときは、その言語のテストの回帰テストで)。テストがない範囲は書く。
- **best-effort**: 直しは入れたが、確かめきれなかった(認証の状態や外のサービスが要るなど)。
- **reverted**: 回帰が出たか、未解決のまま。AI は、この実行の直しだけを戻し(コミット済みなら、そのコミットを revert する。git のリポジトリでないときは、8b の写しで、変えたファイルを書き戻す)、正しい回帰テストと証拠は残し、問題を "deferred" とする。ユーザーの変更は消さない。

### 8e.5. 回帰テストの記録

AI は、8a.5 で直す前に作ったテストと、8c でのテストし直しの結果を記録する。記録は、ファイル、コマンド、出どころの書き込み、確かめた境目、価値のカード、赤と緑の証拠、または先送りにした理由を持つ。この手順は記録だけを行い、別のテストを作らない。健全な契約のテストのコミットは、`test(qa): regression test for {contract}` とする。**繰り返しの止め方からの除外:** テストだけのコミットは、8f の止める数に数えない。

### 8f. 繰り返しの止め方(止まって見直す)

AI は、直しを 5 件ごとと、戻したあとに毎回、繰り返しが害のほうが大きくなっていないかを確かめる。次のときは、**すぐに止まる**。

- 2 回戻したとき
- 見つけた問題と関係のないファイルを 1 回編集したとき
- 直しが多くのファイルにまたがり続けるとき
- Low の問題だけが残ったとき

止まったときは、AI は、ここまでにしたことをユーザーに見せ、続けるかを聞く。

**上限: 直しは 50 件まで。** 50 件を直したら、残る問題にかかわらず止まる。

---

## Phase 9: 最後の QA

AI は、影響を受けた契約と、隣の正常な流れを、最後の入力で走らせ直す。呼び出し元が求めた確かめ直しは、影響がないとして飛ばさない。ブラウザの面では、影響を受けたページを確かめ直し、最後の Health Score を計算する。ページを開き直すときは、AI は、キャッシュの古いファイルを読まないように、URL に `?v=<時刻>`(`date -u +%Y%m%d%H%M%S` の値。URL がすでに問い合わせの文字列を持つときは `&v=<時刻>`)を付けて開き、報告と比べでは、`v` を除いた URL を使う。スコアが下がったときか、契約が回帰したときは、目立つように警告する。blocked か結論の出ない確かめ直しは、直しを確かめたことにならない。

---

## Phase 10: 報告

AI は、「出力の形」の報告を `REPORT_DIR` に書き、同じ中身を、`test-reports/gstack-qa/{user}-{branch}-test-outcome-{datetime}.md` にも書く。

- `{user}` は `git config user.name`、`{branch}` は `git branch --show-current` とする。取れないときは `unknown-user`、`detached` とし、英数字でない文字は `-` にする。
- `{datetime}` は UTC の `YYYYMMDDTHHMMSSZ` とする。

**問題ごとに足すもの:**
- 直しの状態: verified / best-effort / reverted / deferred
- コミットの SHA(直したとき)
- 変えたファイル(直したとき)
- 直す前と後の証拠: ブラウザは画像、機能は出力、リクエスト、残る状態

**まとめ:** AI は、問題の総数、verified、best-effort、reverted の直しの数、deferred の問題の数を書く。ブラウザの範囲では、スコアの差を入れる。機能の範囲では、pass、fail、blocked、not run の契約の数と、足して残す回帰テストと、残るリスクを入れ、スコアは入れない。両方があるときは、結果を分けておく。

**PR の要約:** 1 行で、"QA found N issues, fixed M, health score X → Y." と書く。機能の対象は、スコアでなく、契約の結果を書く。

**チャットへの最後の報告:** AI は、冒頭に次の 3 行を置き、そのあとに、変えたものと走らせたものを書き、それ以上を主張しない。3 行の各行は、項目を名指しするか、「なし」とする。

- `Failed or skipped:` 失敗したもの(あとで直したものも含む)、飛ばしたもの、走らなかったもの
- `Unverified:` どの出力でも確かめていない主張
- `Also changed:` 設定、CI、依頼の範囲の外のファイル

---

## Phase 11: TODOS.md を更新する

リポジトリに `TODOS.md` があるときは、AI は次を行う。

1. **新しく先送りにしたバグ** → 重大度、分類、再現の手順を付けて、TODO として足す。
2. **TODOS.md にあって直したバグ** → "Fixed by gstack-qa on {branch}, {date}" を書き添える。

---

## この skill だけの決まり

**ユーザーが承認したブラウザのテストの枠組みの準備のほかでは:** AI は、テストを、Phase 8a.5 の手順でだけ作る。AI は、CI の設定を変えず、今あるテストを弱めず、新しいテストのファイルを使う。

迷ったときは、AI は止まって聞く。

---

この skill は、gstack(https://github.com/garrytan/gstack)をもとにした。
