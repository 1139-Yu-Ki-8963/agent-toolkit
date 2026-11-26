# test-skills

資料「品質保証のテストの 2 つの軸」で挙げたテストの道具を、Claude Code ですぐ使えるように集めたフォルダです。skill の文書は、日本語で書いています。

## 使い方

1. このフォルダの直下で、準備のスクリプトを 1 回走らせます。designing-test-cases が使う Python のパッケージがあるかを確かめます。

   ```bash
   ./setup.sh
   ```

2. このフォルダで Claude Code を開きます。`.claude/skills/` の skill が読み込まれます。
3. skill は、`/名前` で呼びます。break-ui、performance、designing-test-cases と、gstack から作った skill は、依頼の文からも自動で呼ばれます。

ほかのプロジェクトでも使うときは、`.claude/skills/` の下の skill のフォルダを、そのプロジェクトの `.claude/skills/` か、`~/.claude/skills/` に写します。gstack から作った 6 つの skill を使うには、下の「gstack から作った skill について」の準備が要ります。

## 集めた道具

資料の項目の番号と、このフォルダでの使える状態です。

### 2 形式検証

- create-formal-verification-skill: 害の大きい所を形式検証し、次のエージェントが変更を確かめられる、プロジェクトの中の skill を作る。
  - 使える状態: このフォルダを開けば使える。
  - 要るもの: 選んだ検証の道具(TLA+ など)を、対象のプロジェクトに入れること。
- maintain-formal-verification-skill: コードが変わったあとに、形式検証をコードに合わせ直す。
  - 使える状態: このフォルダを開けば使える。

### 6 仕様のテスト

- designing-test-cases: 仕様から、ISTQB CTFL v4.0 のテスト技法(同値分割、境界値分析、デシジョンテーブル、状態遷移テスト、エラー推測、探索的テスト、チェックリストベースのテストなど)と、それに加えて使う技法(ペアワイズ、ユースケースやシナリオからのテスト)で、テストケースの一覧を作る。
  - 使える状態: このフォルダを開けば使える。
  - 要るもの: ペアワイズの表を作るときは、`python3` と、パッケージ `allpairspy`。足りないときは、`./setup.sh` が入れ方を出す。
  - 資料が挙げた test-case-designer は、本家にライセンスのファイルがなく、日本語にして公開できないので、同じ技法を使う skill を、test-case-designer を写さずに書いた。
- gstack-qa: 下の「gstack から作った skill について」。

### 7 UI/UX

- break-ui: 長い名前、空の値、絵文字のような最悪の場合のデータで画面を壊し、壊れた所と直し方を報告する。
  - 使える状態: このフォルダを開けば使える。
  - 文の中で名前を出す emil-design-eng、review-animations、prototype は、このフォルダに入っていない。
- gstack-design-review、gstack-ios-design-review: 下の「gstack から作った skill について」。

### 8 セキュリティ

- gstack-cso: 下の「gstack から作った skill について」。
- security-guidance、claude-security、/security-review: Claude 本家のもの。このフォルダでは扱わない。

### 9 性能

- performance: 性能の問題を、計測を軸に直す。性能の数字を報告する前の確かめ(pstack の benchmark-checklist の中身)を含む。
  - 使える状態: このフォルダを開けば使える。
  - 手順の中の `strace -c` は、Linux だけにある。
- gstack-benchmark: 下の「gstack から作った skill について」。

### 10 互換性

- blast-radius: 変更が、差分の外のどこで何を壊しうるかを見つけ、安全である理由の事実を、コードを走らせて証明する。
  - 使える状態: このフォルダを開けば使える。

### 11 信頼性

- gstack-canary: 下の「gstack から作った skill について」。

### そのほか

- /code-review(項目 3 単体テストのテストのコードを見る道具): Claude 本家のもの。このフォルダでは扱わない。
- 項目 1、3、4、5、9 の「言語ごとの道具」は、言語ごとに選ぶ道具なので、このフォルダには入れていない。

## gstack から作った skill について

gstack-qa、gstack-design-review、gstack-ios-design-review、gstack-cso、gstack-benchmark、gstack-canary の 6 つは、gstack(https://github.com/garrytan/gstack、作者 Garry Tan、MIT License)の qa、design-review、ios-design-review、cso、benchmark、canary の skill を日本語に訳し、名前の前に `gstack-` を付けたものです。訳した元と、元から変えたことは、[NOTICE.md](./NOTICE.md) にあります。

6 つの skill は、gstack の道具(`bin/` のスクリプト、ブラウザの道具 `browse`、`design`、/cso の launcher)を、`~/.claude/skills/gstack/` のパスで呼びます。使うには、gstack を、gstack の README の手順で `~/.claude/skills/gstack` に入れておく必要があります。gstack の `./setup` は、gstack のすべての skill(英語の版)を `~/.claude/skills/` に入れ、`~/.claude/settings.json` に hook を足します。

使うときの注意は、次のとおりです。

- 6 つの skill は、skill ごとの節の文書(`sections/` の下の文書)の多くを、このフォルダの写しでなく、`~/.claude/skills/gstack/<元の名前>/sections/` から読みます。そこで読まれるのは、入れた gstack の英語の文書です。gstack-design-review、gstack-cso、gstack-benchmark の節の文書と、gstack-qa、gstack-design-review、gstack-ios-design-review、gstack-canary の `preamble.md` が、これに当たります。gstack-qa の `preamble.md` のほかの節の文書は、`SKILL.md` のあるフォルダから読むので、このフォルダの日本語の文書が読まれます。
- 6 つの skill は、gstack のコミット 789e9badaa754c666fba0ad18032e7c5dad474d7 から作りました。gstack の道具と節の文書は、入れた gstack から読まれるので、入れた gstack がこのコミットより新しいと、`SKILL.md` と版が合わないことがあります。版をそろえるときは、入れた gstack のフォルダで `git checkout 789e9badaa754c666fba0ad18032e7c5dad474d7` を走らせてから、gstack の `./setup` を走らせます。
- 6 つの skill の中では、日本語と英語が混ざります。frontmatter の description、見出し、コード、コマンド、gstack のテストが英語の文そのものを照らし合わせている文は、英語のまま残しています。gstack の道具が出す文は、英語です。
- gstack を入れると、同じ中身の英語の skill(/qa など)も呼べます。日本語の版は、`/gstack-qa` のように、`gstack-` の付いた名前で呼びます。
- gstack の `./setup` が skill の名前の付け方を聞いたときは、短い名前(`1) Short names`。`./setup --no-prefix` と同じ)を選びます。名前の前に `gstack-` を付ける方を選ぶと、gstack の英語の skill が、この 6 つと同じ名前になります。
- 6 つの skill の本文は、/review、/plan-tune など、ほかの gstack の skill の名前も出します。それらは、入れた gstack の英語の skill です。
- 6 つの skill を、Claude Code で呼んで確かめてはいません。

## 出典とライセンス

- このフォルダのライセンスは、MIT License です([LICENSE](./LICENSE))。
- pstack、break-ui、gstack から作った skill の出典は、[NOTICE.md](./NOTICE.md) にあります。
- designing-test-cases は、一般のテスト技法(ISTQB CTFL v4.0)から書いた skill で、ほかの作品から作ったものではありません。
