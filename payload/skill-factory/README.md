# skill-factory

このフォルダは、Claude Code のスキルを作る、直す、テストするための作業フォルダです。`.claude/` の下の規約、スキル、hook は、作った人の環境では実体のフォルダを指すリンクで、配られたフォルダでは実体の写しです。「スキルの実体のフォルダ」の意味は、規約 skill-making-flow の章「この規約で使う語」にあります。

## 使い方

この節の手順の主語は、ユーザーです。

1. ターミナルで、このフォルダに `cd` を実行し、`claude` を起動する。
2. 次の表の形で依頼する。AI は、依頼の形から段階を決めて、始める段階と入力を返す。

| したいこと | 依頼の文 | 始める段階 |
|---|---|---|
| 新しいスキルを作る | 「<作業>をするスキルを作って」 | 1 |
| 途中の文書から続ける | 「`<スキルの実体のフォルダ>/designs/<作業の名前>/要件定義書.md` ができたから続きをやって」(分割設計書、構成の案も同じ形) | 2、3、4 |
| 既存のスキルを照合する | 「<スキルの名前> を照合して」 | 5(指摘の一覧を見せ、直すかを聞いて止まる) |
| 既存のスキルを直す | 「<スキルの名前> の <直す内容> を直して」 | 5(先に修正、次に照合) |
| 既存のスキルのテストを作る | 「`<スキルの実体のフォルダ>/<スキルの名前>/` のテストを作って」 | 5(指摘なしなら 6 へ) |
| テストの実施する範囲を決める | 「`<テスト計画書のパス>` の実施する範囲は <正常系だけ か 1 回の実行で終わるすべて か 全件>」 | 7 |
| 既存のスキルのテストを流す | 「`<テスト計画書のパス>` のテストを流して」 | 8 |
| 不合格のテストからスキルを直す | 判定の記録のパス | 5 |

スキルの名前は、スキルの実体のフォルダの下のフォルダの名前です。`.claude/skills/` にないスキルも、照合、修正、テストの対象になります。依頼の形の全件は、規約 skill-making-flow の規則「最初の依頼から始める段階を決める」の表にあり、ユーザーが「ここで何ができるか」と聞いたときは、AI がその表を示します。

3. AI が聞いたときに、次の 3 つを答える。
   - 各段階の承認
   - 段階 4 の出力先(推奨は `<スキルの実体のフォルダ>/<スキルの名前>/`)
   - 段階 7 の実施する範囲(推奨は「正常系だけ」)
4. 段階 8 のテストが全件合格したら、AI が返すリンクのコマンドを、スキルを使うプロジェクトで実行する。

## 前提

- Claude Code と Node.js が、claude を起動する PC に入っていること。
- `.claude/` の下に、規約 6 フォルダ、スキル 13 本、hook 3 本と settings.json があること。

## フォルダの中身

| パス | 中身 |
|---|---|
| `.claude/rules/` | 規約 6 フォルダ。text-writing、thinking、skill-or-rule、skill-writing(規約、雛形、完成例)、skill-testing(規約 skill-test-design-rule)、skill-making-flow(8 段階の流れ) |
| `.claude/skills/` | スキル 13 本。段階が使う 10 本(defining-skill-requirements、designing-skill-structure、designing-skill-phases、drafting-skill-with-template、checking-skill-with-template、fixing-skill、designing-skill-test-cases、designing-skill-test-scenarios、testing-skill-with-template、fixing-test-plan)と、hook と fixing-skill が呼ぶ補助の 3 本(checking-markdown-document-with-rules、fixing-markdown-document、rewrite-pink-elephants) |
| `.claude/hooks/` | hook 3 本 |
| `.claude/settings.json` | hook 3 本の登録 |
| `docs/規約とスキルとhookの一覧.md` | 規約 6 フォルダ、スキル 13 本、hook 3 本ごとの、パス、読み込まれる条件か段階と、受けた検査 |
| `docs/操作の流れ.md` | 起動からリンクまでの操作の流れの図 |
| `docs/各スキルの要件.md` | スキル 13 本ごとの責務、業務要件、入力、最終出力、範囲外と、共通の要件 |

作ったスキルは `<スキルの実体のフォルダ>/<スキルの名前>/` に、要件定義書と分割設計書と構成の案は `<スキルの実体のフォルダ>/designs/<作業の名前>/` に、テスト計画書と判定の記録は `<スキルの実体のフォルダ>/tests/<スキルの名前>/` に置かれます。
