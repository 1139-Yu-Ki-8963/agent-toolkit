# public-skills

Claude Code で使うスキルと規約を公開する置き場。スキルは 1 スキル 1 フォルダで、`~/.claude/skills/` に置くと動く。規約は `~/.claude/rules/` に置くと、該当するファイルを触るときに自動で読み込まれる。

## 導入

```bash
cp -R skills/<スキル名> ~/.claude/skills/
cp -R rules/skill-writing ~/.claude/rules/
cp -R rules/rule-writing ~/.claude/rules/   # 規約を書くときだけ要る
```

drafting-skill-with-template と reviewing-agent-skills は、`~/.claude/rules/skill-writing/` の規約と雛形を読んで動くので、規約も一緒に置く。

## 収録スキル

| スキル | 役割 | 前提 |
|---|---|---|
| `reporting-textlint-findings` | md を textlint で機械検査し、指摘箇所に波線を引いた HTML を出す | node。textlint と 5 パッケージはスキルが導入先を聞いて入れる |
| `drafting-skill-with-template` | 雛形の形で、スキルの下書きを新規に作る。構成の案の承認を得てから SKILL.md を書く。雛形は `~/.claude/rules/` の下から探すので、skill-writing と skill-writing-compact のどちらの箱でも動く。依頼がスキルの定義に合わなければ中止して案内する | `rules/skill-writing` か `rules/skill-writing-compact` |
| `reviewing-agent-skills` | 既存のスキルを規約 skill-writing の 12 本(53 規則)と 1 つずつ照らし、規約と項目の番号、箇所、根拠、直し方の案を一覧にする。ファイルは変更しない | `rules/skill-writing` |
| `testing-agent-skills` | 作ったスキルを、何も知らない実行者(サブエージェント)に実際に実行させ、不明瞭な点を洗い出して直す。成果物は一時フォルダに書き、終了時に消す | サブエージェントを起動できる環境 |
| `converting-mermaid-md-to-html` | Mermaid の図を含む md 1 本を、図の拡大・移動と目次ボタンを持つ 1 ページの HTML に変換する。Hugo と Relearn の公式のコマンドと設定だけで行い、md の中身は変更しない | hugo(extended)。無ければスキルが入れ方を案内する |

3 つは、下書きを作る(drafting)、規約と照らす(reviewing)、動かして直す(testing)の順で使う。前のスキルの完了の報告が、次のスキルを案内する。規約との照合は、作ったのと同じセッションでは行わず、新しいセッションで reviewing-agent-skills を使う。

## 規約(rules/)

規約はどれも「適用する場面、守ること、理由」の節を持ち、守ることは「規則 N: 観点」の行と箇条書きの組で書く。`paths` で該当するファイルを読むか書くときだけ読み込まれ、常時読み込まれるものはない。

```
rules/
├── skill-or-rule/                   スキルにするか、規約にするか。スキルと規約の両方を書くときに読み込まれる
│   └── skill-or-rule.md
├── rule-writing/                    規約を書くときの規約。rules/ の下を触るときに読み込まれる
│   ├── rule-format.md               規約の形。4 つの節、「規則 N: 観点」、対の形と例の表、判定できる文、7 規則 50 行以内、同じ内容は 1 か所にだけ
│   └── rule-naming.md               規約の名前とフォルダ。rules/ の直下に箱、箱の下に分類 1 段、主語で始める日常の語、1 フォルダ 1 種類、対は同じファイル名、規則の見出しの付け方
│   └── rule-file-split.md           規約をファイルに分ける仕方。1 ファイル 1 対象、2 つ以上に掛かる決まりは観点のファイルへ
├── skill-writing/                   スキルを書くときの規約。12 本に分けた版(下の木)
└── skill-writing-compact/           同じ内容を 1 ファイルにまとめた版(その下の木)
```

skill-writing と skill-writing-compact は、内容が同じで、まとめ方が違う 2 つの版。どちらか 1 つを使う。使うほうの `paths` を `**/skills/*/SKILL.md` と `**/skills/*/references/**` に向け、使わないほうの `paths` は箱の中(`**/<箱の名前>/**`)だけに向ける。配布の状態では skill-writing が使う側。

