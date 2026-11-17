# public-skills

Claude Code で使うスキルと規約のうち、skill-factory にないものを公開する置き場。`.claude/` の下に、規約(`rules/`)とスキル(`skills/`)を、プロジェクトに置いてそのまま動く形で収めている。スキルを作る、直す、照合する、テストする流れのスキル 13 本と、その規約と hook は、配布リポジトリ agent-toolkit の `payload/skill-factory/` にある。

## 導入

この `.claude/` フォルダの中身を、使うプロジェクトの直下の `.claude/` に置く(既に `.claude/` があるときは、中の `rules/` と `skills/` を足す)。すべてのプロジェクトで使うときは、`$HOME/.claude/rules/` と `$HOME/.claude/skills/` に置く。

```bash
git clone <このリポジトリ>
cp -R public-skills/.claude/rules/<規約のフォルダ> <プロジェクト>/.claude/rules/
cp -R public-skills/.claude/skills/<スキル名> <プロジェクト>/.claude/skills/
```

規約とスキルだけなので、settings.json への追加は要らない。

## 収録スキル

- `revising-skill-writing-rule`: スキル作成の規約の一式(規約、雛形、完成例)に決まりを足す、直す、消す依頼を、規約の規則、雛形、規約の冒頭の章、設計書、規約にも雛形にもしないものに仕分けて既にある決まりと突き合わせ、置く位置の決定、置き場の形の文、節の中の番号の振り直しと参照の修正、ピンクの象を除く書き直し、承認、反映までを規約の改訂の規則の手順で行う。規約の一式は、パスで受け取る。
- `converting-mermaid-md-to-html`: Mermaid の図を含む md ファイル 1 本を、md の中身を変えずに、図をホイールで拡大、ドラッグで移動、右上のボタンで元に戻せて、上のバーに目次ボタンを持ち、ブラウザで直接開ける 1 ページの HTML に変換する。
- `reporting-textlint-findings`: md を textlint で機械検査し、指摘箇所に波線を引いた HTML を出す。
- `managing-textlint-banned-words`: textlint の禁止語の辞書と設定と hooks を依頼どおりの状態にし、辞書を一覧で表示する。
- `checking-ui-with-rules`: 画面の決まりを書いたルールの文書(例: デジタル庁デザインシステムの Markdown)を規約の形に直し、プロジェクトの画面のファイルを照合者 2 人に照合させ、画面の URL があるときは 3 つの幅(1440、768、375)で写真を撮って文字の色の濃さの差と押す場所の大きさを測り、指摘の一覧をプロジェクトの `ui-check-results/<日時>/` に書く。直したあとの調べ直しも受け持つ。結果のフォルダ `ui-check-results/` は照合するプロジェクトの中にできるので、git で追わないときは、そのプロジェクトの `.gitignore` に `ui-check-results/` を足す。
- `fixing-ui-with-rules`: checking-ui-with-rules の指摘の一覧のうち、返事で頼まれた番号の指摘を、書き換えてよいかを確かめてから画面のファイルに直し、調べ直しを頼む文を出す。直さないと決めた箇所の一覧は、照合するプロジェクトの中の `ui-check-results/直さないと決めた箇所の一覧.md` に書くので、`.gitignore` の扱いは checking-ui-with-rules と同じとする。

checking-ui-with-rules は、画面の URL を渡したときだけ、Playwright と Chromium を使う。スキルは、初めて使うときに、確かめてからスキルのフォルダの `.tools/` に入れる(node と npm が要る)。手で入れるときは、次のコマンドを使う。

```bash
npm install --prefix "<スキルのフォルダ>/.tools" playwright@1.65.1
npm install --prefix "<スキルのフォルダ>/.tools" @playwright/browser-chromium@1.65.1
```

## 規約(`.claude/rules/`)

| フォルダ | 中身 | 読み込まれるとき |
|---|---|---|
| `rule-writing/` | 規約の書き方の規約。`rules/` の下に置くすべての規約に共通する、章と規則の形、名前とフォルダ、読み込みの決まり | `rules/` の下のファイルを触るとき |
| `hook-writing/` | hook の書き方の規約と、hook のスクリプトと README の雛形と完成例 | `hooks/` の下のファイルと settings.json を触るとき |
| `behavior/` | 振る舞いの規約。AI がユーザーに見せる回答と、AI が変えるファイルの中身と、回答の前に AI が読み直すものを決める | 常に |

規約 behavior は、規約 text-writing と thinking を前提とする。この 2 本は skill-factory の `.claude/rules/` にある。

## 構成

リポジトリの直下にあるのは、この README と、`.claude/`(規約とスキル)と、`docs/`(公開スキルの検査の状況、設計、スキル開発の流れ、提案、履歴の文書)と、`.gitignore`(node_modules の除外だけ)の 4 つ。

```text
.claude/
├── rules/
│   ├── rule-writing/rule-writing-rule.md
│   ├── hook-writing/   規約と、雛形 4 本(スクリプト、README、それぞれの完成例)
│   └── behavior/behavior-rule.md
└── skills/
    ├── <スキルの名前>/
    │   ├── SKILL.md
    │   └── references/
    │       ├── 全スキル共通の決まり.md    どのスキルも持つ。雛形の「全スキル共通の決まり」の章の写し
    │       └── <そのスキルのリファレンス>.md
    └── reporting-textlint-findings/   古い形。全スキル共通の決まり.md を持たず、.textlintrc.json を直下に置く
docs/
├── 公開スキルの検査の状況.md   収録スキルごとに、規約との照合、テストシナリオの実施、ピンクの象の除去、文章の書き方の規約との照合を通ったかの表
├── 設計/      エージェントの設定ファイルとプログラムの構成要素の対応表
├── 流れ/      スキル開発の流れの文書と図(md と html)、各スキルの要件、テストの前提の状態に関する問題
├── 提案/      規約と雛形への提案。書き方は 提案/フォーマット.md
└── 履歴/      フィードバックへの修正対応の履歴と、消した規則の記録(消した規則の原文と理由)
```

`全スキル共通の決まり.md` は、ツールの呼び方、チャットへの表示の書式、中止の決まり、完了の確認の手順を持つ。各スキルは最初の step でこれを読むので、スキルは規約の一式がなくても単体で動く。
