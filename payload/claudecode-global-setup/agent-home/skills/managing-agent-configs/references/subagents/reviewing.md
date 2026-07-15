# サブエージェント静的レビュー手順

## Phase 一覧

| Phase | 内容 |
|---|---|
| 1 | 対象発見 |
| 2 | 静的解析（観点 A〜F） |
| 3 | 実体検証 |
| 4 | レポート |
| 5 | 自動修正承認 |

重大度の付与基準: 機械検出可能で定義の実効性を直接壊すもの（frontmatter 不正・正本間ドリフト・正本の事実誤認）を CRITICAL、設計品質・読みやすさ・境界の明瞭さに関わるものを WARN、体裁を INFO とする。

## Phase 1: 対象発見

```bash
find ~/.claude/agents/ -name "*.md" -not -path "*/references/*" | sort
```

レビュー対象を特定し、一覧表示する。ユーザーが対象を指定済みなら省略。

## Phase 2: 静的解析

機械判定可能な観点（A1〜A9・B1・B3・C5・C7・D4・E5）の検出式は `check-items.md` に定義済み。先に check-items.md の式を一括実行してから、残りの観点を目視・突合で検査する。

### 観点 A: frontmatter / メタデータ（9 項目）

| ID | 観点 | 重大度 | 検証方法 |
|---|---|---|---|
| A1 | `name` が kebab-case かつ dir 名・file 名と一致 | CRITICAL | check-items.md A1 |
| A2 | `description` に TRIGGER when + SKIP が存在 | CRITICAL | check-items.md A2 |
| A3 | `description` 1 行目が 50 字以内 | WARN | check-items.md A3 |
| A4 | `model` が明示モデル ID。エイリアス（`opus` / `sonnet` / `haiku`）は禁止 | CRITICAL | check-items.md A4 |
| A5 | `tools` に禁止ツールが含まれていない | CRITICAL | conventions.md のツール選択基準と突合 |
| A6 | frontmatter のフィールドが許可白リスト内（conventions.md フィールド表の公式サポートフィールドのみ） | CRITICAL | check-items.md A6 |
| A7 | `tools` が明示されている（省略は親の全ツール継承 = 最小権限違反） | CRITICAL | check-items.md A7 |
| A8 | `model` の値が現行有効なモデル ID リスト（check-items.md 冒頭で管理）に存在 | CRITICAL | check-items.md A8 |
| A9 | `disallowedTools` と `tools` を併用していない（公式仕様: 併用不可・許可リスト優先） | CRITICAL | check-items.md A9 |

### 観点 B: 本文品質（4 項目）

| ID | 観点 | 重大度 | 検証方法 |
|---|---|---|---|
| B1 | 本文 100 行以内 | WARN | check-items.md B1 |
| B2 | 出力フォーマットが定義されている | WARN | `grep -i "出力"` |
| B3 | セクション数が 2〜4 | INFO | check-items.md B3 |
| B4 | 見出しが日本語統一 | INFO | 目視確認 |

### 観点 C: 単一責任・役割境界（7 項目）

| ID | 観点 | 重大度 | 検証方法 |
|---|---|---|---|
| C1 | 責務が 1 つに集中している | CRITICAL | description 1 行目の述語数 |
| C2 | 他 subagent との責務境界が明確 | WARN | SKIP の代替先と全 subagent の TRIGGER を突合 |
| C3 | 計画者が実装を兼ねていない / 調査者が修正を兼ねていない | CRITICAL | tools の Write/Edit 有無で判定 |
| C4 | 全エージェントの TRIGGER 同士のペアワイズ突合で、同一タスクが 2 体以上にマッチする交差が無い（交差がある場合は SKIP で相互に区別されている） | WARN | 全 TRIGGER 行を並べ、動詞・対象語の重なりを突合 |
| C5 | SKIP の代替先参照が双方向に成立している（A が「X は B へ」と書くとき、B の TRIGGER に X 相当の記述が実在する） | WARN | check-items.md C5 |
| C6 | 組み込みエージェント（Plan / Explore / claude-code-guide / general-purpose）と責務が重なる場合、棲み分け根拠（model 固定・ツール制限・出力形式統一等）が本文に明記されている | WARN | 本文の目視 + 組み込み一覧との突合 |
| C7 | 正本 4 点（conventions.md 役割体系・subagent-selection 規約 4 分類表・カタログ HTML・実体ファイル）の掲載エージェント集合が一致している | CRITICAL | check-items.md C7 |

