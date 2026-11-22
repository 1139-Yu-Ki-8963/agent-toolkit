# slide-creator-studio

このフォルダは、Claude Code で、説明用のスライドを Claude デザイン(Artifact の型「Design」)の上に作るための、スキル 4 本と規約 1 本の一式です。色、文字、部品の値は、規約の中のデザインシステムが持ち、どの依頼でも同じ見た目のスライドが出ます。

## 何ができるか

- 1 つの結論を、1 枚のスライドにする。同じ 1 枚を、見せ方の違う複数の案で出す。
- 1 枚の図が、1 つの結論だけを伝えているかを判定する(1 スライド 1 メッセージ)。
- スライドごとの結論の並びが、1 つの話として通るかを判定する。
- 決まった並びのとおりに、スライドを 1 つの資料に組み立てる。

## 入っているもの

```
.claude/
├── skills/
│   ├── creating-claude-design-slide/      1 枚を作る
│   ├── checking-one-slide-one-message/    1 枚の図が、1 つの結論だけを伝えているかを判定する
│   ├── checking-slide-story/              結論の並びが、1 つの話として通るかを判定する
│   └── assembling-claude-design-slides/   決まった並びで、資料スライドに組み立てる
└── rules/slide-writing/
    ├── slide-writing-rule/                規約(構成、言葉、文字と可読性、色と図形、レイアウト、ファイルの名前)
    └── template/
        ├── ink-and-red-design-system/                    デザインシステム「墨と赤」(色、文字、グリッド、部品、間隔の値)
        │   └── illustration/                             デジタル庁のイラスト 40 点と、その利用規約
        └── ink-and-red-design-system-completed-example/  デザインシステムの見本(8 枚のスライドと、確認用の画像)
```

## イラストの著作権

`.claude/rules/slide-writing/template/ink-and-red-design-system/illustration/` の PNG 40 点は、デジタル庁の[イラストレーション・アイコン素材](https://www.digital.go.jp/policies/servicedesign/designsystem/Illustration_Icons)のファイルを、変えずに置いたものです。著作権はデジタル庁にあり、利用の条件は、同じフォルダの `LICENSE.txt` に従います。編集、加工して使うときは、出典と編集の内容の表記が要ります。

## 導入

`.claude/` の中身を、使うプロジェクトの直下の `.claude/` に置く。

```bash
cp -R .claude/skills/* <プロジェクト>/.claude/skills/
cp -R .claude/rules/slide-writing <プロジェクト>/.claude/rules/
```

## 前提

- Claude Code。ツール `Artifact` で、型「Design」の Artifact を作れること。
- サブエージェントを起動できること。2 つの判定のスキルは、読む役目に haiku、判定する役目に opus のサブエージェントを使う。
- 画像にして確かめる手順は、Playwright の MCP のツール `browser_run_code_unsafe` を使う。画像を作ると同時に、絵の欠け、フォントの読み込み、日本語の指定を自動で確かめられるためである。入れていないときは、スキルが入れてよいかを聞く。入れるコマンドは `claude mcp add playwright npx @playwright/mcp@latest`。
- このツールは、AI が書いたコードを、利用者の権限で、Claude Code のサンドボックスの外で動かせる(Playwright MCP の説明では RCE 相当)。使うたびに許可の確認が出たら、実行するコードを見て判断する。
- 規約 slide-writing-rule は、文の書き方の規約 text-writing-rule を前提にしている。text-writing-rule は、このリポジトリの `payload/skill-factory/.claude/rules/text-writing/` にある。

## 使い方

Claude Code に、次の形で依頼する。

| したいこと | 依頼の文の例 | 動くスキル |
|---|---|---|
| 図を 1 枚作る | 「<内容>を 1 枚のスライドにして」 | creating-claude-design-slide |
| 同じ 1 枚を、複数の案で見る | 「このページを 3 パターンで見たい」 | creating-claude-design-slide |
| 図が伝わるかを確かめる | 「このスライドは、1 メッセージになっている?」 | checking-one-slide-one-message |
| 話の流れを相談する | 「この順で、話が通るかを見て」 | checking-slide-story |
| 資料にまとめる | 「この順で、資料スライドに組み立てて」 | assembling-claude-design-slides |

資料を作るときの流れ:

1. 結論の文を並べて、checking-slide-story で、話が通るかを判定する。判定はチャットに出るので、順序をチャットで話し合う。
2. 並びが決まったら、assembling-claude-design-slides で、資料に組み立てる。足りないページは、creating-claude-design-slide が作る。
3. できた図を、checking-one-slide-one-message で判定し、伝わらない図を直す。

## 判定の仕組み

2 つの判定のスキルは、役目を 3 つに分ける。

- 進める役目: スキルを動かしている AI。材料を用意し、結果をチャットに出す。合否は決めない。
- 読む役目: haiku のサブエージェント。図か、結論の文だけを、初めて見る人として読む。性能の高くないモデルが読み取れない所は、初めて見る人がつまずく所である。
- 判定する役目: opus のサブエージェント 1 人。読む役目が読み取ったことを、結論の一文と比べて、合否を決める。

## 作ったスライドの置き場と、公開するものの選び方

作ったスライドと、公開するものを、2 つのフォルダに分けて置く。

- `output-slides/<作る日>_<資料の名前>/`: スキルが作った元のファイル(`.dc.html`、`canvas.json`、確認用の画像)と、1 つにまとめた HTML の置き場。このフォルダは公開しない。
- `payload/<作る日>_<資料の名前>/`: ユーザーが公開すると選んだ成果物だけを、`output-slides/` のファイルへの symlink で置く。公開の側は、このフォルダだけを写す。

公開するときは、次の順で進める。

1. `payload/` の下に、選んだファイルへの相対パスの symlink を置く。
2. 公開の側の承認の記録に、そのファイルの行を足す。
3. 公開の側で同期のスクリプトを走らせ、写したものをコミットして push する。

## デザインを足す

別のデザインを使うときは、`.claude/rules/slide-writing/template/` の下に、`<名前>-design-system/` と `<名前>-design-system-completed-example/` を足す。デザインシステムが持つ章は、規約の節「デザインシステムが持つもの」が決めている。
