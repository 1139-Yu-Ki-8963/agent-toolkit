---
name: reporting-textlint-findings
description: |
  md を textlint で機械検査し、指摘箇所に赤ペンを入れた HTML を出す。
  TRIGGER when: 「赤ペンを入れて」「この md の文章を検査して」時。辞書に語を足したい時。
  SKIP: 修正の適用。検査ルールの数値変更。md 以外のファイル。
invocation: reporting-textlint-findings
type: action
allowed-tools: ["Read", "Write", "Bash", "Glob", "AskUserQuestion"]
---

# textlint の指摘に赤ペンを入れる

md ファイルを textlint にかけ、指摘箇所に赤ペンを入れた HTML にする。textlint が返した置き換え案はそのまま見せ、適用するかどうかは読む人が決める。辞書に語を足す操作も持つ。

## 前提

| 必要なもの | 無い時 |
|---|---|
| node | Step 2 が「node の導入が必要」と報告して止まる |
| textlint と 5 パッケージ（一覧は Step 2） | Step 2 が導入先を聞いて入れる |

Claude の設定ファイルへの追加は不要である。hook を持たないため settings.json に書くものはない。

| 同梱ファイル | 役割 |
|---|---|
| `.textlintrc.json` | 検査設定。効かせる規則・数値・辞書の場所・除外フィルタ |
| `prh.yml` | 置き換え語の辞書 |
| `references/report-template.html` | HTML の雛形。見出し・集計行・1 指摘分の型・訂正線と波線の見た目 |

## 効かせている規則

| 区分 | 規則 | 値 |
|---|---|---|
| 辞書 | `prh.yml` の置き換え語 | |
| 文の規則 | 1 文の長さ | 100 字以内 |
| 文の規則 | 読点の数 | 1 文に 3 個まで |
| 文の規則 | 漢字の連続 | 8 文字まで |
| 文の規則 | 助詞の重複 | 「は・に・で・と・を・が」は許可 |
| 文の規則 | 同語の連続・冗長表現・誤用・弱い表現・不自然な英字・接続詞の重複・逆接の「が」の重複・二重否定・ら抜き・半角カナ・NFD 濁点・ゼロ幅スペース・制御文字・括弧の対応 | 既定 |
| 文の規則（無効） | 文体の混在・句点の統一・感嘆符と疑問符 | 無効 |
| 癖の規則 | 誇張語 | `大幅に` は許可 |
| 癖の規則 | 技術文書指針 | 明確性の分類（数値化の要求）は無効 |
| 癖の規則 | 箇条書きの太字ラベル・コロン継続・強調の乱発 | 既定 |
| 除外 | 行頭が「参考:」「題名:」「出典:」「引用:」「例:」「図N:」「表N:」「キャプション:」「注:」「注釈:」「備考:」「補足:」の行 | 検査しない |
| 除外 | `<!-- textlint-disable -->` から `<!-- textlint-enable -->` の範囲 | 検査しない |

## フロー一覧

```
Step 1: 操作の選択    「検査する」「辞書に語を足す」の 2 択を提示する
Step 2: 環境確認      textlint が実行できるか確かめる。無ければ導入先を聞いて入れる
Step 3: 反映          分岐 A: 検査 / 分岐 B: 辞書に語を足す
   3-A-1 入力受付     検査対象と出力先を 1 問ずつ聞く
   3-A-2 検査         textlint を JSON 形式で 1 回実行し、返り値を受け取る
   3-A-3 変換         返り値を「1 か所 1 指摘」の一覧に整える
   3-A-4 レポート     一覧を雛形に埋めて HTML を書き出す
   3-B-1 入力受付     避けたい語と置き換え先を聞く
   3-B-2 追記         prh.yml を Read し、重複を確かめて追記し、Write する
   3-B-3 確認         追記した語を含む md を一時的に作り、3-A-2 の検査で指摘されることを確かめる
Step 4: 報告          分岐ごとの固定形式で報告する
```

## Step 1: 操作の選択

入力: なし（利用者に聞く）
出力: 分岐 A または B

AskUserQuestion で 2 択を提示する。

- 質問: 何を行いますか？
- 選択肢:
  1. 検査する。md ファイルまたはフォルダを textlint にかけ、指摘に赤ペンを入れた HTML を出す
  2. 辞書に語を足す。避けたい語と置き換え先を `prh.yml` に登録する

## Step 2: 環境確認

入力: なし
出力: 起動方法（`node <パス>` または `textlint`）。決まらなければ終了

1. textlint の起動方法を 2 段で確かめる
   - cwd で `node -e "console.log(require.resolve('textlint/bin/textlint.js'))"` を実行する。通れば、表示されたパスを起動方法（`node <そのパス>`）とし、Step 3 へ
   - 通らなければ `command -v textlint` を実行する。通れば起動方法を `textlint` とし、Step 3 へ
