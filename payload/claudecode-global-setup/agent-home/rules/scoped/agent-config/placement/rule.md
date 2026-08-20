---
paths:
  - "**/CLAUDE.md"
  - "**/.claude/**"
  - "**/SKILL.md"
  - "**/agent-home/skills/**"
---

# Claude 設定層配置判定規約（CONFIG-PLACEMENT）

「これはどこに書くか」を AI が判定するための判定フロー。
CLAUDE.md / Rules / Skills / Subagents / Hooks / Output styles / --append-system-prompt の 7 層を正しく使い分ける。

## 判定フロー（トップダウン・最初にヒットした層を使う）

```
Q1. ライフサイクルイベントで確実に発火させたいか？
    OR「毎回 X したら必ず Y せよ」「絶対にするな」を技術的に保証したいか？
    OR 特定キーワードを含む prompt のときだけ context 注入したいか？
    YES → Hook（+ permissions 設定）へ。プロンプト指示は長時間セッション・プロンプト
          インジェクションで破られうるため、決定論的強制が必要。
          「特定キーワードのとき注入」は UserPromptSubmit hook の additionalContext で実装

Q2. 全セッションで出力形式・ペルソナ全体をシステムレベルで制御したいか？
    YES → Output styles（システムプロンプトを置き換える。デフォルト役割が消えるため慎重に）

Q3. 単発起動時のみのトーン・出力形式の補足か？
    YES → --append-system-prompt フラグ（役割は置き換えず追加のみ。指示が多いほど
          従い度が下がる「逓減」あり。その起動時のみ有効）

Q4. 特定のトリガー（スラッシュコマンド・自動マッチ）でのみ要る手順 or 知識か？
    OR 30 行を超える手順・フロー・デプロイチェックリストか？
    YES → Skills（手順型 / 条件付き知識型 / 強制型）へ。
          起動時は name と description だけ読まれ、本体は呼び出し時に遅延ロード

Q5. 独立したコンテキストで完結させたい作業か？
    （中間結果でメイン会話を汚染したくない：ログ解析・依存関係監査・長大な調査など）
    YES → Subagents（独立コンテキストウィンドウで動作し、最終結果だけメインに返る）

Q6. 特定のパス・ファイル種別に限定した制約か？（例: src/api/** のみ、**/*.sh のみ）
    YES → Rules（paths 付き・lazy。該当ファイル Read 時にのみ高 attention で注入される）

Q7. 機械強制（hook / CI / linter）と対になる制約・規約か？
    OR hook が注入する [TAG] への対応手順か？
    OR カテゴリ別の長文ルールか？
    OR 全タスクで違反しうる制約か？
    YES → Rules（paths 無し・eager。CLAUDE.md と同列で常時注入される）

Q8. ユーザーが「CLAUDE.md に書け」と明示したか？
    AND 機械強制不可能か？（言語の選択・文体・対話原則など hook で弾けないもの）
    AND 全タスク共通の根本姿勢か？（トリガー駆動でない）
    AND Claude のデフォルトと異なるか？（デフォルトと同じなら dead code）
    すべて YES → CLAUDE.md（200 行以内を厳守）
    いずれか NO → どこにも書かない
```

## 各層の一言定義

| 層 | 向いている内容 | 向いていない内容 |
|---|---|---|
| **Hooks** | 「必ず Y せよ」「絶対するな」の決定論的強制、linter 自動実行、Slack 通知 | 柔らかいガイドライン、手順書 |
| **Output styles** | ペルソナ・出力形式の全セッション制御 | 一部タスクにだけ適用したい制約 |
| **--append-system-prompt** | 単発起動時のトーン・形式の補足 | 永続的な制約、複雑な手順 |
| **Skills** | 多段手順・フロー（デプロイ、リリース）、条件付き知識、slash コマンド化したい処理 | 常時効かせたい固定ルール |
| **Subagents** | 独立実行・中間結果を散らかしたくない作業 | 会話の文脈・承認が必要な作業 |
| **Rules (lazy)** | 特定パス・ファイル種別だけに効かせる制約（paths 付き） | 全タスク共通の制約 |
| **Rules (eager)** | 機械強制と pair の規約、[TAG] 対応手順、カテゴリ別長文ルール（paths 無し） | 一度しか使わない規約、手順書 |
| **CLAUDE.md** | 言語・文体・対話・コーディング原則（全タスク共通・機械強制不可・ユーザー明示指定のみ） | 機械強制できる禁止事項、トリガー駆動の手順 |

## 頻出アンチパターン（見つけたら即・移行先へ）

| アンチパターン | 正しい移行先 |
|---|---|
| CLAUDE.md に「毎回 X したら必ず Y せよ」 | Hook |
| CLAUDE.md に「絶対にするな」 | Hook + permissions.deny |
| CLAUDE.md に 30 行超の手順 | Skills |
| CLAUDE.md と rules 両方に同じ制約 | rules を定義元とし CLAUDE.md からはポインタのみ |
| 全タスク共通の制約を paths 付き rules に書く | paths 無し rules（eager）に変更 |
| `src/api/` だけに効くルールを eager rules に書く | paths 付き rules（lazy）に変更 |
| スラッシュコマンド化したい手順を rules に書く | Skills へ |
| 中間ステップが不要なシンプルな作業を Subagents に書く | Skills または直接実行 |

## 各層の定義ポインタ

詳細設計は各ガイドを参照:
- CLAUDE.md 設計: `~/agent-home/ai-management-portal/design/claude-md.html`
- Rules 設計: `~/agent-home/ai-management-portal/design/rules.html`
- Skills 設計: `~/agent-home/ai-management-portal/design/skill.html`
- Hooks 設計: `~/agent-home/ai-management-portal/design/hooks.html`
- Hooks 配置 4 象限: `~/.claude/rules/scoped/agent-config/hooks/rule.md`

## プロジェクト上書き

- 上書き可否: 一律適用
- 理由: 配置判定フローは設定アーキテクチャの定義であり、一律適用するため受け口を設けない

設計判断・経緯の記録は同ディレクトリの `design-notes.txt` を参照（非注入サイドカー）。
