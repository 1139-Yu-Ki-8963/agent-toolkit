---
paths:
  - "**/ai-management-portal/**"
---

# ポータルページ構成規約（PORTAL-PAGE-CONVENTIONS）

`agent-home/ai-management-portal/` のページファミリー分類・ツール名表記・並び順を定義し、`data/manifest.js` / `claude/*.html` / `design/*.html` / `architecture/*.html` / `catalog/*.html` / `index.html` を横断する不整合を検知する規約。

## 背景

「設定すべきツール一覧」ページ（`claude/tooling.html`）と、CLAUDE.md/Rules/Skills/Subagents/Hooks/Output styles/Statusline の各設計ガイド・登録一覧を追加する過程で、以下 3 種類の不整合が実際に発生した。いずれも「そのページを作る瞬間には気づけないが、サイト全体を横断すると露見する」性質のものであり、単発の目視レビューでは再発を防げない。

1. **ツール名の表記ゆれ**: 一部を日本語カタカナ（例: アウトプットスタイル）、一部を英語（Rules/Skills/Hooks 等）で書いた
2. **遷移先の種別混在**: 早見表からのリンクが、あるツールは登録一覧（`catalog/`）、別のツールは設計ガイド（`design/`）を指し、目的の異なる 2 系統が無自覚に混ざった
3. **並び順のバラバラ**: 同じ 7 ツールの並び順が、早見表・設計ガイド一覧・登録一覧・TOP ページの規模サマリカードでそれぞれ違っていた

## フォルダマップ

| パス | 役割 |
|---|---|
| `index.html` | SPA 本体。規模サマリとカテゴリ別ナビゲーションを提供する |
| `catalog/` | スキル・hook・ルール・エージェント等の一覧アプリ |
| `design/` | 設計ガイド系の文書ページ |
| `claude/` | `.claude` 設定層を解説する文書ページ |
| `architecture/` | 複数レイヤーを横断する機構の仕組み解説ページ |
| `data/` | 一覧アプリが読み込む JS データ（`manifest.js` 等） |
| `src/` | `index.html` の SPA を動かすスクリプト一式 |
| `src/common/` | 全ページ共通の拡張スクリプト（header.js が集約する） |

## 1. ページファミリーの4分類

| ディレクトリ | 役割 | 判定基準 |
|---|---|---|
| `claude/*.html` | `.claude` ディレクトリ自体の見取り図（アーキテクチャ・ディレクトリ構造・設定ファイル概要など） | 「.claude の中身を俯瞰したい」時に見るページ |
| `design/*.html` | 各設定層の「書き方・仕様」を規定する実務ガイド（frontmatter 仕様・命名規約・判定フロー・チェックリスト） | 「これから作る/直す」時に見るページ。呼称は「設計ガイド」（「設計思想」ではない） |
| `architecture/*.html` | 複数の config 層・スキル・サブエージェントがどう繋がって 1 つの機構を成すかを横断的に解説するページ（データフロー図・層構造・導入経緯） | 「この仕組みは全体としてどう動いているか」を俯瞰したい時に見るページ。単一設定層の書き方は対象外（それは `design/`） |
| `catalog/*.html` | 実際に存在するインスタンスの一覧（何個あるか・現物は何か） | 「今何がいくつあるか」を数えたい時に見るページ |

CLAUDE.md・Statusline は単一ファイルのため catalog は作らない。

新規ページを追加するときは、上記いずれの役割に該当するかを先に判定してから配置先ディレクトリを決める。役割が曖昧なまま複数ファミリーの中間的なページを作らない。`design/` と `architecture/` の主な違いは対象が単一設定層か複数レイヤー横断かであり、`claude/` と `architecture/` の主な違いは対象が `.claude` ディレクトリ自体かそれを含む機構全体か（agent-home 側のスキル・サブエージェントも含むか）である。

## 2. ツール名の表記規約

`design/config-placement.html`（既存の定義ページ、7 層判定フロー）が先例として「CLAUDE.md / Rules / Skills / Subagents / Hooks / Output styles」と英語表記している。この先例に合わせ、config 層の名称（CLAUDE.md, Rules, Skills, Subagents, Hooks, Output styles, Statusline）は**プロパーノウンとして英語表記に統一する**。

