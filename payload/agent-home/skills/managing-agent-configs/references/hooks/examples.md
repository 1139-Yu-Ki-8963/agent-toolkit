# 既存 13 フックの実例カタログ

`~/.claude/settings.json` に登録済みの 13 フックを 5 カテゴリに分類して掲載する。新規フックを書くときは、最も近い既存フックを下敷きにする。

各エントリは「ねらい / マッチ条件 / 出力 / timeout の理由」の 4 項目で示す。

---

## カテゴリ 1: 命名規則の注入（5 件）

すべて PreToolUse。systemMessage は `[フック発火] 命名規則: <対象>`、additionalContext は `[NAMING] <ルール>`。

### 1.1 git commit メッセージ

- ねらい: コミット作成前に `<type>: <subject>` フォーマットを Claude に再認識させる
- マッチ: `matcher: Bash` + `if: Bash(git commit:*)`
- 出力: type 一覧（feat/fix/docs/...）と subject ルール（日本語必須・25文字・末尾ピリオドなし）
- timeout: 5（printf のみ）

### 1.2 ブランチ作成

- ねらい: ブランチ作成前に `<prefix>/<slug>` フォーマットを注入
- マッチ: `Bash(git checkout:*)` `Bash(git branch:*)` `Bash(git switch:*)` の 3 件を別エントリで登録
- 出力: prefix 一覧（feature/fix/docs/...）と slug ルール（ケバブケース・50文字以内）
- timeout: 5

### 1.3 mkdir

- ねらい: ディレクトリ作成前に予約名（references/ scripts/ assets/ workflows/ shared_scripts/）と命名規則を注入
- マッチ: `if: Bash(mkdir:*)`
- timeout: 5

### 1.4 ファイル名（Write）

- ねらい: Write 前にケバブケース必須ルールと大文字固定例外（SKILL.md/README.md/CLAUDE.md/CHANGELOG.md）を注入
- マッチ: `matcher: Write`（`if` なしで全 Write に適用）
- timeout: 5

---

## カテゴリ 2: 操作のブロック（1 件）

PreToolUse。重大な操作を止めるか、別手段に誘導する。

### 2.1 図記述コードフェンス検出（exit 2 ブロック型）

- ねらい: Mermaid / PlantUML / Graphviz dot の記述を検出したら .drawio に強制誘導
- マッチ: `matcher: Write`
- 動作: `jq -r '.tool_input.content'` を抽出 → grep で 4 種のマーカー（3 種のコードフェンス + PlantUML 開始タグ）を検出 → ヒットすれば echo + exit 2
- 出力: stderr に `[DRAWIO BLOCK] <理由>`（JSON ではなく plain text）
- timeout: 5
- **唯一の exit 2 例**。多用しないこと

このフックの副作用として、本ドキュメント自身が「3 種のコードフェンスマーカー」を直接書こうとするとフックに自分自身がブロックされる。`references/output-schema.md` の最終行「自己参照ブロック」項目を参照。

---

## カテゴリ 3: プロンプトキーワード検知（3 件）

UserPromptSubmit。すべて `jq -r '.prompt' | grep -qiE '...' && printf '<json>' || true` の定型。

### 3.1 スキル作成キーワード

- ねらい: 「スキルを作る」系のリクエストで SKILL 作成ルールを先に Claude に注入
- マッチ: `(skill|スキル).*(作成|作る|追加|書く|実装|設計|新しい|creat|make|add|build|write|new)` の双方向 OR + `SKILL\.md`
- 出力: `[SKILL作成ルール] frontmatter に必須3項目: name(kebab-case), description(TRIGGER when/SKIPを含む複数行), invocation(nameと同値)。配置先: ~/agent-home/skills/<name>/SKILL.md。絶対パス禁止。`
- timeout: 5

### 3.2 図作成キーワード

- ねらい: 「フロー図」「シーケンス図」「diagram」等を検出したら drawio に誘導
- マッチ: 多数の日本語図名 + 英語の diagram/flowchart/mockup/wireframe + `\.drawio`
- 出力: `[DRAWIO] 図・ダイアグラムの作成は必ず ~/agent-home/skills/frontend-design/SKILL.md を参照し .drawio ファイルで生成すること。`
- timeout: 5

---

## カテゴリ 4: ファイル変更後の検査（2 件）

PostToolUse。`matcher: Write|Edit` で file_path を取り、ファイルを走査してから JSON を返す。

### 4.1 曖昧表現の自動修正トリガー

