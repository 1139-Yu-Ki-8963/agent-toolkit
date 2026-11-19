# skill-static-checker

このフォルダは、SkillEvaluator の検査を、日本語のスキルと skill-factory の規約に合わせて行う 2 本のスキルを持つ作業フォルダです。

- scoring-skill-structure-and-danger: スキルのフォルダを動かさずに調べ、構造の点数と危険の合否を出して、報告の HTML を書く。SkillEvaluator の Tier 1(構造と危険の静的チェック)に当たる。
- checking-skill-duplication: スキルの中で同じ指示を繰り返す節と、役目が重なるほかのスキルを、判定者 2 人に仕分けさせ、重複の検査の合否と報告の HTML を出す。SkillEvaluator の Tier 2(重複の検査)に当たる。

## スキルの呼び方

### 構造と危険の静的チェック

このフォルダで AI の実行環境(Claude Code)を開き、次のように依頼します。

```text
<調べるスキルのフォルダ> を、構造と危険の静的チェックにかけて。報告は <報告の出力先のフォルダ> に書いて。
```

スキルは、調べるスキルのフォルダの `SKILL.md` を読み、8 本の検査のスクリプトと、2 つの AI の推論の検査を流して、次の 2 つを出します。

- 報告の HTML: `<報告の出力先のフォルダ>/<調べたスキルの名前>-構造と危険の静的チェック-<年月日時分>.html`
- チャットの表示「構造の点数と危険の合否」

構造の点数は、4 つの分野(正しさ、見つけやすさ、信頼性、効率)を、それぞれ 100 点から減点し、重み(0.35、0.25、0.25、0.15)をかけて足した点数です。構造は、丸める前の点数が 70 点以上で、重さ「重大」の構造の指摘が 0 件のときに合格です。危険は点数にせず、重さ「重大」の危険の指摘が 1 件でもあれば不合格です。

### 重複の検査

```text
<調べるスキルのフォルダ> を、重複の検査にかけて。報告は <報告の出力先のフォルダ> に書いて。
```

比べるスキルの置き場を依頼の文に書かなければ、スキルは、調べるスキルのフォルダの親のフォルダにあるスキルと比べます。スキルは、2 本のスクリプトで候補を挙げ、判定者 2 人(サブエージェント)に仕分けさせて、次の 2 つを出します。

- 報告の HTML: `<報告の出力先のフォルダ>/<調べたスキルのフォルダの名前>-重複の検査-<年月日時分>.html`
- チャットの表示「重複の検査の合否」

SkillEvaluator の Tier 2 は、埋め込みで近さを測るために、節の本文を外部の AI の提供元に送ります。このスキルは、埋め込みの提供元に本文を送らず、手元で文字の近さ(続いた 3 字の組の TF-IDF の余弦)を測って候補を挙げ、意味の判定を判定者 2 人に任せます。判定者が読む本文は、スキルを動かしている AI の実行環境が、すでに使っている AI の提供元に届きます。2 人とも「重複」か「役目が同じ」とした候補が 1 件でもあれば不合格です。文字の近さで候補を挙げるので、同じ指示を別の言葉で書き直した節は見つかりません。

## スキルとツールの責務

2 本のスキルは、機械的に出せる作業を `scripts/` のスクリプト(ツール)に任せ、`SKILL.md` の手順(スキルの AI)は、ツールを動かすことと、推論と、ユーザーとのやり取りだけを受け持ちます。step ごとの受け持ちは、`スキルとツールの責務.html` をブラウザで開くと見られます。

## フォルダの中身

| パス | 中身 |
|---|---|
| `README.md` | このファイル |
| `.claude/rules/skill-writing` | skill-factory の規約 skill-writing へのシンボリックリンク |
| `.claude/rules/text-writing` | skill-factory の規約 text-writing へのシンボリックリンク |
| `.claude/rules/rule-writing` | skill-factory の規約 rule-writing へのシンボリックリンク |
| `.claude/skills/scoring-skill-structure-and-danger/` | スキルの本体(`SKILL.md`、`references/`、`scripts/`) |
| `.claude/skills/tests/scoring-skill-structure-and-danger/テスト計画書.md` | スキルのテスト計画書 |
| `.claude/skills/checking-skill-duplication/` | 重複の検査のスキルの本体(`SKILL.md`、`references/`、`scripts/`) |
| `.claude/skills/tests/checking-skill-duplication/テスト計画書.md` | 重複の検査のスキルのテスト計画書 |
| `スキルとツールの責務.html` | 2 本のスキルの step ごとに、ツール、スキルの AI、判定者、ユーザーに聞く step のどれが受け持つかを並べた 1 枚の HTML |
| `SkillEvaluator との対応.md` | 2 本のスキルが、SkillEvaluator のどの検査を、どこから写したかの記録 |
| `sample-reports/` | 動作確認の出力。名前に「構造と危険の静的チェック」を持つ 2 本は、skill-factory のスキル fixing-skill と drawing-skill-factory-figure に、8 本の検査のスクリプトと、AI の推論の 2 つの検査(サブエージェントが step 3-5 と 4-6 の基準で判定したもの)を、`SKILL.md` の流れの順に流して書いた報告の HTML。名前に「重複の検査」を持つ 2 本は、skill-factory のスキル fixing-skill と publishing-skills-to-public-repo の、2026-11-19 の候補と判定者 2 人の判定を、今のスクリプトでまとめ直して書いた報告の HTML。4 本とも、ファイルの名前と「作った日時」は `--time 202611201330` で決めた値で、実際に作った日時と違う |

## スクリプトのテスト

スクリプトのテストは、スクリプト 1 本ごとに 1 本あり、次のコマンドで流します。どれも終了コード 0 で通ります。

```text
node .claude/skills/<スキルの名前>/scripts/tests/test-<スクリプトの名前>.mjs
```

テストは、OS の一時フォルダに小さな見本のスキルを作り、合格の例と違反の例で終了コードと指摘を確かめ、終わりに見本を消します。test-check-dependencies.mjs は、npm の登録所を `127.0.0.1` のつながらない番号にして、つながらないときの動きを確かめるので、ネットワークがなくても通ります。

## 公開の写し

このフォルダは、配布リポジトリ agent-toolkit の `payload/skill-static-checker/` に写して公開している。写すのは、`README.md`、`スキルとツールの責務.html`、`SkillEvaluator との対応.md`、`.claude/skills/`、`sample-reports/` の 5 つで、`.claude/rules/` のシンボリックリンクは写さない。スキルが名前で挙げる規約 skill-writing-rule と text-writing-rule は、agent-toolkit の `payload/skill-factory/.claude/rules/` にある。`sample-reports/` の HTML では、この PC のパスを `<skill-factory のパス>` と `<作業用のフォルダ>` に置き換えている。
