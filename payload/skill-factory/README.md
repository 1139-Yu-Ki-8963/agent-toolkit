# skill-factory

このフォルダは、Claude Code のスキルを作る、直す、テストするための作業フォルダです。`.claude/` の下の規約、スキル、hook は、作った人の環境では実体のフォルダを指すリンクで、配られたフォルダでは実体の写しです。作成したスキルは、このフォルダの直下の `output/` に置かれます。

## いつ使うか

このフォルダは、Claude Code のスキルを、要件の聞き取り、本文の作成、規約との照合、テストの 8 段階で作るときに使います。

## 最初にすること

この節の手順の主語は、ユーザーです。

1. 端末で、このフォルダに移動して `node ui/server.mjs` を起動する。
2. ブラウザで http://127.0.0.1:4173/ を開く。
3. 画面の入力欄に、次のプロンプトを送る。

    <作業>をするスキルを作って

## Claude Code に直接「スキルを作って」と頼むときとの違い

- 作ったスキルは、使う前に、別の AI が流してテストされる。
- 作ったスキルは、すべて同じ雛形の形になる。
- 要件とテストの根拠は、文書として残る。

## 使い方

この節の手順の主語は、ユーザーです。

1. ターミナルで、このフォルダに `cd` を実行し、`claude` を起動する。
2. 次の表の形で依頼する。AI は、依頼の形から段階を決めて、始める段階と入力を返す。

| したいこと | 依頼の文 | 始める段階 |
|---|---|---|
| 新しいスキルを作る | 「<作業>をするスキルを作って」 | 1 |
| 途中の文書から続ける | 「`output/<開始日時>/要件定義書.md` ができたから続きをやって」(分割設計書も同じ形。構成の案は `output/<開始日時>/skills/<スキルの名前>/構成の案.md`) | 2、3、4 |
| 既存のスキルを照合する | 「<スキルの名前> を照合して」 | 5(指摘の一覧を見せ、直すかを聞いて止まる) |
| 既存のスキルを直す | 「<スキルの名前> の <直す内容> を直して」 | 5(先に修正、次に照合) |
| 既存のスキルのテストを作る | 「`output/<開始日時>/skills/<スキルの名前>/` のテストを作って」 | 5(指摘なしなら 6 へ) |
| テストの実施する範囲を決める | 「`<テスト計画書のパス>` の実施する範囲は <正常系だけ か 1 回の実行で終わるすべて か 全件>」 | 7 |
| 既存のスキルのテストを流す | 「`<テスト計画書のパス>` のテストを流して」 | 8 |
| 不合格のテストからスキルを直す | 判定の記録のパス | 5 |

`<開始日時>` は、AI が段階 1 を始めた日時です。スキルの名前は、`output/<開始日時>/skills/` の下のフォルダの名前です。依頼の形の全件は、規約 skill-making-flow の規則「最初の依頼から始める段階を決める」の表にあり、ユーザーが「ここで何ができるか」と聞いたときは、AI がその表を示します。

3. AI が聞いたときに、次の 2 つを答える。
   - 各段階の承認
   - 段階 7 の実施する範囲(推奨は「正常系だけ」)
4. 段階 8 のテストが全件合格したら、AI が返す使うためのコマンドを、スキルを使うプロジェクトで実行する。

## 確認と承認の画面で進めるとき

この節の手順の主語は、ユーザーです。画面は、AI のスキル作成をブラウザで見て、承認か直す指示を返すための画面です。

1. 節「最初にすること」の 1 から 3 を行う。スキルの名前は、AI が提案する。
2. 画面の右上の図と右下の文書を見て、承認のボタンを押すか、直す指示を入力欄から送る。

3. 止めるときは、中継サーバーの端末で `Ctrl+C` を押す。画面か中継サーバーを直したあとは、中継サーバーを止めて起動し直し、ブラウザの画面を読み直して、開いた直後の画面の「続きから」で続ける。