- ねらい: .md / .txt 保存後に曖昧表現（適宜 / 随時 / 必要に応じて / それ / これ ...）を検出 → サブエージェント起動を指示
- マッチ: 拡張子フィルタで md / txt のみ走査
- 動作: `grep -nE '<曖昧パターン>' "$file" | head -5` の結果を additionalContext に埋め込む
- 出力: `[AMBIGUITY-AUTO-FIX]` + ファイルパス + 検出行 + 「Agent ツール（subagent_type: general-purpose）を即座に起動し、clarifying-ambiguity スキルで修正すること（`~/.claude/rules/always/agent/subagent-selection/rule.md`）」
- timeout: 10（ファイル走査込み）
- 連動: `~/.claude/rules/always/agent/subagent-selection/rule.md` にサブエージェント起動ルールを明記

### 4.2 textlint 検査

- ねらい: .md 保存後に textlint を走らせ、エラーがあれば writing-quality スキルでの修正を指示
- マッチ: 拡張子フィルタで md のみ
- 動作: `node_modules/.bin/textlint --config .textlintrc.json "$file" --format compact`
- 出力: `[TEXTLINT]` + ファイルパス + textlint 結果 + 「~/agent-home/skills/writing-quality/SKILL.md のルールに従い修正すること（`~/agent-home/skills/writing-quality/SKILL.md`）」
- timeout: 15（外部ツール起動のため最長）
- 連動: `~/agent-home/skills/writing-quality/SKILL.md`

---

## カテゴリ 5: セッションロギング（2 件）

裏方ログ専用のフック。ユーザー / Claude への注入はせず、ファイルへの書き込みだけを行う。`additionalContext` を出さず exit 0 のみで終了するのが特徴（プレフィックス TAG も不要）。

### 5.1 スキル発動ログ

- ねらい: スキル呼び出し時に `~/agent-home/sessions/.skill-log/{session-id}.jsonl` に `{ts, skill}` を追記
- マッチ: `matcher: Skill`（PreToolUse）
- 動作: `tool_input.skill` を抽出 → 1 行 jsonl で append
- 再帰防止: 先頭で `[ -n "$CLAUDE_HOOK_SUMMARY_RUNNING" ] && exit 0`
- timeout: 5
- 出力: なし（exit 0 のみ）
- 連動: SessionEnd の要約フックがこの jsonl を `jq -s 'group_by(.skill)'` で集計する

### 5.2 セッション要約（SessionEnd）

- ねらい: `/clear` 時に headless `claude -p` でセッション要約 Markdown を `~/agent-home/sessions/YYYY-MM-DD/<session-id>.md` に書き出す
- マッチ: SessionEnd（matcher なし、command 内で `reason="clear"` を判定）
- 動作:
  1. `[ -n "$CLAUDE_HOOK_SUMMARY_RUNNING" ] && exit 0` で再帰即停止
  2. stdin 全体をデバッグログに追記
  3. reason フィルタ
  4. `~/agent-home/sessions/.skill-log/{session}.jsonl` を `jq -s 'group_by(.skill)'` で集計
  5. transcript jsonl から user/assistant メッセージのみ抽出 + `head -c 200000` で打ち切り
  6. プロンプトを `claude --no-session-persistence -p` に流す（環境変数 `CLAUDE_HOOK_SUMMARY_RUNNING=1` を子プロセスに渡す）
- 失敗時: stderr をエラーログに保存し、要約ファイルに `.error` サフィックス付きでコピー
- timeout: 180（claude -p の冷起動を考慮）
- 出力: なし（exit 0 のみ）
- 連動: `~/.claude/settings.json` の SessionEnd フック定義

`--bare` を使わない理由: keychain 認証と OAuth トークンを温存するため。再帰防止は ENV ガードで担保する。

---

## 共通パターンのチェックリスト

13 フックすべてを横断した結果、以下が **全件遵守** されている定型:

- [x] `systemMessage` に `[フック発火]` プレフィックス（11/13、裏方ログ系の 2 件は systemMessage も省略）
- [x] `additionalContext` に `[<TAG>]` プレフィックス（11/13、裏方ログ系の 2 件は additionalContext を出さない）
- [x] `timeout` を明示（13/13）
- [x] `hookSpecificOutput.hookEventName` を親イベント名と一致（11/13、出力する 11 件のみ対象）
- [x] キーワードマッチ系で `|| true` フォールバック（5/5、UserPromptSubmit と PostToolUse）
- [x] 動的内容を含む出力は `jq -n --arg` で組み立て（PostToolUse 2 件）
- [x] サブエージェント委譲は対応するルール・スキルと連動（AMBIGUITY-AUTO-FIX → always/agent/subagent-selection 規約、TEXTLINT → writing-quality SKILL.md、SESSION-SUMMARY → settings.json SessionEnd）
- [x] 再帰呼び出しを伴う子プロセス起動は ENV ガードで止める（カテゴリ 5 の 2 件）

新規フックを追加する場合、このチェックリストを満たすかを **必ず** 確認すること。
