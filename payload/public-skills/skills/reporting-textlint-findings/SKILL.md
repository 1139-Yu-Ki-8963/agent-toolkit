---
name: reporting-textlint-findings
description: |
  md を textlint で機械検査し、指摘箇所に波線を引いた HTML を出す。
  TRIGGER when: 「赤ペンを入れて」「この md の文章を検査して」時。
  SKIP: 修正の適用。検査ルールの数値変更。md 以外のファイル。
invocation: reporting-textlint-findings
type: action
allowed-tools: ["Read", "Write", "Bash", "Glob", "AskUserQuestion"]
---

# textlint の指摘に赤ペンを入れる

md ファイルを textlint にかけ、指摘箇所に波線を引いた HTML にする。直すかどうかは読む人が決める。

## 前提

| 必要なもの | 無い時 |
|---|---|
| node | Step 1 が「node の導入が必要」と報告して止まる |
| textlint と 5 パッケージ（一覧は Step 1） | Step 1 が導入先を聞いて入れる |

Claude の設定ファイルへの追加は不要である。hook を持たないため settings.json に書くものはない。

| 同梱ファイル | 役割 |
|---|---|
| `.textlintrc.json` | 検査設定。効かせる規則・数値・除外フィルタ |
| `references/report-template.html` | HTML の雛形。見出し・集計行・1 指摘分の型・波線の見た目 |

## 効かせている規則

| 区分 | 規則 | 値 |
|---|---|---|
| AI が使いがちな語（ai-words-ja） | 効く・道具・踏み込む・照合・実測など約 55 語と、短い主題直後の読点 | 2 ルールとも有効。読点の規則はプリセットの既定が無効で、textlint 15.8 では true 指定が既定に負けるため `{}` で有効化している |
| 文の規則（ja-technical-writing） | 23 ルールすべて | 既定（1 文 100 字以内、読点 3 個まで、漢字の連続 6 文字まで） |
| 癖の規則（ai-writing） | 5 ルールすべて | 既定 |
| 除外 | 行頭が「参考:」「題名:」「出典:」「引用:」「例:」「図N:」「表N:」「キャプション:」「注:」「注釈:」「備考:」「補足:」の行 | 検査しない |
| 除外 | `<!-- textlint-disable -->` から `<!-- textlint-enable -->` の範囲 | 検査しない |

同梱の設定は 30 ルールすべてを既定値で有効にしている。特定のルールを止めたい、しきい値を変えたい場合は、利用者が `.textlintrc.json` で当該ルールに `false` や値を書く。

## フロー一覧

```
Step 1: 環境確認    textlint が実行できるか確かめる。無ければ導入先を聞いて入れる
Step 2: 入力受付    検査対象と出力先を 1 問ずつ聞く
Step 3: 検査        textlint を JSON 形式で 1 回実行し、返り値を受け取る
Step 4: 変換        返り値を「1 か所 1 指摘」の一覧に整える
Step 5: レポート    一覧を雛形に埋めて HTML を書き出す
Step 6: 報告        出力先と件数を返す
```

## Step 1: 環境確認

入力: なし
出力: 起動方法（`node <パス>` または `textlint`）。決まらなければ終了

1. textlint の起動方法を 2 段で確かめる
   - cwd で `node -e "console.log(require.resolve('textlint/bin/textlint.js'))"` を実行する。通れば、表示されたパスを起動方法（`node <そのパス>`）とし、Step 2 へ
   - 通らなければ `command -v textlint` を実行する。通れば起動方法を `textlint` とし、Step 2 へ
2. どちらも通らなければ `node --version` を実行する。通らなければ「node が無いため検査できません。node の導入が必要です」と報告して終了する
3. AskUserQuestion で導入先を聞く
   - 質問: textlint が見つかりません。導入しますか？
   - 選択肢:
     1. このリポジトリに導入する。cwd のロックファイルで道具を決める（pnpm-lock.yaml → `pnpm add -D`、yarn.lock → `yarn add -D`、bun.lockb → `bun add -d`、それ以外 → `npm install -D`）。package.json が無ければ `npm init -y` で作る
     2. グローバルに導入する（`npm install -g`）
     3. 導入しない（終了する）
4. 導入後、手順 1 を再実行して通ることを確認してから Step 2 へ

導入するパッケージは次の 6 つである。

| パッケージ | 種類 | 役割 |
|---|---|---|
| `textlint` | 本体 | 文書の読み込み、ルールの実行、結果の集約 |
| `textlint-rule-preset-ai-words-ja` | ルール群 | AI が使いがちな語（約 55 語）を形態素解析で指摘する |
| `textlint-rule-preset-ja-technical-writing` | ルール群 | 文の長さ・読点・助詞・ら抜きなど文の規則 20 個 |
| `@textlint-ja/textlint-rule-preset-ai-writing` | ルール群 | 誇張語・太字ラベルなど癖の規則 5 個 |
| `textlint-filter-rule-allowlist` | フィルタ | 設定に書いた行頭パターンに一致する行の指摘を捨てる |
| `textlint-filter-rule-comments` | フィルタ | 文書内の `<!-- textlint-disable -->` から `<!-- textlint-enable -->` までの指摘を捨てる |