### skill-writing/

スキルの書き方の規約。`skills/*/SKILL.md` と `skills/*/references/` を読むか書くときだけ読み込まれる。

```
rules/skill-writing/
├── skill-writing-word-definition.md スキルの書き方で使う語の定義。最終出力、受け渡し値、中間成果物など 10 語
├── structure/                       構成。SKILL.md に何を置くか
│   ├── skill-sections.md            description、開始時の入力の列の値、ユーザーに聞く項目、手順に当たるもの、step の種別
│   ├── skill-limits.md              本文の行数、phase と step の数、リファレンスとスクリプトの数の上限
│   ├── skill-input-output.md        入力と出力の種類、対象の範囲と 0 件、ファイルの一致、チャットへの表示
│   ├── skill-references.md          リファレンスの置き場、何を出すか、読む時点
│   ├── skill-scripts.md             スクリプトの置き場、終了コード、説明書とテスト
│   ├── skill-needed-tool.md               前提ツール。表に挙げるコマンド
│   ├── skill-phase.md               phase の書き方。番号、先頭と最後の固定の phase、本作業の分け方、省いたあとの番号
│   └── skill-exception-handling.md  例外処理。想定外は中止、中止後に残すもの、失敗し得る step が手順に書くこと
├── writing/                         書き方。文と流れをどう書くか
│   ├── skill-step-sentence.md       step の文の書き方。「step 2-1」の番号、1 文 1 動作、使えない語、山かっこ、機能の名前
│   ├── skill-flow.md                流れの書き方。分岐、繰り返し、やり直し、ユーザー確認、中止、委任
│   └── rule-or-template-or-template-writing.md 規約か雛形か雛形の書き方か。文をどの文書に置くかの線引き
└── template/                        雛形関連。1 フォルダ 1 種類
    ├── skill-template/              スキルの雛形。形だけ。省ける部分は【〜だけ】の印で示す
    │   ├── skill-template.md        SKILL.md の形
    │   └── skill-plan-template.md   構成の案の形
    ├── skill-template-writing/      スキルの雛形の書き方。雛形と同じファイル名で対にする
    │   ├── skill-template.md        SKILL.md の山かっこに何を書くか
    │   └── skill-plan-template.md   構成の案の項目ごとの目的と出どころ
    └── skill-template-completed-example/ スキルの雛形の完成例
        ├── skill-completed-example.md 最も短い SKILL.md の全文
        └── skill-plan-completed-example.md その構成の案の全文
```

### skill-writing-compact/

同じ規約を 1 ファイルにまとめた版。数の上限や選択肢の値は雛形の「変数」の節が持ち、規約は変数の名前で指す。

```
rules/skill-writing-compact/
├── skill-template/                   雛形。SKILL.md(省ける部分の印、変数、形)と構成の案
├── skill-writing-rule/skill-writing-rule.md  規約 1 ファイル。44 規則の通し番号
└── skill-template-completed-example/ 完成例。SKILL.md と構成の案
```

## 規約と雛形と雛形の書き方と完成例

規約は、できあがったもの(SKILL.md、リファレンス)が満たしていることを書く。`skill-writing-word-definition.md`、`structure/`、`writing/` に置く(スキルにするか規約にするかの入口は箱の外の `skill-or-rule/`)。雛形は、成果物の章の構成と形(節の並び、表の列、固定の文、省ける部分の印)を持ち、`template/skill-template/` に置く。雛形の書き方は、項目ごとの目的、意図、出どころ、書かないときを書き、`template/skill-template-writing/` に雛形と同じファイル名で置く。完成例は、雛形の形で書き上げた SKILL.md の全文で、`template/skill-template-completed-example/` に置く。4 種類とも規約の箱にあり、`paths` で該当するファイルを触るときに自動で読み込まれる。スキルはどれも持たず、step で読む。
