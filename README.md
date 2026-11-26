# agent-toolkit

Claude Code で使うスキル集を、公開できると判断した範囲だけ選んで配布するリポジトリ。各スキル集は `payload/` の下に 1 フォルダずつ置き、正本(private な作業環境)から `scripts/sync-payload.mjs` で写す。

2026-09-29 に、PC 全体の環境をセットアップする bundle `claudecode-global-setup`(スキル、規約、hook、サブエージェント、インストーラ)を閉じた。正本の側が 2026-09-20 に全面解体され、配布物だけが残っていたため。いまの配布物は、フォルダを置くだけで動くスキル集だけである。

## 導入

`payload/public-skills/.claude/` の中身を、使うプロジェクトの直下の `.claude/` に置く。settings.json への追加は要らない。

```bash
git clone https://github.com/1139-Yu-Ki-8963/agent-toolkit.git
cp -R agent-toolkit/payload/public-skills/.claude/rules/<規約のフォルダ> <プロジェクト>/.claude/rules/
cp -R agent-toolkit/payload/public-skills/.claude/skills/<スキル名> <プロジェクト>/.claude/skills/
```

`~/.claude/skills/` や `~/.claude/rules/` には置かない。規約は作業中のプロジェクトの中のファイルにしか効かないため、`~/.claude/` の下に置いたスキルを読んでも規約が読み込まれず、スキルが最初の step で中止する。

## payload 構成

```
payload/
├── public-skills/                        プロジェクトの .claude/ に置いて動く公開スキル集
│   ├── README.md
│   └── .claude/
│       ├── rules/                        規約 3 つ(rule-writing、hook-writing、behavior)
│       └── skills/
│           ├── revising-skill-writing-rule/
│           ├── checking-ui-with-rules/
│           ├── fixing-ui-with-rules/
│           ├── managing-textlint-banned-words/
│           ├── converting-mermaid-md-to-html/
│           └── reporting-textlint-findings/
├── ai-consulting-toolkit/                AI 推進コンサルタントの道具箱
│   ├── README.md                         業務フロー・ドキュメント一覧・スキル一覧の入口
│   ├── .claude/skills/                   consult-* スキル
│   ├── docs/                             業務フロー、判定基準、テンプレート、案件フォルダ設計(14)
│   ├── templates/案件雛形/               新しい案件を始めるとき複製するフォルダ一式
│   └── portal/                           業務管理ポータル(データは架空のプロトタイプ)
├── slide-creator-studio/                 Claude デザインの上にスライドを作るスキルと規約
│   ├── README.md
│   ├── .claude/
│   │   ├── rules/slide-writing/  スライドの書き方の規約、デザインシステム「墨と赤」、見本
│   │   └── skills/
│   │       ├── creating-claude-design-slide/
│   │       ├── checking-one-slide-one-message/
│   │       ├── checking-slide-story/
│   │       └── assembling-claude-design-slides/
│   ├── slides/2026-11-14_理想のAI駆動開発フロー/理想のAI駆動開発フロースライド.html   スキルで作った資料 11 枚
│   ├── slides/2026-11-14_AI駆動開発フローの資料マップ/AI駆動開発フローの資料マップ.html   工程ごとに作る資料の図
│   ├── slides/2026-11-16_AIエージェントの誤りを止める層の形/AIエージェントの誤りを止める層の形の活用例.md   スライド 2 枚の資料の、見せる場面と目的
│   ├── slides/2026-11-16_AIエージェントの誤りを止める層の形/AIエージェントの誤りを止める層の形スライド.html   良い例と失敗例のスライド 2 枚
│   ├── slides/2026-11-17_開発成果物における不整合の定義/開発成果物における不整合の定義スライド.html   不整合の 10 の型のスライド 1 枚
│   ├── slides/2026-11-19_PoCを前提にした基本設計書の管理/PoCを前提にした基本設計書の管理スライド.html   画面の図と番号で設計書を管理する仕組みのスライド 18 枚
│   └── slides/2026-11-19_PoCを前提にした基本設計書の管理/画面基本設計書のサンプル.html   その仕組みで作った設計書のサンプル 1 本
├── engineering-handbook/                 ベテランエンジニアのように振る舞わせる規約 2 本とスキル 9 本
│   ├── README.md
│   ├── LICENSE                           MIT(pstack 由来の部分を含む)
│   ├── NOTICE.md                         もとにした pstack の著作権表示と、ファイルの対応
│   ├── rules/                            .claude/rules/ に置く規約(veteran-engineer、agent-behavior)
│   └── skills/                           .claude/skills/ に置くスキル(investigate、bug-fix など 9 本)
├── skill-static-checker/                 スキルの構造と危険の静的チェックと、重複の検査を行うスキル 2 本
│   ├── README.md
│   ├── スキルとツールの責務.html          step ごとのツールと AI の受け持ちの一覧
│   ├── SkillEvaluator との対応.md         SkillEvaluator のどの検査を写したかの記録
│   ├── .claude/skills/                   スキル 2 本と、テスト計画書と判定の記録
│   └── sample-reports/                   報告の HTML の見本 4 本
├── test-skills/                          資料「品質保証のテストの 2 つの軸」のテストの道具の skill 12 本
│   ├── README.md
│   ├── LICENSE                           MIT(pstack、break-ui、gstack 由来の部分を含む)
│   ├── NOTICE.md                         もとにした作品と、ファイルの対応
│   ├── setup.sh                          designing-test-cases が使う Python のパッケージを確かめる
│   ├── .claude/skills/                   skill 12 本(gstack から作った gstack-qa など 6 本を含む)
│   └── third-party/gstack/               gstack のライセンスと、gstack がもとにした作品の表示
```