## Step 2: 入力受付

入力: なし（利用者に聞く）
出力: 検査対象の md の一覧、出力先のフォルダ `<出力先>/textlint-report-<YYYYMMDD-HHMMSS>/`

AskUserQuestion で 1 問ずつ聞く。

| 聞くこと | 聞き方 | 断る条件 |
|---|---|---|
| 検査対象 | md ファイルまたはフォルダのパス | 存在しない、または md を 1 つも含まない |
| 出力先 | 3 択。デスクトップ（`~/Desktop`） / ダウンロード（`~/Downloads`） / 場所を指定する（絶対パス。無ければ作る） | 書き込めない |

対象がフォルダなら配下の `*.md` を列挙する（`node_modules` を除く）。出力先に `textlint-report-<YYYYMMDD-HHMMSS>/` を作る。

## Step 3: 検査

入力: Step 1 の起動方法、Step 2 の md の一覧
出力: textlint の返り値（JSON）

次を 1 回実行し、標準出力を受け取る。

```bash
<起動方法> --config <スキルのフォルダ>/.textlintrc.json --format json <対象の md...>
```

終了コードは違反 0 件で 0、1 件以上で 1、起動失敗で 2 以上である。2 以上なら標準エラーを添えて「検査できない」と報告し、終了する。

textlint に渡すもの:

| 渡すもの | 意味 |
|---|---|
| `--config` | 効かせる規則・数値・除外フィルタ |
| 対象ファイル | 検査する md |
| `--format json` | 返り値を JSON にする指定 |

textlint の返り値は、ファイルごとに 1 要素の配列である。各要素は `filePath` と `messages` を持ち、`messages` の 1 要素が 1 指摘である。

| 項目 | 内容 |
|---|---|
| `ruleId` | ルール ID |
| `line` / `column` | 開始位置（1 始まり） |
| `index` | ファイル先頭からの文字位置（0 始まり） |
| `message` | 人向けの説明 |
| `severity` | 2 = error、1 = warning |

## Step 4: 変換

入力: Step 3 の返り値、対象の md
出力: 「1 か所 1 指摘」の一覧。1 か所は、ファイル・行・列・元の文・印の範囲・表示名（複数可）・説明（複数可）を持つ

返り値を読み、次の規則で整える。

| 規則 | 内容 |
|---|---|
| 総評行の除去 | `line` が 1 かつ `column` が 1 で、`message` が「【テクニカルライティング品質分析】」で始まる指摘は捨てる |
| 位置での束ね | 同じファイル・同じ `line`・同じ `column` の指摘を 1 か所にまとめ、表示名と説明を列にする |
| 元の文 | 対象ファイルを Read し、`line` の行全体を取る |
| 印の範囲 | `message` の「」または "" で囲まれた語を行から探してその語。語が特定できなければ `column` から行末まで |
| 表示名 | 「区分 › ルール ID」。区分は次の表で決める。表示ではルール ID の接頭辞を省く |

| ルール ID の接頭辞 | 区分（表示名） |
|---|---|
| `ai-words-ja/` | AI が使いがちな語（ai-words-ja） |
| `ja-technical-writing/` | 文の規則（ja-technical-writing） |
| `@textlint-ja/ai-writing/` | 癖の規則（ai-writing） |

表に無い接頭辞は区分「その他」。

### 規則の一覧

入っている 3 プリセットからルール ID を読み取り、設定と指摘件数を突き合わせて「規則」タブの一覧を作る。ルール名は固定で書かず、次で読み取る（プリセットの版が上がると増減するため）。

    node -e "for (const p of ['textlint-rule-preset-ai-words-ja','textlint-rule-preset-ja-technical-writing','@textlint-ja/textlint-rule-preset-ai-writing']) console.log(p, Object.keys(require(p).rules).join(' '))"

Step 1 で決めた起動方法が `node <パス>` なら、そのパスから見える node_modules で実行する。各ルールを次の 3 状態に分ける。

| 状態 | 条件 |
|---|---|
| 無効 | `.textlintrc.json` でそのルールが `false` |
| 指摘あり | Step 3 の返り値にそのルール ID の指摘が 1 件以上ある |
| 指摘なし | 上記のどちらでもない |

「設定」列は `.textlintrc.json` の値から書く。同梱の設定はすべて既定のため「既定」と書く。利用者が値を変えていれば、数値はそのまま（例: 100 字以内）、`allows` は「『語』は許可」、`false` は「無効」と書く。「何を見るか」列は次の表から引く。表に無いルールはルール ID をそのまま書く。

