# skill-factory

このフォルダは、Claude Code のスキルを作る、直す、テストするための作業フォルダです。`.claude/` の下の規約、スキル、hook は、作った人の環境では実体のフォルダを指すリンクで、配られたフォルダでは実体の写しです。作成したスキルは、このフォルダの直下の `output/` に置かれます。

## 使い方

この節の手順の主語は、ユーザーです。

1. ターミナルで、このフォルダに `cd` を実行し、`claude` を起動する。
2. 次の表の形で依頼する。AI は、依頼の形から段階を決めて、始める段階と入力を返す。

| したいこと | 依頼の文 | 始める段階 |
|---|---|---|
| 新しいスキルを作る | 「<作業>をするスキルを作って」 | 1 |
| 途中の文書から続ける | 「`output/<スキルの名前>/要件定義書.md` ができたから続きをやって」(分割設計書、構成の案も同じ形) | 2、3、4 |
| 既存のスキルを照合する | 「<スキルの名前> を照合して」 | 5(指摘の一覧を見せ、直すかを聞いて止まる) |
| 既存のスキルを直す | 「<スキルの名前> の <直す内容> を直して」 | 5(先に修正、次に照合) |
| 既存のスキルのテストを作る | 「`output/<スキルの名前>/` のテストを作って」 | 5(指摘なしなら 6 へ) |
| テストの実施する範囲を決める | 「`<テスト計画書のパス>` の実施する範囲は <正常系だけ か 1 回の実行で終わるすべて か 全件>」 | 7 |
| 既存のスキルのテストを流す | 「`<テスト計画書のパス>` のテストを流して」 | 8 |
| 不合格のテストからスキルを直す | 判定の記録のパス | 5 |

スキルの名前は、`output/` の下のフォルダの名前です。依頼の形の全件は、規約 skill-making-flow の規則「最初の依頼から始める段階を決める」の表にあり、ユーザーが「ここで何ができるか」と聞いたときは、AI がその表を示します。

3. AI が聞いたときに、次の 3 つを答える。
   - 各段階の承認
   - 段階 4 の出力先(推奨は `output/<スキルの名前>/`)
   - 段階 7 の実施する範囲(推奨は「正常系だけ」)
4. 段階 8 のテストが全件合格したら、AI が返すリンクのコマンドを、スキルを使うプロジェクトで実行する。

## 確認と承認の画面で進めるとき

この節の手順の主語は、ユーザーです。画面は、AI のスキル作成をブラウザで見て、承認か直す指示を返すための画面です。

1. ターミナルで、このフォルダに `cd` を実行し、`node ui/server.mjs` を実行する。
2. ブラウザで http://127.0.0.1:4173/ を開く。
3. 画面の入力欄に、「<作業>をするスキルを作って」と書いて送る。スキルの名前は、AI が提案する。
4. 画面の右上の図と右下の文書を見て、承認のボタンを押すか、直す指示を入力欄から送る。

画面が読むファイルは、`output/<スキルの名前>/ui/` の state.json、figures/、conversation.md です。中継サーバーは、起動したあとに AI が state.json を書いたフォルダを、いまの作業のフォルダにします。中継サーバー `ui/server.mjs` は、起動ごとに 1 つの会話を作り、画面から送った文を conversation.md に書き足して、このフォルダの Claude Code に渡します(1 回目は `claude -p --session-id`、2 回目からは `claude -p --resume`)。Claude Code の途中の返事も、1 つずつ conversation.md に書き足します。どの依頼の形でも、起動のコマンドは同じです。設計は `docs/スキル作成の確認と承認の画面/設計書.html` にあります。画面の見本は、`node ui/server.mjs ui/example` で開けます。

## 前提

- Claude Code と Node.js が、claude を起動する PC に入っていること。
- `.claude/` の下に、規約 6 フォルダ、スキル 15 本、hook 3 本と settings.json があること。

## フォルダの中身

| パス | 中身 |
|---|---|
| `.claude/rules/` | 規約 6 フォルダ。text-writing、thinking、skill-or-rule、skill-writing(規約、雛形、完成例)、skill-testing(規約 skill-test-design-rule)、skill-making-flow(8 段階の流れ) |
| `.claude/skills/` | スキル 15 本。段階が使う 10 本(defining-skill-requirements、designing-skill-structure、designing-skill-phases、drafting-skill-with-template、checking-skill-with-template、fixing-skill、designing-skill-test-cases、designing-skill-test-scenarios、testing-skill-with-template、fixing-test-plan)と、hook と fixing-skill が呼ぶ補助の 3 本(checking-markdown-document-with-rules、fixing-markdown-document、rewrite-pink-elephants)と、確認と承認の画面のための 2 本(updating-skill-factory-ui-state、drawing-skill-factory-figure。実体は `output/` の下) |
| `.claude/hooks/` | hook 3 本 |
| `.claude/settings.json` | hook 3 本の登録 |
| `output/` | 作成したスキル。スキルごとのフォルダに、SKILL.md、references/、scripts/、要件定義書.md、分割設計書.md、構成の案.md、tests/ を持つ。配布しない |
| `docs/規約とスキルとhookの一覧.md` | 規約 6 フォルダ、スキル 13 本、hook 3 本ごとの、パス、読み込まれる条件か段階と、受けた検査 |
| `docs/操作の流れ.md` | 起動からリンクまでの操作の流れの図 |
| `docs/各スキルの要件.md` | スキル 13 本ごとの責務、業務要件、入力、最終出力、範囲外と、共通の要件 |
| `docs/スキル作成の確認と承認の画面/` | AI のスキル作成をユーザーがブラウザで確認して承認する画面の、要件定義書(業務要件、責務境界、機能要件、足すスキル 2 本)と、段階 1 から 8 の画面のイメージの HTML |

作ったスキルと、要件定義書、分割設計書、構成の案は `output/<スキルの名前>/` に、テスト計画書と判定の記録は `output/<スキルの名前>/tests/` に置かれます。`.claude/` は配布するフォルダで、`output/` は配布しません。
