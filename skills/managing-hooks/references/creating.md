# Hook 作成手順（creating）

`managing-hooks` の **create モード** が参照する手順書。`conventions.md` を前段で読んだ前提で、新規 hook 作成の流れと作成後チェックリストを定義する。

このファイルを読み終えたら、配置を決定し hook script を Write し、ADR・hooks.html・settings.json への登録を実施する。完了したら **自動的に review モード → test モード** へ連鎖する（ハブ SKILL.md の指示に従う）。

## 使用タイミング

以下の場面で create モードが発動:

| タイミング | 例 |
|----------|-----|
| 新規フック追加 | 「PreToolUse で git push 前に確認したい」 |
| 既存フックの編集 | 「textlint フックの timeout を伸ばしたい」 |
| `update-config` スキルが hooks を触る時 | 「`when claude stops show X` を設定したい」 |

`settings.json` への書き込み手順自体は `update-config` スキルが担当する。本モードは **フックの中身（hook script と JSON 出力）の書き方** を定義する。

## 推奨手順

### 0. 配置 4 象限を決める（最初に必ず実施）

`conventions.md` の「4. 配置 4 象限」を参照。新規 hook script の物理配置は ownership × scope で決定する。配置先を決めずに書き始めると `hooks-architecture-check.sh` が PreToolUse で block する。

### 1. JSON 出力スキーマを決める

`conventions.md` の「2. 標準出力 JSON フォーマット」を参照。`systemMessage` と `additionalContext` の使い分けを意識する。

### 2. TAG プレフィックスを決める

`conventions.md` の「3. プレフィックス規約」を参照。重複禁止 TAG リストに被らない名前を選び、追加時はリストにも追記する。

### 3. event 別パターンに従う

`conventions.md` の「5. イベント別パターン」と、より詳細な `event-recipes.md` を参照。PreToolUse / UserPromptSubmit / PostToolUse それぞれに定型がある。

### 4. timeout を明示する

`conventions.md` の「6. timeout の目安」を参照。秒単位で必ず指定する。

### 5. サブエージェント委譲が必要なら CLAUDE.md / rules も同時に書き加える

`conventions.md` の「7. サブエージェント委譲パターン」を参照。`additionalContext` で参照先スキル名を明示するだけでは不十分で、CLAUDE.md か rules 側で「`[<TAG>]` を見たらサブエージェントを起動」のルールも必要。

## 作成前チェックリスト

**配置（hooks-architecture-rules 準拠）**

- [ ] hook script の配置先が 4 象限のいずれかに該当するか（skill×global / skill×project / 独立規約×global / 独立規約×project）
- [ ] `(.claude)` 配下の flat `hooks/` バケットに置いていないか（禁止配置）
- [ ] 配置先の rule.md 内に `## 設計判断` セクションを記載したか（4 項目: 必要性 / 代替案不採用理由 / 保守責任者 / 廃棄条件）
- [ ] `hooks 一覧ドキュメント` の `HOOKS` 配列に新規 hook を登録したか

**書式**

- [ ] `timeout` を秒単位で明示したか
- [ ] `systemMessage` に `[フック発火]` プレフィックスを付けたか
- [ ] `additionalContext` に `[<TAG>]` プレフィックスを付けたか
- [ ] `hookSpecificOutput.hookEventName` が親イベント名と一致するか
- [ ] キーワードマッチ系では `|| true` でフォールバックしたか
- [ ] `<TAG>` が既存と重複していないか（`conventions.md` の重複禁止 TAG 参照）
- [ ] サブエージェント起動が必要なら CLAUDE.md / rules にも対応ルールを書いたか
- [ ] PreToolUse で `exit 2` ブロックを使う場合、本当に止める必要があるか確認したか
- [ ] PostToolUse で Node.js を使う場合、`exec 0</dev/null` を node 実行前に挿入したか
- [ ] PostToolUse で Node.js を使う場合、nvm の絶対パスを使っているか
- [ ] PostToolUse で exit 1 を返しうる外部ツールに `|| true` を付けたか
- [ ] 同じ matcher に複数フックを並べていないか（stdin exhaustion → 1 フックに統合）
- [ ] stdin 読み取りに `printf '%s' "$input" | jq -r '...' 2>/dev/null` を使っているか（`echo` 不可）
- [ ] `if` がコロンなし・スペース区切り（`Bash(tool *)` 形式）になっているか

## 作成後チェックリスト（必須）

- [ ] hook script を配置先に保存した
- [ ] 配置先の rule.md に `## 設計判断` セクションを記載した
- [ ] `hooks.html` の `HOOKS` 配列に登録した
- [ ] `settings.json` の対応イベントに command path を登録した
- [ ] **review モードへ自動連鎖**（managing-hooks ハブが制御）
- [ ] **test モードへ自動連鎖**（review 完了後）

## Gotchas

- 作成しただけで終わらせない: ハブが自動で review → test へ連鎖する。連鎖を止めるのはユーザー明示時のみ
- 配置を最初に決めない罠: 書き始めてから「これは skill 延長 / 独立規約 のどっち？」と悩むと、後から `git mv` + settings.json + hooks.html の 3 箇所更新が必要になる
- 設計判断を後回しにしない: `sh-adr-check.sh` が新規 `.sh` 作成時に `[ADR-REQUIRED]` を出すので、後回しにすると次ターンで警告される

## 参照資料

- 共通規約: `conventions.md`
- event 別の入力 / 出力レシピ: `event-recipes.md`
- settings.json 既存フックの実例カタログ: `examples.md`
- JSON 出力スキーマの完全リファレンス: `output-schema.md`