### 観点 D: references 健全性（4 項目）

| ID | 観点 | 重大度 | 検証方法 |
|---|---|---|---|
| D1 | references に可変データが置かれていない | CRITICAL | ファイル内容の目視 |
| D2 | references が subagent 固有の知識である | WARN | 汎用パターンは skill/rules に属する |
| D3 | 本文から references への参照が適切 | INFO | 本文内の言及確認 |
| D4 | references/ 配下の md に `name:` frontmatter が無い（エージェント定義と誤認識されるリスク） | WARN | check-items.md D4 |

### 観点 E: 行動制約設計（5 項目）

正本は conventions.md「行動制約設計」節。テスト設計事例（Zenn 記事 be13a2395a5d2a）からの転用観点。

| ID | 観点 | 重大度 | 検証方法 |
|---|---|---|---|
| E1 | 「やらないこと」（禁止事項・越権防止の制約）が本文に明記されている | WARN | `grep -E "禁止|しない|やらない"` + 目視 |
| E2 | 出力フォーマットが項目構成・行数上限まで固定されている（B2 より一段厳格。「出力への言及がある」だけでは不足） | WARN | 出力フォーマット節の具体性を目視 |
| E3 | 未確認事項を推測で埋めず「不明」「証拠なし」と明示させる指示がある | WARN | `grep -E "不明|証拠|推測"` + 目視 |
| E4 | 報告に根拠（ファイルパス・実行コマンド・引用）を要求している | WARN | `grep -E "根拠|パス|コマンド"` + 目視 |
| E5 | 合否（PASS / FAIL）宣言の有無が分類と整合している（宣言できるのは判定系のみ） | WARN | check-items.md E5 |

### 観点 F: 正本の事実性（1 項目）

| ID | 観点 | 重大度 | 検証方法 |
|---|---|---|---|
| F1 | conventions.md 自体の記述が公式仕様（https://code.claude.com/docs/en/sub-agents）と矛盾しない（フィールド一覧・省略時挙動・予約語の有無） | CRITICAL | 公式ドキュメントとの突合（外部取得は researcher / claude-code-guide へ委任可） |

## Phase 3: 実体検証

- frontmatter の `tools` に列挙されたツールが実在するか
- `model` の値が有効か（check-items.md 冒頭の現行モデル ID リストと突合）
- references/ 内のファイルが存在し、空でないか
- frontmatter の `skills` を使用している場合、対象スキルが実在するか

## Phase 4: レポート

```
## レビュー結果: <subagent-name>

| 重大度 | 件数 |
|---|---|
| CRITICAL | N |
| WARN | N |
| INFO | N |

### 検出事項
- [CRITICAL] A1: name が dir 名と不一致 ...
- [WARN] B1: 本文 120 行（上限 100 行）...

### 健全性判定
- CRITICAL = 0 → PASS（test 連鎖可）
- CRITICAL > 0 → FAIL（修正必須）
```

## Phase 5: 自動修正承認

CRITICAL / WARN の検出事項に対して修正案を提示し、`AskUserQuestion` で承認を得てから適用する。

修正可能なもの:
- frontmatter のフィールド修正（name 不一致、tools 過剰・省略、白リスト外フィールド、disallowedTools 併用）
- 本文の行数削減（references への分離）
- 見出しの日本語統一
- 行動制約 5 要素の追記（E1〜E5）
- 正本 4 点間のドリフト追随（C7。掲載漏れの追加）

修正不可能なもの（設計判断が必要）:
- 責務の分割
- 役割パターンの変更
- references の構造変更
- 組み込みエージェントとの棲み分け方針（C6。ユーザー判断）