- 周辺の説明文・見出しラベルは日本語のままでよい（例:「hook が注入する〜」「ルールの定義は〜」といった一般名詞としての使用は対象外）
- カタカナ変換（例: アウトプットスタイル、フックス、スキルズ）は禁止
- 特に `claude/tooling.html` の早見表・各カタログの一覧タイトルなど、**その語がツール名そのものを指す固有名詞として使われる箇所**が対象。地の文で一般名詞として使う分には日本語表現を妨げない
- config層7層には含まれないが、`routines`（`~/agent-home/routines/` の定期実行自動化群。ディレクトリ名・ID共に英語 `routines`）も同じ理由でプロパーノウン用法は英語表記「Routines」に統一する。ページタイトル・見出し・カタログカードタイトルが対象。「13 ルーティン」「全ルーティンの実行ログ」等、地の文で対象群を指す一般名詞としての使用は対象外

## 2b. manifest id・カテゴリ id の命名規約

### manifest tool id

- 形式: kebab-case
- スキル実体名との対応原則: id はスキルの `name` フィールドと一致させる。フロー抽象 id（複数スキルを束ねる表示用 id）を使う場合は manifest.js のコメントに対応表を明記する
- 例: `orchestrating-dev-flow`（スキル実体名一致）、`worktree-required`（フロー抽象 id → コメントで `parallel-dev-worktree` スキルへの対応を記載）

### カテゴリ id

- 形式: kebab-case の英語名詞
- 語彙の統一原則: manifest.js と他の分類ファイル（`skill-categories.js` 等）で同一概念には同一語を使う
- 同概念異名の禁止: `dev` と `impl` のように同じ概念を指す異なる語を併用しない。どちらかに統一する

### カテゴリ語彙表（定義）

| カテゴリ id | 用途 | 備考 |
|---|---|---|
| flow | フロー一覧 | 開発・レビュー・運用等のスキルフロー |
| design | 設計ガイド | 各設定層の書き方・仕様ガイド |
| architecture | 仕組み解説 | 複数レイヤーを横断する機構のデータフロー・層構造解説 |
| registry | 登録一覧 | 実インスタンスの一覧 |
| claude-config | .claude 設定 | .claude ディレクトリ関連 |
| pc-config | PC 設定 | マシン設定 |
| tools | ツール設定 | MCP・Playwright 等 |

## 3. 並び順の規約

基準順序:

```
CLAUDE.md → Rules → Skills → Subagents → Hooks → Output styles → Statusline
```

根拠: `design/config-placement.html` §1 冒頭文の既存順序（「CLAUDE.md / Rules / Skills / Subagents / Hooks / Output styles の使い分けを一枚で参照できる」）を採用し、この 6 項目に含まれない Statusline を末尾に追加した。

適用箇所（現在実装済みの 4 箇所。本規約はこの並び順を今後も維持することを保証する）:

- `claude/tooling.html` の早見表（7 行フル）
- `data/manifest.js` の `design` カテゴリ内、config-layer 系 7 エントリ（`config-placement-design` / `loop-design` / `worktree-design` 等の canonical order 対象外の項目は除く）
- `data/manifest.js` の `registry` カテゴリ内、catalog を持つ 5 項目（CLAUDE.md・Statusline は catalog を持たないため対象外。`usage-catalog` も対象外）
- `index.html` の規模サマリカード内、catalog を持つ 5 項目分

`registry` カテゴリには上記 5 項目に加え routines の登録一覧（`catalog/routines.html`）のエントリも存在する。routines は基準順序（config 層 7 ツール）の判定対象外のため、並び順検証は 5 項目のみに適用し、routines のエントリは 5 項目の後ろに置く。

### 今後7ツール以外を追加する場合の並び順判断基準

新しい設定層・ツールを追加する際は、以下の順で判断する。「都度相談」で済ませず、必ずこの基準に従う。

1. `design/config-placement.html` §1 冒頭文（定義の一覧文）に当該レイヤー名が既出であれば、その文中の並び順に従って挿入位置を決める
2. 冒頭文に登場しない単独ツール（Statusline のように 7 層判定フローに含まれない設定ファイル）は、基準順序の**末尾に追加日順**（先に追加されたものを前）で並べる
3. 新レイヤー追加時は必ず `design/config-placement.html` §1 冒頭文を先に更新し、その直後に本規約の基準順序表と、上記 4 適用箇所（tooling.html 早見表 / manifest.js design カテゴリ / manifest.js registry カテゴリ / index.html 規模サマリカード）を同時に更新する。一覧文と 4 適用箇所を分離した状態で commit しない