2026-09-29 に、reverse-docs-skills、claude-code-template、explanation-slides-kit、ai-driven-development-setup、ai-consulting-toolkit の公開をやめた。2026-10-05 に、`.claude/` 配下の構成に改め、規約を 1 ファイル版に一本化し、reviewing-agent-skills(checking-skill-with-template に置き換え)の公開をやめた。同日、ai-consulting-toolkit の公開を再開した(skills、docs、portal に加え、templates と README.md を同期)。

## ai-consulting-toolkit(AI 推進コンサルタントの道具箱)

顧客企業の現場業務をヒアリングし、AI 化の提案・導入・運用管理までを進めるための道具箱。使い方は [`payload/ai-consulting-toolkit/README.md`](payload/ai-consulting-toolkit/README.md) にある。新しい案件は `templates/案件雛形/` を複製して始め、決まりは `docs/14_案件フォルダ設計/案件フォルダ設計.md` にある。

## slide-creator-studio(Claude デザインの上にスライドを作る)

説明用のスライドを、Claude デザイン(Artifact の型「Design」)の上に作る一式。規約(見た目の原則と中身の原則)、デザインシステム 3 つ(「墨と赤」と「青と灰」と「紺と紫」。値、部品の意図、型ごとのテンプレート。「紺と紫」は、2026-11-25 に足した)、機械のチェックツール(`tools/`。描く、測る、検査する)、スキル 2 本(スライドを作る、全ページを 1 つの HTML にまとめる)を持つ。2026-11-25 に、この構成に入れ替えた。使い方は [`payload/slide-creator-studio/README.md`](payload/slide-creator-studio/README.md) にある。2026-11-14 に公開を始めた。

