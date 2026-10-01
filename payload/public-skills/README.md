# public-skills

Claude Code で使うスキルと規約を公開する置き場。スキルは 1 スキル 1 フォルダで、`~/.claude/skills/` に置くと動く。規約は `~/.claude/rules/` に置くと、該当するファイルを触るときに自動で読み込まれる。

## 導入

```bash
cp -R skills/<スキル名> ~/.claude/skills/
cp -R rules/agent-skill ~/.claude/rules/
```

drafting-agent-skill-from-template と reviewing-agent-skills は、`~/.claude/rules/agent-skill/` の規約と雛形を読んで動くので、規約も一緒に置く。

## 収録スキル

| スキル | 役割 | 前提 |
|---|---|---|
| `reporting-textlint-findings` | md を textlint で機械検査し、指摘箇所に波線を引いた HTML を出す | node。textlint と 5 パッケージはスキルが導入先を聞いて入れる |
| `drafting-agent-skill-from-template` | 規約 agent-skill の雛形に沿って、スキルの下書きを新規に作る。規約との照合と動作の確認は行わず、次のスキルを案内する。依頼がスキルの定義に合わなければ中止して案内する | `rules/agent-skill` |
| `reviewing-agent-skills` | 既存のスキルを規約 agent-skill の 7 本(41 項目)と 1 つずつ照らし、規約と項目の番号、箇所、根拠、直し方の案を一覧にする。ファイルは変更しない | `rules/agent-skill` |
| `testing-agent-skills` | 作ったスキルを、何も知らない実行者(サブエージェント)に実際に実行させ、不明瞭な点を洗い出して直す。成果物は一時フォルダに書き、終了時に消す | サブエージェントを起動できる環境 |

3 つは、下書きを作る(drafting)、規約と照らす(reviewing)、動かして直す(testing)の順で使う。前のスキルの完了の報告が、次のスキルを案内する。規約との照合は、作ったのと同じセッションでは行わず、新しいセッションで reviewing-agent-skills を使う。

## 規約(rules/agent-skill/)

スキルに関する規約の箱。`paths` で、`skills/*/SKILL.md` と `skills/*/references/` を読むか書くときだけ読み込まれる。常時読み込まれるものはない。規約は `rule/`、雛形と記入例は `template/` に分けてある。

| ファイル | 内容 |
|---|---|
| `rule/scope.md` | スキルにするか。スキル、規約、その場の依頼の見分け。1 場面 1 目的 |
| `rule/required.md` | 必須の事項。SKILL.md が持つ節と順、description の 3 文、step が持つ項目 |
| `rule/limit.md` | 数の上限。本文 200 行、phase 5、step 5、リファレンス 5 個 200 行、スクリプト 3 本 50 行、委任 |
| `rule/notation.md` | 書き方の記法。「step 2-1」の形、1 文 1 動作、禁止語、山かっこ、7 つの機能の名前 |
| `rule/flow.md` | 流れ。7 つのパターンと持つ項目、やり直し、ユーザー確認 |
| `rule/io.md` | 入出力と表示。入力と出力の種類、対象の範囲と 0 件、ファイルの一致、表示の 8 種類 |
| `rule/attachment.md` | 付属物。リファレンス、スクリプトと説明書とテスト、前提ツール、委任 |
| `rule/rule-or-guide.md` | 規約か手引きか。規約、手引き、雛形、記入例に文を置くときの線引き |
| `template/skill.md` | 雛形。SKILL.md の形 |
| `template/plan.md` | 雛形。構成の案の形 |
| `template/example.md` | 記入例。最も短い SKILL.md の完成例 |