## 4. 開発規約

1. 文書ページは `design/` / `claude/` / `architecture/` のいずれかに置く（§1 の判定基準で選ぶ）。この配置により MD コピー / MD DL / LLM コピーのボタンが自動で付く
2. ヘッダーは `src/common/header.js` が実行時に統一生成する。各ページで手書きしない
3. 共通スクリプトを追加するときは `src/common/` に置き、`header.js` の `init()` から呼び出す
4. 新規ページは `templates/page-doc.html` または `templates/page-catalog.html` をコピーして作成する。head は編集せず `{{...}}` プレースホルダの置換のみ行う
5. スキル一覧と規模サマリは手動編集しない。`node skills/managing-agent-configs/scripts/manage-portal.mjs generate` で再生成する。カテゴリの割当だけ `data/skill-categories.js` を編集する
6. コミット前に `node skills/managing-agent-configs/scripts/manage-portal.mjs verify` が exit 0 であることを確認する

## 5. ローカル配信

起動コマンド・アクセスURL（ブックマーク）の定義は同ディレクトリの `access-values.txt`（非注入サイドカー）を参照する。ポータル配下をカレントディレクトリにして `python3 -m http.server` 等を即席起動すると `/ai-management-portal/` パスが解決できず 404 になるため、必ず `access-values.txt` 記載の正規手順に従う。

## 設計判断

### check-portal-consistency（.sh / .mjs）

**必要性**: ページファミリー・表記・並び順の不整合は「そのページを作る瞬間には気づけないが、サイト全体を横断すると露見する」性質を持ち、実際に 3 種類の不整合（表記ゆれ・遷移先種別混在・並び順バラバラ）が同一セッション内で発生した。`data/manifest.js`（JS オブジェクト配列）・`claude/tooling.html`（HTML テーブル）・`index.html`（HTML カード）という異なるフォーマットを横断して並び順とリンク先系統を照合する処理は、正規表現によるブロック抽出・ID→定義名マッピング・部分列判定という複数の分岐を持ち、Bash の一行コマンドや `grep` だけでは実装できない。`check-portal-consistency.mjs`（Node）で判定ロジックを一元化し、`check-portal-consistency.sh` は PostToolUse イベントからの起動・対象ファイル判定・advisory JSON 整形のみを担う薄いラッパーとする。

**代替案を採用しなかった理由**:
- Bash ツール直叩き: 複数フォーマット横断の並び順・リンク先照合をコマンド一発で都度実行するのは非現実的で、編集のたびに手動確認が必要になる
- 既存 Makefile 拡張: `~/.claude/rules/` 配下に Makefile は存在せず、新規導入は本チェック専用の依存を増やすだけになる
- package.json scripts 追加: 同様に本ディレクトリはビルド設定を持たない

**保守責任者**: 人手（ユーザー）。基準順序・ページファミリー分類を変更する場合は本ファイルと `check-portal-consistency.mjs` の `CANON_ORDER` / `DESIGN_ID_MAP` / `REGISTRY_ID_MAP` を同時に更新する。

**廃棄条件**: `ai-management-portal` 自体が廃止された時、または一覧アプリの自動生成（`manage-portal.mjs generate`）が並び順・リンク先系統も含めて完全に決定論的生成へ移行し、事後検査が不要になった時。

設計判断・経緯の全文は同ディレクトリの `design-notes.txt` を参照（非注入サイドカー）。

## プロジェクト上書き

- 上書き可否: 一律適用
- 理由: `ai-management-portal` は agent-home リポジトリ内の単一インスタンスであり、上書きを許す下位プロジェクト構造が存在しないため受け口を設けない

## 機械強制

| timing | スクリプト | 注入タグ | 挙動 |
|---|---|---|---|
| PostToolUse(Write\|Edit\|MultiEdit) | `check-portal-consistency.sh` | `[PORTAL-CONSISTENCY-WARN]` | `data/manifest.js` / `claude/*.html` / `design/*.html` / `architecture/*.html` / `catalog/*.html` / `index.html` の編集を検知し、`check-portal-consistency.mjs` で並び順・リンク先系統・`tooling.html` の表記完全一致を検査。違反があれば advisory 注入（exit 0、block なし） |