| ルール ID | 何を見るか |
|---|---|
| no-ai-words | AI が使いがちな語（土台・効く・実測など約 55 語） |
| no-short-topic-comma | 短い主題の直後の読点 |
| sentence-length | 1 文の長さ |
| max-ten | 1 文の読点の数 |
| max-comma | 1 文のカンマの数 |
| arabic-kanji-numbers | 算用数字と漢数字の使い分け |
| max-kanji-continuous-len | 漢字の連続 |
| ja-no-successive-word | 同じ語の連続 |
| ja-no-redundant-expression | 冗長表現（〜することができる 等） |
| ja-no-abusage | 誤用 |
| ja-no-weak-phrase | 弱い表現（かもしれない 等） |
| ja-unnatural-alphabet | 不自然な英字 |
| no-doubled-joshi | 助詞の重複 |
| no-doubled-conjunction | 接続詞の重複 |
| no-doubled-conjunctive-particle-ga | 逆接の「が」の重複 |
| no-double-negative-ja | 二重否定 |
| no-dropping-the-ra | ら抜き |
| no-hankaku-kana | 半角カナ |
| no-nfd | NFD 濁点 |
| no-zero-width-spaces | ゼロ幅スペース |
| no-invalid-control-character | 制御文字 |
| no-unmatched-pair | 括弧の対応 |
| no-mix-dearu-desumasu | 文体の混在 |
| ja-no-mixed-period | 句点の統一 |
| no-exclamation-question-mark | 感嘆符・疑問符 |
| no-ai-hype-expressions | 誇張語（革命的な・究極の 等） |
| no-ai-list-formatting | 箇条書きの太字ラベル・絵文字 |
| no-ai-colon-continuation | コロンで文を続ける癖 |
| no-ai-emphasis-patterns | 強調の乱発 |
| ai-tech-writing-guideline | 技術文書指針（簡潔性・一貫性・構造） |

## Step 5: レポート

入力: Step 4 の一覧と規則の一覧、`references/report-template.html`
出力: `<出力先>/textlint-report-<YYYYMMDD-HHMMSS>/report.html`

雛形は変更しない。Read で内容を取り、次の差し込み位置を埋めたものを出力先に `report.html` として Write する。雛形はタブ 2 つ（指摘・規則）を持ち、切り替えは CSS だけで動く。

| 差し込み位置 | 内容 |
|---|---|
| `{{TITLE}}` | 「赤ペン <対象名>」 |
| `{{META}}` | 検査日時と textlint の版（例: 2026-09-16 10:42　textlint 15.1） |
| `{{FINDINGS_COUNT}}` | 指摘の箇所数 |
| `{{RULES_SUMMARY}}` | 「<全ルール数> のうち <指摘ありの数> に指摘」 |
| `{{FINDINGS_COUNTS}}` | 区分ごとの件数。`<span>AI が使いがちな語（ai-words-ja） <b>N</b></span>` を 3 区分ぶん |
| `{{FINDINGS}}` | ファイルごとに `<h2>ファイル名</h2>`、その下に指摘を行・列の順で 1 指摘分の型で並べる |
| `{{RULES_HIT}}` `{{RULES_OK}}` `{{RULES_OFF}}` | 指摘あり・指摘なし・無効のルール数 |
| `{{RULES}}` | 区分ごとに `<h2>区分（プリセット名）　N</h2>`、その下に 1 ルール分の型で並べる |

1 指摘分の型:

```html
<div class="spot"><div class="loc">N 行</div><div>
<div class="text">前 <mark>印の範囲</mark> 後</div>
<div class="why"><div><span class="tag">指摘</span><b>区分 › ルール ID</b><br>説明文</div></div>
</div></div>
```

束ねた指摘が複数なら `.why` の中の `<div>` を 1 指摘 1 つ並べる。

1 ルール分の型（状態で `dot` と `n` のクラスを変える）:

```html
<div class="rules row"><div class="dot hit"></div><div class="id">ルール ID</div><div class="what">何を見るか</div><div class="cfg">設定</div><div class="n hit">件数</div></div>
<div class="rules row"><div class="dot ok"></div><div class="id">ルール ID</div><div class="what">何を見るか</div><div class="cfg">設定</div><div class="n">なし</div></div>
<div class="rules row off"><div class="dot off"></div><div class="id">ルール ID</div><div class="what">何を見るか</div><div class="cfg">無効</div><div class="n">—</div></div>
```

## Step 6: 報告

入力: Step 5 の出力先、Step 4 の一覧の件数
出力: 次の 3 行

```
- 出力: <出力先>/report.html
- 指摘: N か所（AI が使いがちな語 N ／ 文の規則 N ／ 癖の規則 N）
- 規則: <全数> のうち指摘あり N、指摘なし N、無効 N
```

## 対象外

- 置き換え案の提示。指摘は波線で場所を示すだけ
- 修正案の起草、修正の適用（`--fix` も使わない）、AI 向けの修正指示プロンプトの生成
- 辞書の管理（語の追加・削除）。AI が使いがちな語の一覧はパッケージが持ち、利用者は管理しない
- 検査ルールの数値変更
- hook としての自動発火
- 変換や HTML 生成のためのスクリプト作成。Step 4 と 5 は手順どおりに手で行う
- md 以外のファイル

## 既知の限界

- 波線の範囲は、`message` に語が書かれた規則ではその語、無い規則では `column` から行末までになる
- yarn の Plug'n'Play 方式と Deno は node_modules と PATH のどちらも使わないため、Step 1 では見つからず、導入先を聞く扱いになる
