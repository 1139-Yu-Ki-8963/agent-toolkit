# public-skills

Claude Code で使うスキルを、1 スキル 1 フォルダで公開する置き場。各スキルは自己完結し、フォルダを `~/.claude/skills/` に置くだけで動く。

## 導入

```bash
cp -R skills/<スキル名> ~/.claude/skills/
```

## 収録スキル

| スキル | 役割 | 前提 |
|---|---|---|
| `reporting-textlint-findings` | md を textlint で機械検査し、指摘箇所に赤ペンを入れた HTML を出す | node。textlint と 5 パッケージはスキルが導入先を聞いて入れる |