### 機械チェックする範囲（構造的に判定しやすいもの）

1. `claude/tooling.html` 早見表: 7 行の並び順が基準順序と一致するか、かつ各行のツール名セルが基準文字列と完全一致するか
2. `claude/tooling.html` 早見表: 全リンクが同一ディレクトリ系統（`design/` か `catalog/` のどちらか一方）を指しているか
3. `data/manifest.js` design カテゴリ: config 層エントリの並び順が基準順序の部分列として成立しているか
4. `data/manifest.js` registry カテゴリ: catalog を持つ 5 項目の並び順が基準順序の部分列として成立しているか
5. `index.html` 規模サマリカード: catalog を持つ 5 項目の並び順が基準順序の部分列として成立しているか
6. 全 HTML の `#/category/<id>` リンクが `data/manifest.js` のカテゴリ id として実在するか（リンク切れ検知）

### 機械チェックしない範囲（人間 / Claude のレビュー観点に委ねる）

表記ゆれの日本語⇔英語判定は文脈依存で誤検知しやすいため、以下は本 hook では機械判定せず、レビュー時のチェックリストとして残す。

- `data/manifest.js` の `title` / `description` 内の日本語表記（例: 設計ガイドページタイトルの単数形・複数形の揺れ）
- `index.html` の `metric-label` の厳密一致（`hook` のような短縮ラベルは文脈上許容されうる）
- 地の文でツール名を一般名詞として使っているか固有名詞として使っているかの判定

**レビュー時のチェックリスト**（`managing-agent-configs` の rules レビュー、または当規約に関わるファイルを編集した Claude 自身が確認する）:

- [ ] 新規 / 変更した行のツール名セルが英語表記（カタカナ化していない）か
- [ ] リンク先が意図したページファミリー（`design/` or `catalog/`）と一致しているか
- [ ] 並び順が本規約の基準順序に従っているか（機械チェックで検知されない箇所も含めて目視確認）

## 違反検知時の手順

### `[PORTAL-CONSISTENCY-WARN]` 受信

1. additionalContext に列挙された違反箇所（ファイル・不一致内容）を確認する
2. 並び順違反の場合: 基準順序（`CLAUDE.md → Rules → Skills → Subagents → Hooks → Output styles → Statusline`）に従って該当箇所を並べ替える
3. リンク先混在の場合: `claude/tooling.html` の早見表はページファミリー分類に従い `design/*.html` を指すよう統一する（早見表は「設計ガイドへの入口」であり、登録一覧への導線は別途 `registry` カテゴリ・カタログページ側で提供する）
4. 表記不一致の場合: config 層の名称を英語表記（CLAUDE.md, Rules, Skills, Subagents, Hooks, Output styles, Statusline）に統一する
5. 修正後、`node ~/.claude/rules/scoped/portal/page-conventions/check-portal-consistency.mjs` を実行し exit 0 になることを確認する

設計判断・経緯の記録は同ディレクトリの `design-notes.txt` を参照（非注入サイドカー）。

## 関連

- `~/agent-home/ai-management-portal/design/config-placement.html` — 基準順序の根拠となる 7 層判定フロー・冒頭一覧文
- `~/.claude/rules/scoped/portal/page-conventions/access-values.txt` — ローカル配信の起動コマンド・アクセスURL（ブックマーク）の定義（非注入サイドカー）
- `~/agent-home/.claude/rules/always/placement/directory-structure/rule.md` — agent-home 直下の許可ディレクトリ一覧（`ai-management-portal` を含む）
- `~/agent-home/skills/managing-agent-configs/SKILL.md` — hooks/rules 種別のレビュー時に `~/agent-home/ai-management-portal/design/hooks.html` 等を外部定義として参照する
- `~/.claude/rules/always/lint/text-dictionary/rule.md` / `~/.claude/rules/always/agent-config/review/rule.md` — 本ファイルが踏襲した記述形式（rule.md 本体 + 機械強制表 + 違反検知時手順 + 設計判断）の参照元