2. どちらも通らなければ `node --version` を実行する。通らなければ「node が無いため検査できません。node の導入が必要です」と報告して終了する
3. AskUserQuestion で導入先を聞く
   - 質問: textlint が見つかりません。導入しますか？
   - 選択肢:
     1. このリポジトリに導入する。cwd のロックファイルで道具を決める。package.json が無ければ `npm init -y` で作る。

        | ロックファイル | 道具 |
        |---|---|
        | pnpm-lock.yaml | `pnpm add -D` |
        | yarn.lock | `yarn add -D` |
        | bun.lockb | `bun add -d` |
        | それ以外 | `npm install -D` |
     2. グローバルに導入する（`npm install -g`）。
     3. 導入しない（終了する）。
4. 導入後、手順 1 を再実行して通ることを確認してから Step 3 へ。

導入するパッケージは次の 6 つである。

| パッケージ | 種類 | 役割 |
|---|---|---|
| `textlint` | 本体 | 文書の読み込み、ルールの実行、結果の集約 |
| `textlint-rule-prh` | ルール | 辞書 `prh.yml` の語を置き換え語として指摘する |
| `textlint-rule-preset-ja-technical-writing` | ルール群 | 文の長さ・読点・助詞・ら抜きなど文の規則 20 個 |
| `@textlint-ja/textlint-rule-preset-ai-writing` | ルール群 | 誇張語・太字ラベルなど癖の規則 5 個 |
| `textlint-filter-rule-allowlist` | フィルタ | 設定に書いた行頭パターンに一致する行の指摘を捨てる |
| `textlint-filter-rule-comments` | フィルタ | 文書内の `<!-- textlint-disable -->` から `<!-- textlint-enable -->` までの指摘を捨てる |

## Step 3: 反映

### 分岐 A: 検査

#### Step 3-A-1: 入力受付

入力: なし（利用者に聞く）
出力: 検査対象の md の一覧、出力先のフォルダ `<出力先>/textlint-report-<YYYYMMDD-HHMMSS>/`

AskUserQuestion で 1 問ずつ聞く。

| 聞くこと | 聞き方 | 断る条件 |
|---|---|---|
| 検査対象 | md ファイルまたはフォルダのパス | 存在しない、または md を 1 つも含まない |
| 出力先 | 3 択。デスクトップ（`~/Desktop`） / ダウンロード（`~/Downloads`） / 場所を指定する（絶対パス。無ければ作る） | 書き込めない |

対象がフォルダなら配下の `*.md` を列挙する（`node_modules` を除く）。出力先に `textlint-report-<YYYYMMDD-HHMMSS>/` を作る。

#### Step 3-A-2: 検査

入力: Step 2 の起動方法、3-A-1 の md の一覧
出力: textlint の返り値（JSON）

次を 1 回実行し、標準出力を受け取る。

```bash
<起動方法> --config <スキルのフォルダ>/.textlintrc.json --format json <対象の md...>
```

終了コードは違反 0 件で 0、1 件以上で 1、起動失敗で 2 以上である。2 以上なら標準エラーを添えて「検査できない」と報告し、終了する。

textlint に渡すもの:

| 渡すもの | 意味 |
|---|---|
| `--config` | 効かせる規則・数値・辞書・除外フィルタ |
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
| `fix` | 機械的な置き換え案。`range`（文字位置の始まりと終わり）と `text`（置き換え後）。無い規則では null |

#### Step 3-A-3: 変換

入力: 3-A-2 の返り値、対象の md
出力: 「1 か所 1 指摘」の一覧。1 か所は、ファイル・行・列・元の文・置き換え後・印の範囲・札・表示名（複数可）・説明（複数可）を持つ

返り値を読み、次の規則で整える。

| 規則 | 内容 |
|---|---|
| 総評行の除去 | `line` が 1 かつ `column` が 1 で、`message` が「【テクニカルライティング品質分析】」で始まる指摘は捨てる |
| 位置での束ね | 同じファイル・同じ `line`・同じ `column` の指摘を 1 か所にまとめ、表示名と説明を列にする |
| 元の文 | 対象ファイルを Read し、`line` の行全体を取る |
| 置き換え後 | 束ねた指摘のいずれかに `fix` があれば、`range` の範囲を `text` で置き換えた行。無ければ無し |
| 印の範囲 | `fix` があればその範囲。無ければ `message` の「」内の語を行から探してその語。語が特定できなければ `column` から行末まで |
| 札 | `fix` があれば「置き換え」、無ければ「指摘」 |
| 表示名 | 「区分 › ルール ID」。区分は次の表で決める |

