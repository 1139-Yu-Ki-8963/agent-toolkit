# public-skills

Claude Code で使うスキルと規約を公開する置き場。スキルは 1 スキル 1 フォルダで、`~/.claude/skills/` に置くと動く。規約は `~/.claude/rules/` に置くと、該当するファイルを触るときに自動で読み込まれる。

## 導入

```bash
cp -R skills/<スキル名> ~/.claude/skills/
cp -R rules/skill-writing ~/.claude/rules/
```

drafting-agent-skill-from-template と reviewing-agent-skills は、`~/.claude/rules/skill-writing/` の規約と雛形を読んで動くので、規約も一緒に置く。

## 収録スキル

| スキル | 役割 | 前提 |
|---|---|---|
| `reporting-textlint-findings` | md を textlint で機械検査し、指摘箇所に波線を引いた HTML を出す | node。textlint と 5 パッケージはスキルが導入先を聞いて入れる |
| `drafting-agent-skill-from-template` | 規約 skill-writing の雛形に沿って、スキルの下書きを新規に作る。規約との照合と動作の確認は行わず、次のスキルを案内する。依頼がスキルの定義に合わなければ中止して案内する | `rules/skill-writing` |
| `reviewing-agent-skills` | 既存のスキルを規約 skill-writing の 9 本(49 項目)と 1 つずつ照らし、規約と項目の番号、箇所、根拠、直し方の案を一覧にする。ファイルは変更しない | `rules/skill-writing` |
| `testing-agent-skills` | 作ったスキルを、何も知らない実行者(サブエージェント)に実際に実行させ、不明瞭な点を洗い出して直す。成果物は一時フォルダに書き、終了時に消す | サブエージェントを起動できる環境 |

3 つは、下書きを作る(drafting)、規約と照らす(reviewing)、動かして直す(testing)の順で使う。前のスキルの完了の報告が、次のスキルを案内する。規約との照合は、作ったのと同じセッションでは行わず、新しいセッションで reviewing-agent-skills を使う。

## 規約(rules/skill-writing/)

スキルの書き方の規約。`paths` で、`skills/*/SKILL.md` と `skills/*/references/` を読むか書くときだけ読み込まれる。常時読み込まれるものはない。

```
rules/skill-writing/
├── skill-or-rule.md                 スキルか規約か、その場で頼むか(入口)
├── structure/                       構成。SKILL.md に何を置くか
│   ├── skill-sections.md            必ず持つ節と、step が必ず持つ項目
│   ├── skill-limits.md              本文の行数、phase と step の数、リファレンスとスクリプトの数の上限
│   ├── skill-input-output.md        入力と出力の種類、対象の範囲と 0 件、ファイルの一致、チャットへの表示
│   ├── skill-references.md          リファレンスの置き場、何を出すか、読む時点
│   ├── skill-scripts.md             スクリプトの置き場、終了コード、説明書とテスト
│   └── skill-tools-and-subagents.md 前提ツールと、サブエージェントへの委任
├── writing/                         書き方。文と流れをどう書くか
│   ├── skill-sentences.md           文の書き方。「step 2-1」の番号、1 文 1 動作、使えない語、山かっこ、機能の名前
│   ├── skill-flow.md                流れの書き方。分岐、繰り返し、やり直し、ユーザー確認、中止
│   └── rule-or-guide.md             規約かガイドか。文の置き場の線引き
└── templates/                       雛形と記入例
    ├── skill-template.md            SKILL.md の形
    ├── skill-plan-template.md       構成の案の形
    └── skill-example.md             最も短い SKILL.md の完成例
```

## 規約とガイド

規約は、できあがったもの(SKILL.md、リファレンス)が満たしていることを書く。`rules/` に置き、該当するファイルを触るときに自動で読み込まれる。ガイドは、書く人が行う作業(何を、どの順で、どう選んで書くか)を書く。作るスキルの `references/ガイド-<作業>.md` に置き、スキルの step が読む。見分ける問いは「その文は、できあがったものについて言っているか、書く人の作業について言っているか」である。drafting-agent-skill-from-template の `references/ガイド-スキルの下書き.md` がガイドの例。
