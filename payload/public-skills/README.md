# public-skills

Claude Code で使うスキルを、1 スキル 1 フォルダで公開する置き場。各スキルは自己完結し、フォルダを `~/.claude/skills/` に置くだけで動く。

## 導入

```bash
cp -R skills/<スキル名> ~/.claude/skills/
```

## 収録スキル

| スキル | 役割 | 前提 |
|---|---|---|
| `reporting-textlint-findings` | md を textlint で機械検査し、指摘箇所に波線を引いた HTML を出す | node。textlint と 5 パッケージはスキルが導入先を聞いて入れる |
| `creating-agent-skills` | スキル運用規程(3 原則 20 規則)と雛形をもとに、スキルを新規に作る、または規程に合わせて書き直す。依頼がスキルの定義に合わなければ中止して案内する | なし |
| `testing-agent-skills` | 作ったスキルを、何も知らない実行者(サブエージェント)に実際に実行させ、不明瞭な点を洗い出して直す。成果物は一時フォルダに書き、終了時に消す | サブエージェントを起動できる環境 |

`creating-agent-skills` と `testing-agent-skills` は対で使う。作ったスキルの動作を確かめるときに、前者の完了の報告が後者を案内する。
