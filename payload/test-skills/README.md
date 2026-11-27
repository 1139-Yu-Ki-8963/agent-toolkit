# test-skills

資料「品質保証のテストの 2 つの軸」で挙げたテストの道具を、Claude Code ですぐ使えるように集めたフォルダです。skill の文書は、日本語で書いています。

## 使い方

1. このフォルダの直下で、準備のスクリプトを 1 回走らせます。designing-test-cases が使う Python のパッケージがあるかを確かめます。

   ```bash
   ./setup.sh
   ```

2. このフォルダで Claude Code を開きます。`.claude/skills/` の skill が読み込まれます。
3. skill は、`/名前` で呼びます。break-ui、performance、designing-test-cases と、gstack から作った skill は、依頼の文からも自動で呼ばれます。

ほかのプロジェクトでも使うときは、`.claude/skills/` の下の skill のフォルダを、そのプロジェクトの `.claude/skills/` か、`~/.claude/skills/` に写します。gstack から作った 3 つの skill が要るものは、下の「gstack から作った skill について」にあります。

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
- designing-black-box-test-cases: テストベース(仕様書など)から、選んだ工程(単体、結合、総合)のブラックボックステストのテストケースを、テスト条件 = テスト対象 × テスト観点と、テストケース = テスト条件 × テスト技法の 2 つの公式で作り、仮に決めた点と足りない箇所を持つ md に書く。根拠は、IPA の高信頼化ソフトウェアのための開発手法ガイドブック第 6 章と、JSTQB の Foundation Level シラバス。
  - 使える状態: このフォルダを開けば使える。
  - md の見本: `.claude/skills/designing-black-box-test-cases/references/テストケースの例.md`(工程別のタブで見る HTML 版: `.claude/skills/designing-black-box-test-cases/references/テストケースの例.html`)
  - skill の構成の図: `.claude/skills/designing-black-box-test-cases/references/テストケースを作るskillの構成.html`
- running-e2e-tests-from-test-case-md: designing-black-box-test-cases が書いたテストケースの md から、Playwright のテストのエージェント(planner、generator、healer)で E2E のテストのコードを書いて流し、md の結果の 5 列を埋める。どこまで進めるか(計画まで、コードまで、実行まで、修復まで)を選べる。
  - 要るもの: 動いているアプリ、Playwright 1.56 以上(`npx playwright init-agents --loop=claude` を済ませる)、seed のテスト `tests/seed.spec.ts`、node。
- gstack-qa: 下の「gstack から作った skill について」。

### 7 UI/UX

- break-ui: 長い名前、空の値、絵文字のような最悪の場合のデータで画面を壊し、壊れた所と直し方を報告する。
  - 使える状態: このフォルダを開けば使える。
  - 文の中で名前を出す emil-design-eng、review-animations、prototype は、このフォルダに入っていない。
- gstack-design-review: 下の「gstack から作った skill について」。

### 8 セキュリティ

- security-guidance、claude-security、/security-review: Claude 本家のもの。このフォルダでは扱わない。

### 9 性能

- performance: 性能の問題を、計測を軸に直す。性能の数字を報告する前の確かめ(pstack の benchmark-checklist の中身)を含む。
  - 使える状態: このフォルダを開けば使える。
  - 手順の中の `strace -c` は、Linux だけにある。
- gstack-benchmark: 下の「gstack から作った skill について」。

### 10 互換性

- blast-radius: 変更が、差分の外のどこで何を壊しうるかを見つけ、安全である理由の事実を、コードを走らせて証明する。
  - 使える状態: このフォルダを開けば使える。

### そのほか

- /code-review(項目 3 単体テストのテストのコードを見る道具): Claude 本家のもの。このフォルダでは扱わない。
- 項目 1、3、4、5、9 の「言語ごとの道具」は、言語ごとに選ぶ道具なので、このフォルダには入れていない。

## gstack から作った skill について

gstack-qa、gstack-design-review、gstack-benchmark の 3 つは、gstack(https://github.com/garrytan/gstack、作者 Garry Tan、MIT License)の qa、design-review、benchmark の skill を日本語に訳し、gstack を入れなくても Claude Code だけで動くように書き直したものです。名前の前に `gstack-` を付けています。訳した元と、元から変えたことは、[NOTICE.md](./NOTICE.md) にあります。

要るものは、次のとおりです。

- gstack-qa、gstack-design-review、gstack-benchmark: Playwright の MCP。入っていないときは、skill が、入れるコマンド `claude mcp add playwright npx @playwright/mcp@latest` を示し、入れてよいかを聞きます。
- gstack-design-review の `--build`: 加えて、プレビューを起動する `node`。

報告と基準値は、調べるリポジトリの `test-reports/<skill の名前>/` に書かれます。

gstack の元の skill から、なくなった機能は次のとおりです。

- ユーザーのいつものブラウザのサインイン済みの状態を使うこと。サインインが要るページは、Playwright のブラウザの窓で自分でサインインします。
- gstack-design-review: デザインの案の画像を作る道具と、impeccable の検出器。外の AI(Codex)の意見は、互いの結果を知らない 2 つのサブエージェントの意見に置き換えました。
- 3 つすべて: gstack の学び、質問、判断、テレメトリの記録と、ほかの gstack の skill との連携。

確かめた範囲は、次のとおりです。

- gstack-qa、gstack-design-review、gstack-benchmark は、見本のページと見本のコードで、gstack を入れずに走らせました。そのとき見つかった手順の問題を直したあとには、走らせ直していません。

## 出典とライセンス

- このフォルダのライセンスは、MIT License です([LICENSE](./LICENSE))。
- pstack、break-ui、gstack から作った skill の出典は、[NOTICE.md](./NOTICE.md) にあります。
- designing-test-cases は、一般のテスト技法(ISTQB CTFL v4.0)から書いた skill で、ほかの作品から作ったものではありません。