画面が読むファイルは、`output/<開始日時>/ui/` の state.json、figures/、conversation.md です。中継サーバーは、起動したあとに AI が state.json を書いたフォルダを、いまの作業のフォルダにします。中継サーバー `ui/server.mjs` は、起動ごとに 1 つの会話を作り、画面から送った文を conversation.md に書き足して、このフォルダの Claude Code に渡します(1 回目は `claude -p --session-id`、2 回目からは `claude -p --resume`)。Claude Code の途中の返事も、1 つずつ conversation.md に書き足します。どの依頼の形でも、起動のコマンドは同じです。設計は `docs/スキル作成の確認と承認の画面/設計書.html` にあります。

## 画面と中継サーバーのテスト

テストの分け方と全ケースは `ui/tests/テスト計画書.md` にあります。

1. ユーザーは、準備として、`npm install --prefix ui/tests` と `npx --prefix ui/tests playwright install chromium` を実行する。
2. ユーザーは、毎回流すテストとして、`bash ui/tests/run-auto.sh` を実行する。AI はモックを使うので、利用料はかからない。
3. ユーザーは、本物の `claude` を使うテストとして、`node ui/tests/test-real.mjs <contract か until-stage-3 か until-stage-8 か check-skill か session-lost> --yes` を実行する。時間と利用料がかかるので、AI は、ユーザーが指示したときだけこのテストを流す。

## 前提

- Claude Code と Node.js が、claude を起動する PC に入っていること。
- `.claude/` の下に、規約 11 フォルダ、スキル 15 本、hook 3 本と settings.json があること。

## フォルダの中身

| パス | 中身 |
|---|---|
| `.claude/rules/` | 規約 11 フォルダ。text-writing、thinking、skill-or-rule、behavior、rule-writing、hook-writing、skill-writing(規約、雛形、完成例)、skill-testing(規約 skill-test-design-rule)、skill-making-flow(8 段階の流れ)、ui-design(画面のデザイン)、skill-factory-skill-naming(skill-factory のスキルの名前)。規約ごとの責務は `docs/各規約の要件.md` にある |
| `.claude/skills/` | スキル 15 本。段階が使う 10 本(defining-skill-requirements、designing-skill-structure、designing-skill-phases、drafting-skill-with-template、checking-skill-with-template、fixing-skill、designing-skill-test-cases、designing-skill-test-scenarios、testing-skill-with-template、fixing-test-plan)と、hook と fixing-skill が呼ぶ補助の 3 本(checking-markdown-document-with-rules、fixing-markdown-document、rewrite-pink-elephants)と、確認と承認の画面のための 2 本(updating-skill-factory-ui-state、drawing-skill-factory-figure。実体は `output/` の下) |
| `.claude/hooks/` | hook 3 本 |
| `.claude/settings.json` | hook 3 本の登録 |
| `output/` | 作業のフォルダ `output/<開始日時>/`。要件定義書.md、聞き取りの記録.md、テストの見本/、分割設計書.md、ui/ と、スキルごとのフォルダ `skills/<スキルの名前>/`(SKILL.md、references/、scripts/、構成の案.md、tests/)を持つ |
| `docs/規約とスキルとhookの一覧.md` | 規約 11 フォルダのうちの 8 フォルダ(text-writing、thinking、skill-or-rule、skill-making-flow、ui-design、skill-factory-skill-naming、skill-writing、skill-testing)、スキル 15 本、hook 3 本のそれぞれについて、パス、読み込まれる条件(規約と hook)または動く段階(スキル)、受けた検査 |
| `docs/操作の流れ.md` | 起動からリンクまでの操作の流れの図 |
| `docs/各スキルの要件.md` | スキル 15 本ごとの責務、業務要件、入力、最終出力、範囲外と、共通の要件 |
| `docs/画面のデザインシステム/` | すべての画面に共通の部品の一覧と画面の言葉。値は `ui/デザイントークン.css` が持つ |
| `docs/スキル作成の確認と承認の画面/` | AI のスキル作成をユーザーがブラウザで確認して承認する画面の、要件定義書(業務要件、責務境界、機能要件、足すスキル 2 本)と、段階 1 から 8 の画面のイメージの HTML |

テスト計画書と判定の記録は `output/<開始日時>/skills/<スキルの名前>/tests/` に置かれます。
