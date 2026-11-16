# engineering-handbook

Claude Code に、ベテランエンジニアのように振る舞わせるための規約と skill の集まりです。日本語で書いています。

- **規約(rules)。** どの作業でも常に効く振る舞いの基準です。2つあります。
- **skill。** 調査、バグ修正、機能追加のような作業ごとの手順です。9本あります。

skill は規約がなくても単独で動きます。必要な原則の要点を、各 skill の本文に直接書いているためです。規約と skill は、必要なものだけを選んで入れられます。

## 構成

```
engineering-handbook/
  README.md
  LICENSE
  NOTICE.md
  rules/
    veteran-engineer.md     ベテランエンジニアの振る舞い規約(V-01〜V-12)
    agent-behavior.md       エージェントの振る舞い規約(A-01〜A-12)
  skills/
    investigate/SKILL.md    調査
    prototype/SKILL.md      試作
    plan/SKILL.md           計画
    feature/SKILL.md        機能追加
    bug-fix/SKILL.md        バグ修正
    refactor/SKILL.md       リファクタ
    performance/SKILL.md    性能改善
    open-pr/SKILL.md        PR 作成
    pr-followup/SKILL.md    PR 対応
```

## 導入

Claude Code は、プロジェクトの `.claude/rules/` にある規約と、`.claude/skills/` にある skill を自動で読み込みます。このリポジトリの `rules/` と `skills/` を、そこへコピーします。

この一式は [agent-toolkit](https://github.com/1139-Yu-Ki-8963/agent-toolkit) の `payload/engineering-handbook/` で配布しています。

```bash
# 配布リポジトリを取得する
git clone https://github.com/1139-Yu-Ki-8963/agent-toolkit.git ~/agent-toolkit

# 導入先のプロジェクトで実行する
mkdir -p .claude/rules .claude/skills
cp ~/agent-toolkit/payload/engineering-handbook/rules/*.md .claude/rules/
cp -R ~/agent-toolkit/payload/engineering-handbook/skills/* .claude/skills/
```

すべてのプロジェクトで使いたい場合は、コピー先を `~/.claude/rules/` と `~/.claude/skills/` にします。

一部だけ入れることもできます。

```bash
# 規約だけ
cp ~/agent-toolkit/payload/engineering-handbook/rules/*.md .claude/rules/

# バグ修正と PR 作成の skill だけ
cp -R ~/agent-toolkit/payload/engineering-handbook/skills/bug-fix ~/agent-toolkit/payload/engineering-handbook/skills/open-pr .claude/skills/
```

## 規約

| ファイル | 内容 | 対象 |
|---|---|---|
| `rules/veteran-engineer.md` | 設計するとき(V-01〜V-07)と、正しさを示すとき(V-08〜V-12)の判断基準 | 人間とエージェント |
| `rules/agent-behavior.md` | 作業を始めるとき、判断に迷ったとき、作業中、報告するときの振る舞い | エージェントのみ |

コーディング規約(命名、型の使い方など)は含みません。チームの既存のコーディング規約と組み合わせて使ってください。

規約は常にコンテキストに読み込まれます。2つ合わせて約250行あります。重いと感じたら、各項目の「なぜ」を削るのが一番効果的です。

## skill

| skill | いつ使うか | 主に使う規約 |
|---|---|---|
| `investigate` | 「どう動いているか」「なぜこうなっているか」を調べる。コードは変えない | A-10、A-11 |
| `prototype` | 方式や見た目で案が割れたとき、使い捨ての試作を比べて決める | V-03、A-04 |
| `plan` | 大きな作業を、検証できる小さな PR の並びに分ける。実装はしない | V-06、V-12 |
| `feature` | 新しい振る舞いを、設計から PR まで作る | V-01、V-02、V-08 |
| `bug-fix` | 再現、原因の特定、修正、同じ方法での確認まで行う | V-09、V-10 |
| `refactor` | 振る舞いをテストで固定し、構造だけを変える | V-04、V-06 |
| `performance` | 計測で上限の要因を特定し、変更前後の数字で効果を示す | V-11 |
| `open-pr` | 差分を掃除し、コミットを並べ、PR を開く | V-12、A-12 |
| `pr-followup` | コンフリクト、レビューの指摘、CI の失敗を片付け、マージできる状態にする | A-05 |

skill は、依頼の内容から Claude Code が自動で選びます。名前を指定して呼ぶこともできます(例: `/bug-fix`)。

作業の流れの例です。

- **小さなバグ。** `bug-fix` → `open-pr`
- **新しい機能。** `investigate` → `prototype`(案が割れたら) → `feature` → `open-pr` → `pr-followup`
- **大きな移行。** `investigate` → `plan` → PR ごとに `refactor` か `feature` → `open-pr`

## ID の付け方

規約の各項目には ID があります。

- `V-01`〜: ベテランエンジニアの振る舞い規約
- `A-01`〜: エージェントの振る舞い規約

skill の末尾の「使っている規約」には、その skill が本文に取り込んでいる規約の ID を並べています。規約を変更したときは、ID で検索すれば、影響する skill が分かります。

```bash
grep -rn "V-09" skills/
```

## 自分のプロジェクトに合わせる

skill は、どの言語、どのフレームワークでも使えるように書いています。次の箇所は、プロジェクトに合わせて書き換えると効果が上がります。

- **実物で確かめる方法。** 画面の確認に使うツール(Playwright など)、API の確認方法を、`feature`、`bug-fix` の「実物で確かめる」手順に書き足す。
- **テスト、型チェック、リントのコマンド。** 各 skill の完了の条件に、実際のコマンドを書き足す。
- **PR の運用。** タイトルの形式、向け先のブランチ、ドラフトで開くかどうかを、`open-pr` に合わせる。
- **元に戻せない操作。** 本番データベースのマイグレーションなど、止まって確認すべき操作を `rules/agent-behavior.md` の A-03 に足す。

## 出典

この規約と skill は、Cursor の公式プラグインリポジトリにある [pstack](https://github.com/cursor/plugins/tree/main/pstack)(作者 Lauren Tan、MIT License)をもとに、日本語に訳し、要約し、どの環境でも単独で動くように作り直したものです。pstack の Cursor 固有の機能、複数モデルの使い分け、他の skill への依存は取り除いています。詳細は [NOTICE.md](./NOTICE.md) を見てください。

## ライセンス

MIT License。[LICENSE](./LICENSE) を見てください。