slide-creator-studio のデザインシステム「墨と赤」と「紺と紫」は、デジタル庁の[イラストレーション・アイコン素材](https://www.digital.go.jp/policies/servicedesign/designsystem/Illustration_Icons)の同じイラスト 40 点を、変えずに持つ。素材の著作権はデジタル庁にあり、利用の条件は、同梱の [`LICENSE.txt`](payload/slide-creator-studio/design-systems/ink-and-red/illustration/LICENSE.txt) に従う。墨と赤は 2026-11-22 に、紺と紫は 2026-11-25 に公開を始めた。

このスキルで作った資料「理想の AI駆動開発フロー(一般論)」11 枚を、1 つの HTML ファイルにまとめて [`payload/slide-creator-studio/slides/`](payload/slide-creator-studio/slides/2026-11-14_理想のAI駆動開発フロー/理想のAI駆動開発フロースライド.html) に置いている。ファイルを落としてブラウザで開き、← → かスペースでページを送る。3 枚目は、周回のボタンを押すと動く。10 枚目は、基本設計の合格を、設計書だけを別の AI に読ませて推測の数で確かめる方法を示す。2026-11-16 に公開を始めた。

slide-creator-studio の側では、作ったスライドを非公開の `output-slides/` に置き、公開すると選んだものだけを `payload/` に symlink で置く。この toolkit は、その `payload/` だけを `payload/slide-creator-studio/slides/` に写す(`sync-manifest.json` の mirror の `symlinkRoot`)。

資料「AI 駆動開発フローの資料マップ」は、AI 駆動開発の工程ごとに作る資料と、用意する順を、縦の 1 枚の図にした HTML 1 本([`payload/slide-creator-studio/slides/2026-11-14_AI駆動開発フローの資料マップ/AI駆動開発フローの資料マップ.html`](payload/slide-creator-studio/slides/2026-11-14_AI駆動開発フローの資料マップ/AI駆動開発フローの資料マップ.html))。図は、右上のボタン、ホイール、ドラッグで拡大と移動ができ、資料の札を押すと、その資料の説明のスライドが重なって出る。2026-11-19 に、ドキュメントの規約、入力チェックの共通ルール、画面項目の定義書、動く設計書、API 仕様書、テストコードの規約、単体テストの仕様書、共通レイアウトの定義書の 8 枚の中身を、具体の例に直した。見る人は、ファイルを落として、ブラウザで開く。拡大と移動には @panzoom/panzoom 4.6.2(MIT)を HTML の中に入れて使っている。2026-11-16 に公開を始めた。

資料「AIエージェントの誤りを止める層の形」(スライド 2 枚)を、どの場面で、どの目的で見せるかをまとめた md 1 本を、[`payload/slide-creator-studio/slides/2026-11-16_AIエージェントの誤りを止める層の形/AIエージェントの誤りを止める層の形の活用例.md`](payload/slide-creator-studio/slides/2026-11-16_AIエージェントの誤りを止める層の形/AIエージェントの誤りを止める層の形の活用例.md) に置いている。2026-11-17 に公開を始めた。

その 2 枚(良い例「上で止める逆三角形」と、失敗例「下にたまる砂時計」)は、1 つの HTML にまとめて [`payload/slide-creator-studio/slides/2026-11-16_AIエージェントの誤りを止める層の形/AIエージェントの誤りを止める層の形スライド.html`](payload/slide-creator-studio/slides/2026-11-16_AIエージェントの誤りを止める層の形/AIエージェントの誤りを止める層の形スライド.html) に置いている。ファイルを落としてブラウザで開き、← → かスペースでページを送る。2026-11-17 に公開を始めた。

資料「開発成果物における不整合の定義」は、規約・設計書・コード・テスト・設定のあいだの食い違いを、上と下、同じ層、文書と実物、前と後の 4 つの比べ方で 10 の型に分けた図を、スライド 1 枚にした HTML 1 本([`payload/slide-creator-studio/slides/2026-11-17_開発成果物における不整合の定義/開発成果物における不整合の定義スライド.html`](payload/slide-creator-studio/slides/2026-11-17_開発成果物における不整合の定義/開発成果物における不整合の定義スライド.html))。ファイルを落としてブラウザで開く。2026-11-17 に公開を始めた。

資料「PoCを前提にした基本設計書の管理」は、設計書の md に書いた番号と説明を、試作した画面(PoC)の部品に重ねて表示し、画面と設計書のずれを CI で止め、PR の承認とタグで版を残す仕組みと、ふるまいを 3 つの表で書く書き方、設計書と共通規約と API の設計書の分け方、規約からテストを作る流れを、18 枚で説明したスライド([`payload/slide-creator-studio/slides/2026-11-19_PoCを前提にした基本設計書の管理/PoCを前提にした基本設計書の管理スライド.html`](payload/slide-creator-studio/slides/2026-11-19_PoCを前提にした基本設計書の管理/PoCを前提にした基本設計書の管理スライド.html))。ファイルを落としてブラウザで開き、← → かスペースでページを送る。2026-11-19 に公開を始めた。

その仕組みで作った設計書のサンプルを、[`payload/slide-creator-studio/slides/2026-11-19_PoCを前提にした基本設計書の管理/画面基本設計書のサンプル.html`](payload/slide-creator-studio/slides/2026-11-19_PoCを前提にした基本設計書の管理/画面基本設計書のサンプル.html) に置いている。架空の「会議室予約」の画面 1 つ分の基本設計書で、画面の部品ごと 1 つの HTML にまとめてある。PoC を別に触れる前提の構成で、スマホと PC の図に番号の枠が付き、項目定義表、条件と期待結果の表、状態遷移表、保存する中身、PoC と本番の違い、決めた理由、承認の記録を持つ。上のタブで、どの画面にも共通の決まりを書いた「画面の共通規約」に切り替えられる。ファイルを落としてブラウザで開く。2026-11-19 に公開を始めた。

資料「会員サイトの申込の画面の作り直しの提案」は、デザインシステム「紺と紫」で作った、Web 開発の提案の見本 19 枚(課題、提案、進め方の 3 つの章と、数字の出どころの付録)を、1 つの HTML にまとめたもの([`payload/slide-creator-studio/slides/2026-11-24_会員サイトの申込の画面の作り直しの提案/会員サイトの申込の画面の作り直しの提案スライド.html`](payload/slide-creator-studio/slides/2026-11-24_会員サイトの申込の画面の作り直しの提案/会員サイトの申込の画面の作り直しの提案スライド.html))。中身は架空。ファイルを落としてブラウザで開き、← → かスペースでページを送る。2026-11-25 に公開を始めた。

## engineering-handbook(ベテランエンジニアのように振る舞わせる規約とスキル)

Claude Code に、ベテランエンジニアの判断と作業の進め方をさせるための一式。規約 2 本(ベテランエンジニアの振る舞い、エージェントの振る舞い)と、作業ごとのスキル 9 本(調査、試作、計画、機能追加、バグ修正、リファクタ、性能改善、PR 作成、PR 対応)からなる。スキルは規約がなくても単体で動く。`rules/` を `.claude/rules/` に、`skills/` を `.claude/skills/` に、必要なものだけ写して使う。使い方は [`payload/engineering-handbook/README.md`](payload/engineering-handbook/README.md) にある。

Cursor の公式プラグインリポジトリにある pstack(作者 Lauren Tan、MIT License)を、日本語に訳し、要約し、Claude Code で単体で動くように作り直したもの。ライセンスは [`payload/engineering-handbook/LICENSE`](payload/engineering-handbook/LICENSE)、もとにしたファイルの対応は [`payload/engineering-handbook/NOTICE.md`](payload/engineering-handbook/NOTICE.md) にある。2026-11-17 に公開を始めた。

## skill-static-checker(スキルの構造と危険の静的チェックと、重複の検査)

2 本のスキルを持つ。NVIDIA の SkillEvaluator の Tier 1 と Tier 2 に当たる検査を、日本語のスキルと skill-factory の規約に合わせて行う。

- scoring-skill-structure-and-danger: スキルのフォルダを動かさずに調べ、構造の点数(100 点から減点し、70 点が合格ライン)と、危険の合否を出し、報告の HTML を書く。Tier 1 に当たる。
- checking-skill-duplication: スキルの中で同じ指示を繰り返す節と、役目が重なるほかのスキルを、判定者 2 人(サブエージェント)に仕分けさせ、重複の検査の合否と報告の HTML を出す。Tier 2 に当たり、節の本文を埋め込みの提供元に送らない。

どちらも、スキルのフォルダを `.claude/skills/` に写して使う。node が要る。step ごとのツールと AI の受け持ちは [`payload/skill-static-checker/スキルとツールの責務.html`](payload/skill-static-checker/スキルとツールの責務.html)、SkillEvaluator のどの検査を写したかは [`payload/skill-static-checker/SkillEvaluator との対応.md`](<payload/skill-static-checker/SkillEvaluator との対応.md>) にある。スキルが名前で挙げる規約は、[`payload/skill-factory/.claude/rules/`](payload/skill-factory/.claude/rules/) にある。報告の見本は [`payload/skill-static-checker/sample-reports/`](payload/skill-static-checker/sample-reports/) にあり、ファイルを落としてブラウザで開く。使い方は [`payload/skill-static-checker/README.md`](payload/skill-static-checker/README.md) にある。2026-11-19 に公開を始めた。

## test-skills(品質保証のテストの道具)

slide-creator-studio の資料「品質保証のテストの 2 つの軸」で挙げたテストの道具を、Claude Code の skill として集めた 12 本。形式検証、仕様のテスト、UI/UX、セキュリティ、性能、互換性、信頼性の項目ごとに、skill を当てている。このフォルダで Claude Code を開くか、skill のフォルダを `.claude/skills/` に写して使う。使い方は [`payload/test-skills/README.md`](payload/test-skills/README.md) にある。

gstack(作者 Garry Tan、MIT License)の qa、design-review、ios-design-review、cso、benchmark、canary を日本語に訳し、名前の前に `gstack-` を付けた 6 本を含む。この 6 本は、gstack の道具を `~/.claude/skills/gstack/` から呼ぶので、gstack を gstack の手順で入れておく必要がある。ほかの 6 本のうち 5 本は、pstack と break-ui をもとにした。ライセンスは [`payload/test-skills/LICENSE`](payload/test-skills/LICENSE)、もとにした作品は [`payload/test-skills/NOTICE.md`](payload/test-skills/NOTICE.md) にある。2026-11-27 に公開を始めた。

## public-skills(プロジェクトに置いて動く公開スキル集)

各スキルは、他のスキルを参照せず単体で動く。導入手順と一覧は [`payload/public-skills/README.md`](payload/public-skills/README.md) にある。

| スキル | 何をするか | 前提 |
|---|---|---|
| [`revising-skill-writing-rule`](payload/public-skills/.claude/skills/revising-skill-writing-rule/SKILL.md) | スキル作成の規約の一式(規約、雛形、完成例)に決まりを足す、直す、消す依頼を、既にある決まりと突き合わせて、置く位置を決め、承認を得て反映する | 規約の一式(skill-factory の `.claude/rules/skill-writing`)。パスで渡す |
| [`checking-ui-with-rules`](payload/public-skills/.claude/skills/checking-ui-with-rules/SKILL.md) | ルールの文書を規約にし、画面のファイルと画面を照合者 2 人に見比べさせ、指摘の一覧を結果のフォルダに書く。直したあとの調べ直しも受け持つ | node、npm、git。画面の URL を渡すときは Playwright と Chromium(スキルが入れる) |
| [`fixing-ui-with-rules`](payload/public-skills/.claude/skills/fixing-ui-with-rules/SKILL.md) | checking-ui-with-rules の指摘の一覧のうち、頼まれた番号の指摘だけを画面のファイルに直し、調べ直しの頼み方を出す | node、npm |
| [`managing-textlint-banned-words`](payload/public-skills/.claude/skills/managing-textlint-banned-words/SKILL.md) | textlint の禁止語の辞書と設定と hooks を依頼どおりの状態にし、辞書を一覧で表示する | node、npm。textlint のパッケージはスキルが入れる |
| [`converting-mermaid-md-to-html`](payload/public-skills/.claude/skills/converting-mermaid-md-to-html/SKILL.md) | Mermaid の図を含む md 1 本を、図を描画した 1 ページの HTML に変換する | hugo(extended)。無ければスキルが入れ方を案内する |
| [`reporting-textlint-findings`](payload/public-skills/.claude/skills/reporting-textlint-findings/SKILL.md) | md を textlint で検査し、指摘箇所に波線を引いた HTML を書き出す | node と textlint のパッケージ(一覧はスキルの SKILL.md) |

スキルを作る流れのスキルと規約 skill-writing は、[`payload/skill-factory/`](payload/skill-factory/) にある。規約は、プロジェクトの `.claude/skills/` の下のファイルを読むか書くときに自動で読み込まれる。

## 更新(payload の同期)

`payload/` の中身は、private な正本のコピーである。`scripts/sync-manifest.json` の対応表に基づき、`scripts/sync-payload.mjs --check` で乖離を検知し、`--apply` で同期する。`git commit` 時には `scripts/check-payload-sync.sh` が乖離を検知して止める。公開の可否は `scripts/public-approval-ledger.md` に記録する。詳細は `CLAUDE.md` を参照。

## ディレクトリ構成

```
agent-toolkit/
├── README.md
├── CLAUDE.md                        このリポジトリで作業する AI 向けの手順書
├── .claude/settings.json            commit 時の同期検査 hook 2 本
├── payload/                         配布物(上の「payload 構成」)
└── scripts/
    ├── sync-manifest.json           正本 → payload の対応表
    ├── sync-payload.mjs             乖離検知と同期(--list / --check / --check-artifacts / --apply)
    ├── check-payload-sync.sh        commit 時に乖離を検知して止める hook
    ├── check-payload-artifacts.sh   commit 時に配布禁止の生成物を検知して止める hook
    ├── payload-artifacts.json       配布禁止パターン(公開側は枠だけ)
    └── public-approval-ledger.md    公開承認台帳
```

## 要件

- 利用者: Claude Code。スキルごとの前提は各スキルの SKILL.md に書いてある。
- 保守者: Node.js 18 以上(同期スクリプト)、bash と jq(commit 時の hook)。

ライセンスは現時点で指定されていない。再配布や利用条件が必要な場合はリポジトリ所有者へ確認すること。
