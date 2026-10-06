---
name: consult-portal-update
description: 議事録・メール・資料情報からコンサル業務管理ポータルの data.js を更新し、検証まで行う。 TRIGGER when: 「ポータルを更新」「議事録を取り込んで」「ポータルに反映」「data.js を更新」と言われた時、会議・資料・課題の新情報を受け取った時。 SKIP: ポータルの画面・UI の変更（→通常の開発フロー + scoped/consult-portal/page-conventions 規約）、ポータルの閲覧のみの場合。
invocation: consult-portal-update
type: transform
allowed-tools: Read, Write, Edit, Glob, Bash, AskUserQuestion
---

# コンサル業務管理ポータルのデータ更新（consult-portal-update）

議事録・メール・チャット・資料リストなどの入力から `portal/data.js` の該当エントリを追加・更新し、機械検証まで完遂するスキル。ポータルの設計意図「AI が情報を集約し、人は確認と判断だけを行う」の集約側を担う。UI（`portal/index.html`）の変更は本スキルの対象外である。

## Phase 1: 入力と正本の確認

### Step 1-1: 取込素材の確認

ユーザーから渡された素材（議事録・メール・チャット・資料一覧・進捗報告）を確認する。素材に日付・出所が無い場合は AskUserQuestion で確認する。出典（いつ・どこから）の無い更新は禁止のため、不明なまま進めない。

**完了**: 素材の内容と出典（日付・出所）が確定していること

### Step 1-2: スキーマと現データの読み込み

`docs/13_業務管理ポータル設計/02_データモデル設計.md` と `portal/data.js` を Read する。各エンティティ（projects / issues / docs / people / meetings / decisions / access）のフィールド・状態値・参照形式を確認する。更新対象の data.js は実案件では `clients/<案件名>/portal/data.js`（複製）であり、リポジトリ直下の `portal/data.js` はモックデータ固定のデモのため対象にしない。

**完了**: スキーマ定義と現在のデータを把握していること

## Phase 2: 更新内容の確定

素材から更新対象エンティティを判別し、追加・更新するエントリを確定する。

- 会議の議事録 → meetings に追加。反映される課題があれば issues の tasks / notes / ms を更新
- 受領資料 → docs に追加（relIssue は該当課題の id。無関連は null）
- 決定事項 → decisions に追加（relIssueKey は該当課題の id）
- 人物情報 → people の追加・更新
- アクセス準備の進捗 → access の該当メンバーの items を更新
- 課題の進捗 → issues の tasks の done / due / owner を更新

確定ルール:

1. 事実（出典つき）と判断・仮説（記名）を区別する。notes のタイプタグ（f / j / r / q）を正しく付ける
2. すべての追加・更新エントリに出典を持たせる（notes の src、meetings の group と title 等）
3. スキーマ外フィールドを追加しない。状態値は定義済みの値のみ使う
4. 素材から判別できない値は捏造せず、AskUserQuestion で確認するか未設定のままにする
5. 迷ったら止まる。次の 3 つは推測で埋めずに AskUserQuestion で確認する
   - 対応する課題が issues に見当たらないタスク・決定（「最も近い課題」への便乗登録や課題の新規作成を勝手にしない）
   - 素材が組織主語（当社・先方）のみで、タスクの owner（個人名）を特定できない場合
   - タスクがどの中目標（ms）にも意味的に対応しない場合

**完了**: 追加・更新するエントリの実体（変更前後の対）が確定していること

## Phase 3: data.js への反映

確定したエントリを Edit で data.js に反映する。既存エントリの削除は、素材が明示的に削除を指示している場合に限る。

**完了**: 全エントリが data.js に反映されていること

## Phase 4: 検証

### Step 4-1: 機械検証

```bash
bash .claude/skills/consult-portal-update/scripts/verify-portal-data.sh portal/data.js
```

4 系統（構文・必須フィールド・状態値・参照整合）の全 PASS を確認する。FAIL があれば該当エントリを修正して再実行する。全 PASS になるまで Phase 3 と本 Step を繰り返す。

**完了**: verify-portal-data.sh が exit 0 で全系統 PASS していること

### Step 4-2: 表示確認

`portal/index.html` をブラウザで開き（または実描画検証ツールで）、更新したエントリが該当画面に表示されることを確認する。件数バッジ・期限強調・フィルタ母数の変化も確認する。

**完了**: 更新エントリの表示を確認したこと

## Phase 5: 記録

変更を git commit する（命名規約に従い日本語 prefix。例:【データ更新】8/29定例議事録をポータルへ反映）。版管理は git が担い、専用の履歴機構は持たない。

**完了**: commit が作成されていること

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 素材の出典とスキーマ・現データを確認済み |
| Phase 2 | 追加・更新エントリの実体が確定済み |
| Phase 3 | data.js に反映済み |
| Phase 4 | verify 全 PASS + 表示確認済み |
| Phase 5 | commit 作成済み |
| **Goal** | 素材の情報が出典付きで data.js に反映され、検証済みの状態で記録されている |

## 禁止事項

- `portal/index.html` の変更（UI 変更は通常の開発フローで行う。規約: `.claude/rules/scoped/consult-portal/page-conventions/rule.md`）
- 出典の無いエントリの追加・更新
- スキーマ外フィールドの追加・状態値の発明
- 素材に無い情報の捏造（進捗率・日付・人名を推測で埋めない）
- リポジトリ直下 `portal/data.js` への実案件データの書き込み（公開 payload に同期されるため。実案件は `clients/<案件名>/portal/` の複製で運用する）

## 関連

- `docs/13_業務管理ポータル設計/02_データモデル設計.md` — スキーマの正本
- `docs/13_業務管理ポータル設計/03_運用設計.md` — 運用フローの正本
- `.claude/rules/scoped/consult-portal/page-conventions/rule.md` — ページ規約
- `.claude/skills/consult-portal-update/scripts/verify-portal-data.sh` — 4 系統の機械検証

## 完了報告

変更エンティティと件数・verify の結果・commit ハッシュを 5 行以内で報告する。
