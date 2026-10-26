# skill-factory

このフォルダは、Claude Code のスキルを作る、直す、テストするための作業フォルダです。`.claude/` の下の規約、スキル、hook は、作った人の環境ではスキルの実体のフォルダを指すリンクで、配られたフォルダでは実体の写しです。スキルの実体のフォルダは、規約 skill-making-flow の章「この規約で使う語」で決めています。

## 使い方

1. ターミナルで、このフォルダに `cd` を実行し、`claude` を起動する。
2. 次の表の形で依頼する。AI は、依頼の形から段階を決めて、始める段階と入力を返す。

| したいこと | 依頼の文 | 始める段階 |
|---|---|---|
| 新しいスキルを作る | 「<作業>をするスキルを作って」 | 1 |
| 別のフォルダで書いた依頼の控えからスキルを作る | 「`docs/inbox/<ファイル名>` のスキルを作って」 | 1 |
| 途中の文書から続ける | 「`docs/<作業の名前>/要件定義書.md` ができたから続きをやって」(分割設計書、構成の案も同じ形) | 2、3、4 |
| 既存のスキルを照合する | 「<スキルの名前> を照合して」 | 5(指摘の一覧を見せ、直すかを聞いて止まる) |
| 既存のスキルを直す | 「<スキルの名前> の <直す内容> を直して」 | 5(先に修正、次に照合) |
| 既存のスキルのテストを作る | 「`<スキルの実体のフォルダ>/<スキルの名前>/` のテストを作って」 | 5(指摘なしなら 6 へ) |
| テストの実施する範囲を決める | 「`<テスト計画書のパス>` の実施する範囲は <正常系だけ か 1 回の実行で終わるすべて か 全件>」 | 7 |
| 既存のスキルのテストを流す | 「`<テスト計画書のパス>` のテストを流して」 | 8 |
| 不合格のテストからスキルを直す | 判定の記録のパス | 5 |

スキルの名前は、スキルの実体のフォルダの下のフォルダの名前です。`.claude/skills/` にないスキルも、照合、修正、テストの対象になります。依頼の形の全件は、規約 skill-making-flow の規則「最初の依頼から始める段階を決める」の表にあり、「ここで何ができるか」と聞いたときは AI がその表を示します。

3. 各段階の承認と、段階 4 の出力先(推奨は `<スキルの実体のフォルダ>/<スキルの名前>/`)、段階 7 の実施する範囲(推奨は「正常系だけ」)は、AI が聞いたときに答える。
4. 段階 8 のテストが全件合格したら、AI が返すリンクのコマンドを、スキルを使うプロジェクトで実行する。

## 前提

- Claude Code と Node.js が、この機械に入っていること。
- `.claude/` の下に、規約 6 フォルダ、スキル 13 本、hook 3 本と settings.json があること。

## フォルダの中身

| パス | 中身 |
|---|---|
| `.claude/rules/` | 規約 6 フォルダ。text-writing、thinking、skill-or-rule、skill-writing(規約、雛形、完成例)、skill-testing(規約 skill-test-design-rule)、skill-making-flow(8 段階の流れ) |
| `.claude/skills/` | スキル 13 本。段階が使う 10 本(defining-skill-requirements、designing-skill-structure、designing-skill-phases、drafting-skill-with-template、checking-skill-with-template、fixing-skill、designing-skill-test-cases、designing-skill-test-scenarios、testing-skill-with-template、fixing-test-plan)と、hook と fixing-skill が呼ぶ補助の 3 本(checking-markdown-document-with-rules、fixing-markdown-document、rewrite-pink-elephants) |
| `.claude/hooks/` | hook 3 本 |
| `.claude/settings.json` | hook 3 本の登録 |
| `docs/<作業の名前>/` | 段階 1 から 3 が書く要件定義書、分割設計書、構成の案 |
| `docs/inbox/` | 別のフォルダで書いた依頼の控え |

作ったスキルは `<スキルの実体のフォルダ>/<スキルの名前>/` に、テスト計画書と判定の記録は `<スキルの実体のフォルダ>/tests/<スキルの名前>/` に置かれる。