| ルール ID の接頭辞 | 区分 |
|---|---|
| `prh` | 辞書 |
| `ja-technical-writing/` | 文の規則 |
| `@textlint-ja/ai-writing/` | 癖の規則 |

表に無い接頭辞は区分「その他」。表示ではルール ID の接頭辞（`@textlint-ja/ai-writing/`・`ja-technical-writing/`）を省く。

#### Step 3-A-4: レポート

入力: 3-A-3 の一覧、`references/report-template.html`。
出力: `<出力先>/textlint-report-<YYYYMMDD-HHMMSS>/report.html`

雛形 `references/report-template.html` は変更しない。Read で内容を取り、次の 3 か所を埋めたものを出力先に `report.html` として Write する。

| 埋める場所 | 内容 |
|---|---|
| `{{TITLE}}` | 「赤ペン <対象名>」 |
| `{{SUMMARY}}` | 対象ファイル数、指摘の箇所数、置き換えの数、指摘のみの数 |
| `{{BODY}}` | ファイルごとに `<h2>` の見出し、その下に指摘を行・列の順で、1 指摘分の型に沿って並べる |

1 指摘分の型は次のとおり。

- 行 列
- 元の文。置き換えは印の範囲を `<del>` で囲み、直後に置き換え後の語を `<ins>` で置く。指摘のみは印の範囲を `<mark>` で囲む
- 札（置き換え / 指摘）、表示名、説明文。束ねた指摘が複数なら 1 行ずつ

```html
<h2>ファイル名</h2>                                        ← ファイルごとに 1 回
<div class="spot"><div class="loc">N 行 M 列</div><div>
<div class="text">前 <del>印の範囲</del><ins>置き換え後の語</ins> 後</div>      ← 置き換え
<div class="text">前 <mark>印の範囲</mark> 後</div>                             ← 指摘のみ
<div class="why"><div><span class="tag rep">置き換え</span><b>区分 › ルール ID</b><br>説明文</div></div>
</div></div>
```

札が指摘のみのときは `<span class="tag pt">指摘</span>` にする。`{{SUMMARY}}` は `<span>対象 N ファイル</span><span>指摘 N か所</span><span>置き換え N</span><span>指摘のみ N</span>` の形にする。

### 分岐 B: 辞書に語を足す

#### Step 3-B-1: 入力受付

入力: なし（利用者に聞く）
出力: 避けたい語（カタカナ形・英語形。1 つでも可）、置き換え先 1 語

AskUserQuestion で 1 問ずつ聞く。

#### Step 3-B-2: 追記

入力: 3-B-1 の語、`prh.yml`
出力: 追記後の `prh.yml`

`prh.yml` を Read し、`expected:` に同じ置き換え先が無いか確かめる。

- 同じ置き換え先がある → そのエントリの `patterns:` に新しい表記を 1 行追記する
- 無い → `rules:` の末尾に次の形で追記する

```yaml
  - expected: <置き換え先>
    patterns:
      - /<カタカナ形>/i
      - /<英語形>/i
```

`patterns` の各行は必ず `/i` を付ける。付けた行と付けない行が混在すると prh が辞書を読み込めない。

`rules: []` の形なら `rules:` に変えてから追記する。Write で保存する。

#### Step 3-B-3: 確認

入力: 3-B-1 の語、Step 2 の起動方法
出力: 指摘の有無

追記した語を 1 行含む md を一時的に作り、3-A-2 のコマンドで検査する。返り値に `ruleId` が `prh` で `message` が「<語> => <置き換え先>」の指摘があれば成功。無ければ追記内容を報告して終了する。一時ファイルは削除する。

## Step 4: 報告

入力: Step 3 の出力
出力: 分岐ごとの固定形式

分岐 A:

```
- 出力: <出力先>/report.html
- 集計: 指摘 N か所 / 置き換え N / 指摘のみ N
- 対象: <ファイル数> ファイル
```

分岐 B:

```
- 追記: <置き換え先> ← <避けたい語>
- 確認: 指摘あり / 指摘なし
```

## 対象外

- 修正案の起草。textlint が `fix` を返さない指摘には案を付けない
- 修正の適用。`--fix` も使わない
- AI 向けの修正指示プロンプトの生成
- 検査ルールの数値変更
- 変換や HTML 生成のためのスクリプト作成。Step 3-A-3 と 3-A-4 は手順どおりに手で行う
- md 以外のファイル

## 既知の限界

- 指摘のみの波線の範囲は、`message` に「」で語が書かれた規則ではその語、無い規則では `column` から行末までになる
- yarn の Plug'n'Play 方式と Deno は node_modules と PATH のどちらも使わないため、Step 2 では見つからず、導入先を聞く扱いになる
