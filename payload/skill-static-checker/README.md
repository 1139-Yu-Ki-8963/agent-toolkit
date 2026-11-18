# skill-static-checker

このフォルダは、スキル scoring-skill-structure-and-danger を持つ作業フォルダです。このスキルは、スキルのフォルダを動かさずに調べ、構造の点数と危険の合否を出して、報告の HTML を書きます。SkillEvaluator の Tier 1(構造と危険の静的チェック)に当たる検査を、日本語のスキルと skill-factory の規約に合わせて行います。

## スキルの呼び方

このフォルダで AI の実行環境(Claude Code)を開き、次のように依頼します。

```text
<調べるスキルのフォルダ> を、構造と危険の静的チェックにかけて。報告は <報告の出力先のフォルダ> に書いて。
```

スキルは、調べるスキルのフォルダの `SKILL.md` を読み、8 本の検査のスクリプトと、2 つの AI の推論の検査を流して、次の 2 つを出します。

- 報告の HTML: `<報告の出力先のフォルダ>/<調べたスキルの名前>-構造と危険の静的チェック-<年月日時分>.html`
- チャットの表示「構造の点数と危険の合否」

構造の点数は、4 つの分野(正しさ、見つけやすさ、信頼性、効率)を、それぞれ 100 点から減点し、重み(0.35、0.25、0.25、0.15)をかけて足した点数で、70 点以上で合格です。危険は点数にせず、重さ「重大」の危険の指摘が 1 件でもあれば不合格です。

## フォルダの中身

| パス | 中身 |
|---|---|
| `README.md` | このファイル |
| `.claude/rules/skill-writing` | skill-factory の規約 skill-writing へのシンボリックリンク |
| `.claude/rules/text-writing` | skill-factory の規約 text-writing へのシンボリックリンク |
| `.claude/rules/rule-writing` | skill-factory の規約 rule-writing へのシンボリックリンク |
| `.claude/skills/scoring-skill-structure-and-danger/` | スキルの本体(`SKILL.md`、`references/`、`scripts/`) |
| `.claude/skills/tests/scoring-skill-structure-and-danger/テスト計画書.md` | スキルのテスト計画書 |
| `sample-reports/` | 動作確認の出力。skill-factory のスキル fixing-skill と drawing-skill-factory-figure に、スクリプトを `SKILL.md` の流れの順に手で流して書いた報告の HTML。この動作確認では、AI の推論の step(step 3-5 と 4-6)を流していないので、報告の「検査ごとの状態」で 2 つの検査を「省いた」としている |

## スクリプトのテスト

スクリプトのテストは、スクリプト 1 本ごとに 1 本あり、次のコマンドで流します。どれも終了コード 0 で通ります。

```text
node .claude/skills/scoring-skill-structure-and-danger/scripts/tests/test-<スクリプトの名前>.mjs
```

テストは、OS の一時フォルダに小さな見本のスキルを作り、合格の例と違反の例で終了コードと指摘を確かめ、終わりに見本を消します。test-check-dependencies.mjs は、npm の登録所を `127.0.0.1` のつながらない番号にして、つながらないときの動きを確かめるので、ネットワークがなくても通ります。

## 公開の写し

このフォルダは、配布リポジトリ agent-toolkit の `payload/skill-static-checker/` に写して公開している。写すのは、`README.md`、`.claude/skills/`、`sample-reports/` の 3 つで、`.claude/rules/` のシンボリックリンクは写さない。スキルが名前で挙げる規約 skill-writing-rule と text-writing-rule は、agent-toolkit の `payload/skill-factory/.claude/rules/` にある。`sample-reports/` の HTML では、この PC のパスを `<skill-factory のパス>` と `<作業用のフォルダ>` に置き換えている。
