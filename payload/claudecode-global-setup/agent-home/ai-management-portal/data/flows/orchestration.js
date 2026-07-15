export const ORCHESTRATION_FLOWS = [
  {
    id: "orchestrating-dev-flow",
    title: "orchestrating-dev-flow（統合実装フロー）",
    badge: "統合",
    summary: "全実装フローを統合する開発オーケストレーター。5 ルート × 11 Phase。プロジェクト固有設定ファイル（flow-values.yml）でコンテキストを注入し、全プロジェクト共通で使える。初回は creating-new-project スキルでセットアップ。",
    trigger: "「実装して」「バグ直して」「リファクタして」「ドキュメント編集」「インシデント対応」等の実装を伴う依頼。プロジェクト固有設定ファイルが存在するプロジェクトで自動発動。",
    relatedSkills: [
      "orchestrating-dev-flow",
      "creating-new-project",
      "module-hearing-requirements",
      "phase-6-tdd-cycle",
      "SKILL.md Step 1-4（構造分析）",
      "module-generating-explainer-yaml",
      "module-generating-explainer-html",
      "module-creating-screen-mock",
      "module-formatting-pr",
      "module-fixing-review-findings",
      "module-reviewing-pre-impl",
      "module-reviewing-impl-quality",
      "module-reviewing-pre-push",
      "module-running-e2e",
      "phase-11-main-sync-and-improve"
    ],
    steps: [
      // 概要: 通常のチャットとの対比
      { n: 1, section: "overview", featureTitle: "× 通常チャットでの実装依頼", detail: "「これ実装して」→ Claude が直接コードを書き始める → テストや PR の作成は都度こちらから指示 → 今どこまで進んだかは自分で把握 → 複数タスクの並行管理も自分で判断" },
      { n: 2, section: "overview", featureTitle: "✓ 実装フローでの実装依頼", detail: "「これ実装して」→ タスク規模を自動判定し最適なルートを選択 → 要件ヒアリング → 画面 UI モックで事前確認 → 承認後に実装開始 → テストを先に書いてから実装 → 仕様適合・実装品質・プッシュ前の 3 段階レビュー → PR 作成・マージまで自走" },

      // 概要: 3 つの特徴
      { n: 3, section: "overview", featureTitle: "特徴 1: 作り直しゼロ。実装前に画面 UI モックで合意する", detail: "要件を 1 問ずつ推奨回答付きで深掘りし、認識のずれを事前に解消。説明用 HTML と画面 UI モックを Artifact で公開し、スマートフォンからでも確認・承認できる。承認してから実装に入るため、完成後の「思っていたのと違う」がなくなる。",
        sampleImages: [
          { src: "assets/sample-screen-mock.png", alt: "画面 UI モックのサンプル", caption: "画面 UI モック: 実際の画面に近いビジュアルで事前確認できる" },
          { src: "assets/sample-explainer-html.png", alt: "説明用 HTML のサンプル", caption: "説明用 HTML: 仕様の概要ページを Artifact で公開" }
        ]
      },
      { n: 4, section: "overview", featureTitle: "特徴 2: 放置しても脱線しない。全 Step を事前登録して進捗を可視化", detail: "各 Phase の Step を事前に登録し、飛ばしや漏れを構造的にブロック。ターミナルのステータスラインに現在の進捗が常時表示される。タスクの規模に応じて 5 つのルートから最適なものを自動判定し、判定結果に異議があれば手動で変更できる。" },
      { n: 5, section: "overview", featureTitle: "特徴 3: main を壊さない。専用ブランチで分離し PR マージまで自走", detail: "最初に worktree（独立した作業ディレクトリ）を作成し、メインブランチや他のセッションと完全に分離する。コンフリクトが発生した場合はユーザーに確認して解消する。テストを先に書いてから実装し、仕様適合・実装品質・プッシュ前の 3 段階レビューで品質を検証。" },
      // ルート一覧 (section: "routes")
      { n: 6, section: "routes", routeId: "feature-with-full-planning", routeName: "機能実装（フル計画）", useCase: "新機能・大規模バグ修正", duration: "—", approval: "Phase 4 で 1 回", approvalYes: true, title: "【ルート】feature-with-full-planning", detail: "新機能・大規模バグ修正。全 11 Phase 通過。Phase 4 で仕様確認 + 画面 UI モック承認（唯一の停止点）。1 テスト→1 実装のテスト駆動（TDD）サイクルで実装。", skill: "orchestrating-dev-flow" },
      { n: 7, section: "routes", routeId: "feature-with-quick-delivery", routeName: "機能修正（クイック）", useCase: "小規模修正（ファイル≤2）", duration: "—", approval: "なし（全自走）", approvalYes: false, title: "【ルート】feature-with-quick-delivery", detail: "変更ファイル ≤ 2 / migration なし / UI なし / API 契約なし / DB スキーマなし。承認なし全自走。条件違反でフル計画に昇格。", skill: "orchestrating-dev-flow" },
      { n: 8, section: "routes", routeId: "config-with-review-and-verify", routeName: "設定・ドキュメント編集", useCase: "docs / skills / rules / hooks 変更", duration: "—", approval: "Phase D で 1 回（2 ファイル以上）", approvalYes: true, title: "【ルート】config-with-review-and-verify", detail: "アプリコードを変えない docs / skills / rules / hooks / agents 変更。変更対象が 2 ファイル以上の場合は Phase D で承認。1 ファイルのみの場合は承認スキップ。", skill: "orchestrating-dev-flow" },
      { n: 9, section: "routes", routeId: "refactor-with-safety-guarantee", routeName: "リファクタ（挙動保証）", useCase: "lint・deps・純粋リファクタ", duration: "—", approval: "Phase 5 で 1 回", approvalYes: true, title: "【ルート】refactor-with-safety-guarantee", detail: "挙動を変えない lint・deps・リファクタ。TDD なし、既存テスト全通過で保証。Phase 5 で承認 1 回。", skill: "orchestrating-dev-flow" },
      { n: 10, section: "routes", routeId: "incident-with-emergency-path", routeName: "本番障害復旧", useCase: "P0 障害の緊急復旧", duration: "最速", approval: "I4 で 1 回", approvalYes: true, title: "【ルート】incident-with-emergency-path（最速）", detail: "P0 障害の緊急復旧。Phase 1-2 のみ共通、以降 I1-I7 独自フロー。I4 で本番操作承認。I6 で復旧確認後に手続き省略可能。", skill: "orchestrating-dev-flow" },
      // Phase カード (section: "phases")
      { n: 11, section: "phases", phase: "1", phaseTitle: "調査 + ルート判定", color: "accent",
        detail: "起動前チェック → プロジェクト固有設定ファイル全セクション読み込み（ルート判定閾値 + プロジェクト基本情報 + 開発規約）→ 構造分析 → 条件分岐で 5 ルートに判定 → ユーザーに提案（異議があれば変更可能）。",
        flowSummary: "「調査・ルート確定」起動前チェック → コンテキスト読み込み → タスク内容確認 → 構造分析 → ルート判定 → ルート提案",
        completionCondition: "プロジェクト固有設定ファイルの全セクションが読み込まれていること。構造分析が完了していること（フル計画・リファクタルート）。ルートが 5 つのいずれか 1 つに確定し、ユーザーに提示されていること",
        routes: ["full", "quick", "config", "refactor", "incident"],
        skill: null, stop: false, stopDetail: null,
        phaseSteps: [
          {
            id: "1-1",
            title: "起動前チェック",
            detail: "起動前チェックスキルを呼び出し、プロジェクトの前提条件を検証する。プロジェクト固有設定ファイルが存在しない場合は初回セットアップスキルによるセットアップを案内する。go を返したら次 Step に進む。",
            completionCondition: "起動前チェックが go を返していること",
            timing: "Phase 開始直後",
            refs: [
              { type: "module", text: "module-preflight-check", desc: "プロジェクトの前提条件（flow-values.yml の存在・ツール可用性）を検証する起動前ゲート" },
              { type: "skill", text: "creating-new-project", desc: "初回セットアップ時に flow-values.yml / layers.yml / project-portal 等を自動生成する（references/scaffolding-flow-structure.md に統合済み）" },
              { type: "context", text: "プロジェクト固有設定ファイル（flow-values.yml）", desc: "プロジェクト固有の設定ファイル。ルート判定閾値・設計書パス・レビューゲート・E2E 設定等を定義する" }
            ],
            checks: [
              { type: "hook-notify", text: "check-main-agent-direct-work.sh（Read は通過）", desc: "メインエージェントの直接編集を防ぎ、サブエージェントへの委任を強制する", meta: "対応規約: subagent-delegation-rules | PreToolUse(Write|Edit|Bash)" }
            ]
          },
          {
            id: "1-2",
            title: "コンテキスト読み込み",
            detail: ".claude/rules/always/project-context/flow-values.yml の全セクションを Read する。プロジェクト基本情報・開発規約を取得し、指定されたドメイン用語辞書・デザイン規約・テスト規約・アーキテクチャ決定記録も Read する。起動前チェックは別スキル（別コンテキスト）のため内容は引き継がれない。",
            completionCondition: "プロジェクト固有設定ファイルの全セクションが読み込まれていること（ファイルが存在しない場合はデフォルト値で代替されていること）",
            timing: "Step 1-1 直後",
            refs: [
              { type: "context", text: "プロジェクト固有設定ファイル（flow-values.yml）（全セクション）", desc: "ルート判定閾値・プロジェクト基本情報（アーキテクチャ・用語集・技術スタック等）・開発規約（デザイン・テスト）" },
              { type: "context", text: "開発規約（デザイン・テスト）", desc: "デザイン規約・テスト規約などプロジェクトの開発ルール" },
            ],
            checks: [
              { type: "hook-notify", text: "check-main-agent-direct-work.sh（Read は通過）", desc: "メインエージェントの直接編集を防ぎ、サブエージェントへの委任を強制する", meta: "対応規約: subagent-delegation-rules | PreToolUse(Write|Edit|Bash)" }
            ]
          },
          {
            id: "1-3",
            title: "タスク内容の確認",
            detail: "ユーザーの依頼内容を確認し、挙動変更・アプリコード変更の有無・緊急度を評価する。",
            completionCondition: "タスクを 4 つの分類軸（挙動変更・アプリコード変更・緊急性・lint 系）で評価されていること",
            timing: "Step 1-2 直後",
            refs: [
              { type: "rule", text: "subagent-delegation-rules", desc: "メインエージェントの直接作業を制限し、サブエージェントへの委任を促進する" }
            ],
            checks: [
              { type: "hook-notify", text: "suggest-subagent.sh", desc: "ユーザー発話のキーワードからサブエージェントへの委任を提案する", meta: "対応規約: subagent-delegation-rules | UserPromptSubmit" }
            ]
          },
          {
            id: "1-4",
            title: "構造分析",
            detail: "構造分析スキルを呼び出し、浅いモジュール・Deletion Test 結果・推奨強度の候補リストをユーザーに提示する。prefactoring の要否をユーザーと合意する。incident / config / quick ルートでスキップ可能（Step 1-5 のルート判定前に判断）。",
            completionCondition: "スキルが返した候補リストがユーザーに提示され、prefactoring の要否が確定していること（スキップ可能なルートの場合はスキップ済みであること）",
            timing: "Step 1-3 直後",
            refs: [
              { type: "context", text: "構造分析手順（SKILL.md Step 1-4 にインライン化済み）", desc: "プロジェクトの構造を分析し、変更対象ファイルと影響範囲を特定する（浅いモジュール・Deletion Test・推奨強度の候補提示）" },
              { type: "rule", text: "subagent-delegation-rules", desc: "メインエージェントの直接作業を制限し、サブエージェントへの委任を促進する" },
            ],
            checks: [
              { type: "hook-block", text: "check-main-agent-direct-work.sh", desc: "メインエージェントの直接編集を防ぎ、サブエージェントへの委任を強制する", meta: "対応規約: subagent-delegation-rules | PreToolUse(Write|Edit|Bash)" }
            ]
          },
          {
            id: "1-5",
            title: "ルート判定",
            detail: "条件分岐で 1 ルートに確定する。P0→incident / コード変更なし→config / lint・リファクタのみ→refactor / 変更ファイル≤quick_max→quick / それ以外→full。Step 1-2 の classify セクションと Step 1-4 の構造分析結果を入力として使用する。",
            completionCondition: "条件分岐によりルートが 5 つのいずれか 1 つに確定していること",
            timing: "Step 1-4 直後",
            refs: [
              { type: "context", text: "ルート判定の閾値設定", desc: "ルート自動判定に使う閾値（quick_max_files / quick_excludes）" },
              { type: "context", text: "ルート判定スクリプト", desc: "ルート判定を実行するスクリプトのパス" }
            ],
            checks: [
              { type: "hook-notify", text: "check-main-agent-direct-work.sh（Read は通過）", desc: "メインエージェントの直接編集を防ぎ、サブエージェントへの委任を強制する", meta: "対応規約: subagent-delegation-rules | PreToolUse(Write|Edit|Bash)" }
            ]
          },
          {
            id: "1-6",
            title: "ルート提案",
            detail: "判定結果をユーザーに提案する。ユーザーの承認または次の指示があるまで待機する。",
            completionCondition: "ルートがユーザーに提示され、異議がなければ確定していること",
            timing: "Step 1-5 直後",
            refs: [
              { type: "rule", text: "no-premature-deferral-rules", desc: "作業の先送り（別セッション / 次回対応）を禁止する" },
            ],
            checks: [
              { type: "hook-block", text: "check-no-delegation-stop.sh（停止点）", desc: "最終応答にユーザーへの操作依頼が含まれていないか検査する", meta: "対応規約: response-guard-rules | Stop" },
              { type: "hook-block", text: "check-no-deferral-stop.sh（停止点）", desc: "最終応答に先送り表現が含まれていないか検査する", meta: "対応規約: response-guard-rules | Stop" }
            ]
          },
        ] },

      { n: 12, section: "phases", phase: "2", phaseTitle: "作業ブランチ準備", color: "accent",
        detail: "worktree 作成（全ルート必須）。並走 PR の競合チェック。",
        flowSummary: "「作業環境構築」並走 PR チェック → worktree 判定 → worktree 作成 → 環境確認 → 進捗初期化",
        completionCondition: "worktree 内で作業可能であること。feature ブランチが作成されていること。並走 PR の競合リスクが確認されていること。セッション跨ぎ進捗ファイルが初期化されていること",
        routes: ["full", "quick", "config", "refactor", "incident"],
        skill: "parallel-dev-worktree", stop: false, stopDetail: null,
        phaseSteps: [
          {
            id: "2-1",
            title: "並走 PR チェック",
            detail: "gh pr list --state open で同一領域の OPEN PR を確認し、競合リスクがあればユーザーに報告する。",
            completionCondition: "OPEN な PR が確認されていて、競合リスクがある場合はユーザーに報告されていること",
            timing: "Phase 開始直後",
            refs: [
              { type: "rule", text: "worktree-required-rules", desc: "メインツリーでの実装ファイル編集を禁止し、worktree 内での作業を必須化する" },
            ],
            checks: [
              { type: "hook-block", text: "check-worktree-required.sh", desc: "メインツリーでの実装ファイル編集を禁止し、worktree 内での作業を強制する", meta: "対応規約: worktree-required-rules | PreToolUse(Write|Edit)" }
            ]
          },
          {
            id: "2-2",
            title: "worktree 判定",
            detail: ".git がファイルなら worktree 内（Step 2-3 をスキップ）、ディレクトリならメインツリー（Step 2-3 必須）と判定する。",
            completionCondition: "現在の作業場所（worktree またはメインツリー）が確定し、次の Step の要否が判断されていること",
            timing: "Step 2-1 直後",
            refs: [
              { type: "rule", text: "worktree-required-rules", desc: "メインツリーでの実装ファイル編集を禁止し、worktree 内での作業を必須化する" }
            ],
            checks: [
              { type: "hook-block", text: "check-worktree-required.sh", desc: "メインツリーでの実装ファイル編集を禁止し、worktree 内での作業を強制する", meta: "対応規約: worktree-required-rules | PreToolUse(Write|Edit)" }
            ]
          },
          {
            id: "2-3",
            title: "worktree 作成（メインツリーからの場合は必須）",
            detail: "worktree 作成スキルを呼び出してブランチ + worktree を作成し、worktree のパスを記録する。以降の全 Phase は作成された worktree 内で実行する。",
            completionCondition: "worktree が作成され、以降の全 Phase の実行場所が worktree 内に確定していること",
            timing: "Step 2-2 でメインツリーと判定後",
            refs: [
              { type: "skill", text: "parallel-dev-worktree", desc: "git worktree で実装用の独立作業ディレクトリを作成する" },
              { type: "rule", text: "port-management-rules", desc: "開発サーバーのポート番号を計算式で一意に決定し、ランダムポートを禁止する" }
            ],
            checks: [
              { type: "hook-notify", text: "skill-log-recorder.sh（impl-session マーカー書き込み）", desc: "スキル発火ログを記録し、impl-session マーカーを書き込む", meta: "対応規約: session-infra-rules | PreToolUse(Skill)" }
            ]
          },
          {
            id: "2-4",
            title: "環境確認",
            detail: "git status でクリーンな状態を確認する。必要に応じて npm install / pip install 等を実行する。",
            completionCondition: "git status がクリーンで、依存パッケージがインストールされていること",
            timing: "worktree 確定後",
            refs: [
              { type: "rule", text: "pre-bash-dispatch-rules", desc: "git commit/branch/PR 作成時の命名規則・textlint・公開可否を検査する" },
              { type: "context", text: "ブランチ名提案スクリプト", desc: "ブランチ名を提案するスクリプトのパス" }
            ],
            checks: [
              { type: "hook-notify", text: "dispatch-pre-bash-checks.sh（ブランチ命名）", desc: "コミットメッセージの命名規則・textlint・公開可否を検査する", meta: "対応規約: pre-bash-dispatch-rules | PreToolUse(Bash)" }
            ]
          },
          {
            id: "2-5",
            title: "進捗ファイルの初期化",
            detail: "セッション跨ぎ進捗ファイルが存在すれば前セッションの進捗を復元し中断 Phase から再開する。なければ Phase 1 の結果を記録した新規進捗ファイルを作成する。Phase 2 完了後、定期ヘルスチェックループ（ScheduleWakeup 10 分間隔）を開始する。",
            completionCondition: "セッション跨ぎ進捗ファイルが存在し、前セッションの進捗が引き継がれているか新規初期化が完了していること",
            timing: "Step 2-4 直後",
            refs: [
            ],
            checks: [
              { type: "hook-block", text: "check-worktree-required.sh", desc: "メインツリーでの実装ファイル編集を禁止し、worktree 内での作業を強制する", meta: "対応規約: worktree-required-rules | PreToolUse(Write|Edit)" }
            ]
          },
        ] },

      { n: 13, section: "phases", phase: "3", phaseTitle: "要件ヒアリング", color: "gold",
        detail: "1 問ずつ推奨回答付きで深掘り。対象画面特定・UI 変更有無・レイアウト方針を確認。画面基本設計書があれば Read。",
        flowSummary: "「要件の明確化」ヒアリング実行 → 設計書確認 → 結果承認",
        completionCondition: "設計ツリーの全分岐について判断が確定し、ユーザーとの合意が得られていること",
        routes: ["full"],
        skill: "module-hearing-requirements", stop: false, stopDetail: null,
        phaseSteps: [
          {
            id: "3-1",
            title: "module-hearing-requirements の実行",
            detail: "要件ヒアリングスキルを呼び出し、1 問ずつ推奨回答付きで最大 15 問ヒアリングする。",
            completionCondition: "module-hearing-requirements スキルが起動し、設計ツリーの全分岐の洗い出しと質問が開始されていること",
            timing: "Phase 開始直後",
            refs: [
              { type: "module", text: "module-hearing-requirements", desc: "最大 15 問のヒアリングで要件を深掘りする" },
              { type: "context", text: "設計書ディレクトリ", desc: "プロジェクトの設計書ディレクトリのパス" },
            ],
            checks: [
              { type: "hook-block", text: "check-main-agent-direct-work.sh", desc: "メインエージェントの直接編集を防ぎ、サブエージェントへの委任を強制する", meta: "対応規約: subagent-delegation-rules | PreToolUse(Write|Edit|Bash)" }
            ]
          },
          {
            id: "3-2",
            title: "画面基本設計書の確認（UI 変更時）",
            detail: "UI 変更が確定したら画面基本設計書.md を Read して既存レイアウトを把握する。存在しない（新規画面）場合はヒアリング後に雛形を生成する。",
            completionCondition: "既存の画面基本設計書が Read されていること、または新規画面の雛形が生成されヒアリング結果が反映されていること",
            timing: "Step 3-1 で UI 変更が確定後",
            refs: [],
            checks: [
              { type: "hook-block", text: "check-main-agent-direct-work.sh", desc: "メインエージェントの直接編集を防ぎ、サブエージェントへの委任を強制する", meta: "対応規約: subagent-delegation-rules | PreToolUse(Write|Edit|Bash)" },
              { type: "hook-block", text: "check-worktree-required.sh", desc: "メインツリーでの実装ファイル編集を禁止し、worktree 内での作業を強制する", meta: "対応規約: worktree-required-rules | PreToolUse(Write|Edit)" }
            ]
          },
          {
            id: "3-3",
            title: "ヒアリング結果の確認",
            detail: "設計ツリーの全分岐が解消されたことを確認し、説明用 YAML（core.yaml）作成への入力としてまとめる。",
            completionCondition: "全分岐が解消され、Phase 4（仕様書作成）への入力がまとめられていること",
            timing: "Step 3-2 完了後",
            refs: [
              { type: "rule", text: "no-premature-deferral-rules", desc: "作業の先送り（別セッション / 次回対応）を禁止する" },
            ],
            checks: [
              { type: "hook-block", text: "check-no-deferral-stop.sh（停止点）", desc: "最終応答に先送り表現が含まれていないか検査する", meta: "対応規約: response-guard-rules | Stop" }
            ]
          },
        ] },

      { n: 14, section: "phases", phase: "4", phaseTitle: "仕様書 + 画面 UI モック作成", color: "gold",
        detail: "説明用 YAML 生成（ヒアリング結果から core.yaml + view.yaml）→ 説明用 HTML（yaml-to-html 生成）→ 画面 UI モック（DESIGN.md トークン注入）→ Artifact で公開 → 承認 + ビュー追加選択 → EnterPlanMode → ExitPlanMode。",
        flowSummary: "「仕様の確定」説明用 YAML 生成 → 説明用 HTML 生成 → 画面 UI モック生成 → 承認",
        completionCondition: "説明用 YAML（core.yaml）が生成されていること・説明用 HTML がユーザーに承認されていること・ExitPlanMode を通過していること・review gate を通過していること",
        routes: ["full"],
        skill: "module-generating-explainer-yaml", stop: true, stopDetail: "EnterPlanMode → ExitPlanMode（フルルート唯一の停止点）",
        // Step 4-2 はサブグループ見出しであり、4-3〜4-6 がその子 Step に相当する。
        // ポータル UI の進捗バー表示はフラット（7 Step）で統一しており、
        // Phase ファイル（phase-4-*.md）の見出し階層とは意図的に乖離している。
        phaseSteps: [
          {
            id: "4-1",
            title: "説明用 YAML 生成",
            detail: "説明用 YAML 生成スキルを呼び出し、ヒアリング結果をもとに説明用 YAML（core.yaml + view.yaml）を生成する。前処理指示として課題→解決策→ユーザーストーリー→判断→テスト→スコープ外の構造でコンテンツを整理する。core.yaml と view.yaml は worktree 内に保存する（使い捨て）。説明用 HTML と画面 UI モックは portal_dir/mocks/ にコミットされ永続化される。",
            completionCondition: "説明用 YAML（core.yaml + view.yaml）が生成されていること",
            timing: "Phase 開始直後",
            refs: [
              { type: "module", text: "module-generating-explainer-yaml", desc: "ヒアリング結果から説明用 YAML（core.yaml + view.yaml）を生成する" },
              { type: "context", text: "デザイン準拠チェックスクリプト", desc: "デザイン準拠チェックスクリプトのパス" },
            ],
            checks: [
              { type: "hook-block", text: "check-main-agent-direct-work.sh", desc: "メインエージェントの直接編集を防ぎ、サブエージェントへの委任を強制する", meta: "対応規約: subagent-delegation-rules | PreToolUse(Write|Edit|Bash)" }
            ]
          },
          {
            id: "4-1b",
            title: "画面設計ドキュメント作成（UI 変更時）",
            detail: "flow-values.yml の source.screen_docs を参照し、画面基本設計書.md と DESIGN.md を作成/更新する。画面基本設計書は画面基本設計テンプレートに従い骨格を作成。DESIGN.md は validate-design-md.sh で構造検証する。screen_docs が未設定の場合はスキップ。",
            completionCondition: "画面基本設計書.md が必須 4 セクションを含み、DESIGN.md が validate-design-md.sh を PASS していること（screen_docs 未設定時はスキップ済み）",
            timing: "Step 4-1 直後（UI 変更 or 新規画面時のみ）",
            refs: [
              { type: "context", text: "画面ドキュメント 3 点セット定義（source.screen_docs）", desc: "画面基本設計書.md / DESIGN.md / 結合テスト観点表.md の配置先と作成タイミング" },
              { type: "rule", text: "screen-docs-lifecycle", desc: "画面ドキュメントライフサイクル規約（3 点セット + Phase 別タイムライン）" },
            ],
            checks: [
              { type: "hook-block", text: "check-main-agent-direct-work.sh", desc: "メインエージェントの直接編集を防ぎ、サブエージェントへの委任を強制する", meta: "対応規約: subagent-delegation-rules | PreToolUse(Write|Edit|Bash)" }
            ]
          },
          {
            id: "4-2",
            title: "成果物生成",
            detail: "説明用 HTML と画面 UI モック（DESIGN.md トークン注入）の生成グループ（6-3〜6-6）。",
            completionCondition: "説明用 HTML と画面 UI モックの生成方針が確定していること",
            timing: "Step 4-1 直後",
            refs: [],
            checks: [
              { type: "hook-block", text: "dispatch-pre-bash-checks.sh（docs textlint）", desc: "コミットメッセージの命名規則を検査し、docs の追加行に textlint を実行する。公開可否もチェックする", meta: "対応規約: pre-bash-dispatch-rules | PreToolUse(Bash)" }
            ]
          },
          {
            id: "4-3",
            title: "説明用 HTML 生成（全ケース）",
            detail: "説明用 HTML 生成スキルを呼び出す（入力: Step 4-1 で生成した core.yaml + view.yaml、出力: 説明用 HTML バンドル）。portal_dir/mocks/issue-N-spec/ に生成する。",
            completionCondition: "説明用 HTML バンドルが portal_dir/mocks/issue-N-spec/ に生成されていること",
            timing: "Step 4-1 直後",
            refs: [
              { type: "module", text: "module-generating-explainer-html", desc: "core.yaml + view.yaml から説明用 HTML ページを生成する" }
            ],
            checks: [
              { type: "hook-block", text: "check-main-agent-direct-work.sh", desc: "メインエージェントの直接編集を防ぎ、サブエージェントへの委任を強制する", meta: "対応規約: subagent-delegation-rules | PreToolUse(Write|Edit|Bash)" }
            ]
          },
          {
            id: "4-4",
            title: "画面 UI モック生成（UI 変更がある場合のみ）",
            detail: "既存コンポーネント（.tsx / .vue）と CSS を Read し、画面設計書（7 項目）と DESIGN.md トークンを入力として Before/After の画面 UI モックを生成する。",
            completionCondition: "画面 UI モックが portal_dir/mocks/issue-N-screen.html に生成されていること（UI 変更がある場合のみ）",
            timing: "Step 4-3 直後（UI 変更時のみ）",
            refs: [
              { type: "module", text: "module-creating-screen-mock", desc: "画面 UI モックを HTML で生成する" },
              { type: "rule", text: "file-guard-rules", desc: "ファイルの配置先とマーカーの書き出し先を規制する" }
            ],
            checks: [
              { type: "hook-block", text: "check-playwright-filename.sh", desc: "Playwright スクリーンショットのファイル配置先が正しいか検査する", meta: "対応規約: file-guard-rules | PreToolUse(screenshot)" }
            ]
          },
          {
            id: "4-5",
            title: "ポータルサーバー起動確認",
            detail: "ポータルサーバーが起動しているか確認し、未起動なら起動する。ポートはポート管理規約に従い worktree スロットから動的に算出する。",
            completionCondition: "ポータルサーバーが起動していて Artifact 公開が可能であること",
            timing: "モック生成後",
            refs: [
              { type: "rule", text: "port-management-rules", desc: "開発サーバーのポート番号を計算式で一意に決定し、ランダムポートを禁止する" }
            ],
            checks: [
              { type: "hook-notify", text: "dispatch-pre-bash-checks.sh（ポート確認）", desc: "コミットメッセージの命名規則・textlint・公開可否を検査する", meta: "対応規約: pre-bash-dispatch-rules | PreToolUse(Bash)" }
            ]
          },
          {
            id: "4-6",
            title: "画面 UI モック提示・承認",
            detail: "生成した成果物を Artifact として公開し、AskUserQuestion で承認判定とビュー追加選択を 2 問同時に確認する。承認まで最大 5 回ループ可能。",
            completionCondition: "説明用 HTML バンドルと画面 UI モック（UI 変更時）が生成されていて、ユーザーが「承認」+「追加不要」を選択していること",
            timing: "Step 4-5 直後",
            refs: [],
            checks: [
              { type: "hook-notify", text: "check-main-agent-direct-work.sh（Read は通過）", desc: "メインエージェントの直接編集を防ぎ、サブエージェントへの委任を強制する", meta: "対応規約: subagent-delegation-rules | PreToolUse(Write|Edit|Bash)" }
            ]
          },
          {
            id: "4-7",
            title: "仕様承認 + 後処理",
            detail: "EnterPlanMode → ExitPlanMode でフルルート唯一の停止点。承認後、release-notes.js への URL 追記と pre_impl review gate を実行する。",
            completionCondition: "ExitPlanMode によるユーザー承認が得られ、review gate を通過していること（設定されている場合）",
            timing: "Step 4-6 承認後",
            refs: [
              { type: "module", text: "module-reviewing-pre-impl", desc: "仕様適合レビューを実行する" },
              { type: "context", text: "仕様適合レビューゲート", desc: "仕様適合レビューゲートのスキル名" },
              { type: "rule", text: "no-premature-deferral-rules", desc: "作業の先送り（別セッション / 次回対応）を禁止する" },
            ],
            checks: [
              { type: "hook-guard", text: "EnterPlanMode → ExitPlanMode（計画モード強制）", desc: "計画モードで実装ファイルの編集をブロックし、承認フローを強制する" },
              { type: "hook-block", text: "check-review-gate.sh（仕様承認 PASS 必須）", desc: "レビューゲートの PASS マーカーが存在するか検査する。レビュースキルが内部でコードレビューを実行する", meta: "対応規約: orchestrating-dev-flow | PreToolUse(Bash)" }
            ]
          },
        ] },

      { n: 15, section: "phases", phase: "5", phaseTitle: "実装・テスト計画", color: "gold",
        detail: "振る舞い一覧を優先順位付きで策定。TDD（テスト駆動開発）のテスト対象を確定。リファクタルートではここが停止点。",
        flowSummary: "「実装方針の確定」実装手順策定 → テスト計画 → 計画承認",
        completionCondition: "実装手順とテスト計画が策定されていること。リファクタルートは ExitPlanMode を通過していること",
        routes: ["full", "quick", "refactor"],
        skill: null, stop: true, stopDetail: "リファクタルートのみ EnterPlanMode → ExitPlanMode",
        phaseSteps: [
          {
            id: "5-1",
            title: "実装手順の策定",
            detail: "Phase 4 の説明用 YAML（core.yaml）（フルルート）またはタスク内容（リファクタ・クイック）に基づき、実装手順を箇条書きで策定する。クイックルートは変更対象ファイル列挙・変更内容 1 行要約・テスト方針 1 行要約に簡略化する。",
            completionCondition: "実装手順が箇条書きで策定されていること（クイックルートは変更対象・変更内容・テスト方針の 1 行要約で代替されていること）",
            timing: "Phase 開始直後",
            refs: [
              { type: "rule", text: "subagent-delegation-rules", desc: "メインエージェントの直接作業を制限し、サブエージェントへの委任を促進する" },
            ],
            checks: [
              { type: "hook-block", text: "check-main-agent-direct-work.sh", desc: "メインエージェントの直接編集を防ぎ、サブエージェントへの委任を強制する", meta: "対応規約: subagent-delegation-rules | PreToolUse(Write|Edit|Bash)" }
            ]
          },
          {
            id: "5-2",
            title: "テスト計画（機能実装（フル計画）・リファクタ（挙動保証））",
            detail: "TDD（テスト駆動開発）で書くテストの振る舞い一覧を優先順位付きでリストアップし、パブリックインターフェース経由のテストを設計する。重要パスと複雑ロジックに集中する。",
            completionCondition: "TDD で書くテストの振る舞い一覧が優先順位付きで策定されていること",
            timing: "Step 5-1 直後",
            refs: [],
            checks: [
              { type: "hook-block", text: "check-main-agent-direct-work.sh", desc: "メインエージェントの直接編集を防ぎ、サブエージェントへの委任を強制する", meta: "対応規約: subagent-delegation-rules | PreToolUse(Write|Edit|Bash)" },
              { type: "hook-block", text: "check-worktree-required.sh", desc: "メインツリーでの実装ファイル編集を禁止し、worktree 内での作業を強制する", meta: "対応規約: worktree-required-rules | PreToolUse(Write|Edit)" }
            ]
          },
          {
            id: "5-2b",
            title: "結合テスト観点表の作成/更新（UI 変更時）",
            detail: "flow-values.yml の source.screen_docs を参照し、結合テスト観点表テンプレートに従って結合テスト観点表.md を作成/更新する。テスト計画（Step 5-2）から観点を導出し IT-xxx ID 付きで記載する。V 字対応マトリクスに画面基本設計書のパスを記載する。screen_docs 未設定または設計書 30 行未満の場合はスキップ。",
            completionCondition: "結合テスト観点表.md が必須 6 セクションを含み、観点が 1 件以上記載されていること（スキップ条件に該当する場合はスキップ済み）",
            timing: "Step 5-2 直後（UI 変更時のみ）",
            refs: [
              { type: "context", text: "画面ドキュメント 3 点セット定義（source.screen_docs）", desc: "結合テスト観点表の配置先定義" },
              { type: "rule", text: "integration-test-viewpoint-template", desc: "結合テスト観点表テンプレート（必須 6 セクション）" },
              { type: "rule", text: "screen-docs-lifecycle", desc: "画面ドキュメントライフサイクル規約" },
            ],
            checks: [
              { type: "hook-block", text: "check-worktree-required.sh", desc: "メインツリーでの実装ファイル編集を禁止し、worktree 内での作業を強制する", meta: "対応規約: worktree-required-rules | PreToolUse(Write|Edit)" }
            ]
          },
          {
            id: "5-3",
            title: "計画承認（メンテルート）",
            detail: "リファクタルートの唯一の停止点。EnterPlanMode で計画を提示し、ExitPlanMode でユーザー承認を得る。機能実装（フル計画）ルートは Phase 4 で承認済みなのでスキップ。クイックルートは停止点なし。",
            completionCondition: "リファクタ（挙動保証）ルートの場合は ExitPlanMode によるユーザー承認が得られていること（他ルートはスキップ済みであること）",
            timing: "Step 5-2 直後（リファクタルートのみ）",
            refs: [
              { type: "rule", text: "no-premature-deferral-rules", desc: "作業の先送り（別セッション / 次回対応）を禁止する" },
            ],
            checks: [
              { type: "hook-guard", text: "EnterPlanMode → ExitPlanMode（リファクタルートのみ）", desc: "計画モードで実装ファイルの編集をブロックし、承認フローを強制する" }
            ]
          },
        ] },

      { n: 16, section: "phases", phase: "6", phaseTitle: "テスト駆動実装（TDD）", color: "accent",
        detail: "1 テスト → 1 実装の垂直ループ。水平スライス禁止。UI 変更時は E2E 先行作成。クイックルートからの昇格判定あり。",
        flowSummary: "「コード実装」E2E 先行作成 → テスト駆動実装（TDD）→ 品質レビュー → ルート再評価",
        completionCondition: "全テストが通過していること。review gate を通過していること。クイックルートの再評価で昇格していないこと",
        routes: ["full", "quick"],
        skill: null, stop: false, stopDetail: null,
        phaseSteps: [
          {
            id: "6-1",
            title: "E2E 先行作成（UI 変更時のみ）",
            detail: "UI 変更を伴う場合、TDD 開始前に E2E spec ファイルを作成する。結合テスト観点表（source.screen_docs 配下）が存在する場合、各観点 ID（IT-xxx）を E2E spec の describe/it ブロックにコメントとして記載しトレーサビリティを確保する。プロジェクト hook で spec 未作成のまま実装への進行がブロックされる場合がある。",
            completionCondition: "E2E テスト spec ファイルが作成されていること（UI 変更がある場合のみ。なければスキップ済みであること）",
            timing: "Phase 開始直後（UI 変更時のみ）",
            refs: [
              { type: "module", text: "module-running-e2e", desc: "E2E テストを実行する" },
              { type: "context", text: "E2E テストゲート", desc: "E2E テストゲートのスキル名" },
              { type: "context", text: "E2E テスト必須判定スクリプト", desc: "E2E テスト必須判定スクリプトのパス" },
              { type: "context", text: "E2E テスト設定（URL・コマンド・対象ページ）", desc: "E2E テストの URL・コマンド・対象ページの設定" },
            ],
            checks: [
              { type: "hook-block", text: "E2E 先行チェック hook（プロジェクト側設定時）", desc: "UI 変更時に Playwright による E2E テストの spec ファイルを事前に作成させる" }
            ]
          },
          {
            id: "6-2",
            title: "TDD サイクルの実行（phase-6-tdd-cycle.md にインライン化済み）",
            detail: "references/phase-6-tdd-cycle.md の手順に従い、Phase 5 のテスト計画をもとに実装する。垂直スライス（1 テスト→1 実装）を徹底し、水平スライスは禁止。",
            completionCondition: "全振る舞いについて RED→GREEN が達成し、全テストが通過していること",
            timing: "Step 6-1 直後",
            refs: [
              { type: "context", text: "phase-6-tdd-cycle.md", desc: "テストを先に書いてから実装する TDD サイクルの手順（フロー本体にインライン化済み）" },
              { type: "rule", text: "subagent-delegation-rules", desc: "メインエージェントの直接作業を制限し、サブエージェントへの委任を促進する" },
              { type: "rule", text: "worktree-required-rules", desc: "メインツリーでの実装ファイル編集を禁止し、worktree 内での作業を必須化する" },
              { type: "rule", text: "file-guard-rules", desc: "ファイルの配置先とマーカーの書き出し先を規制する" }
            ],
            checks: [
              { type: "hook-block", text: "check-main-agent-direct-work.sh", desc: "メインエージェントの直接編集を防ぎ、サブエージェントへの委任を強制する", meta: "対応規約: subagent-delegation-rules | PreToolUse(Write|Edit|Bash)" },
              { type: "hook-block", text: "check-worktree-required.sh", desc: "メインツリーでの実装ファイル編集を禁止し、worktree 内での作業を強制する", meta: "対応規約: worktree-required-rules | PreToolUse(Write|Edit)" }
            ]
          },
          {
            id: "6-3",
            title: "review gate 呼び出し",
            detail: "実装品質レビューゲートが設定されていれば各サイクル完了後に呼び出す。",
            completionCondition: "実装品質レビューゲートを通過していること（設定されている場合）",
            timing: "各サイクル完了後",
            refs: [
              { type: "module", text: "module-reviewing-impl-quality", desc: "実装品質レビューを実行する" },
              { type: "context", text: "実装品質レビューゲート", desc: "実装品質レビューゲートのスキル名" },
              { type: "rule", text: "subagent-delegation-rules", desc: "メインエージェントの直接作業を制限し、サブエージェントへの委任を促進する" }
            ],
            checks: [
              { type: "hook-block", text: "check-review-gate.sh（実装品質 PASS 必須）", desc: "レビューゲートの PASS マーカーが存在するか検査する。レビュースキルが内部でコードレビューを実行する", meta: "対応規約: orchestrating-dev-flow | PreToolUse(Bash)" }
            ]
          },
          {
            id: "6-4",
            title: "ルート再評価（クイックルートのみ）",
            detail: "commit 直前に classify 条件を再評価する。条件違反（migration 追加・UI 変更等）を検出したらフルルートに昇格し Phase 1 から再開する。",
            completionCondition: "classify 条件の再評価が完了し、昇格不要が確認されていること（昇格した場合は Phase 1 から再開されていること）",
            timing: "commit 直前（クイックルートのみ）",
            refs: [
            ],
            checks: [
              { type: "hook-block", text: "dispatch-pre-bash-checks.sh（commit 時）", desc: "コミットメッセージの命名規則を検査し、docs の追加行に textlint を実行する。公開可否もチェックする", meta: "対応規約: pre-bash-dispatch-rules | PreToolUse(Bash)" }
            ]
          },
        ] },

      { n: 17, section: "phases", phase: "7", phaseTitle: "完了チェック", color: "accent",
        detail: "lint エラー 0 件・型エラー 0 件・テスト全通過。失敗時は修正ループ（最大 5 回）。",
        flowSummary: "「品質確認」テスト・lint 通過 → ドキュメント更新 → E2E 確認",
        completionCondition: "lint エラーが 0 件であること・型エラーが 0 件であること・テストが全通過していること",
        routes: ["full", "quick", "config", "refactor"],
        skill: null, stop: false, stopDetail: null,
        phaseSteps: [
          {
            id: "7-1",
            title: "lint 実行",
            detail: "プロジェクトの lint コマンドを実行し、エラーをゼロにする。",
            completionCondition: "lint エラーが 0 件であること",
            timing: "Phase 開始直後",
            refs: [
              { type: "context", text: "PR 必須セクション", desc: "PR に必須のセクション一覧" },
              { type: "rule", text: "pre-bash-dispatch-rules", desc: "git commit/branch/PR 作成時の命名規則・textlint・公開可否を検査する" },
            ],
            checks: [
              { type: "hook-block", text: "pre-bash-dispatch（git commit 時）", desc: "コミットメッセージの命名規則を検査し、docs の追加行に textlint を実行する。公開可否もチェックする", meta: "対応規約: pre-bash-dispatch-rules | PreToolUse(Bash)" }
            ]
          },
          {
            id: "7-2",
            title: "型チェック",
            detail: "TypeScript プロジェクトの場合、tsc --noEmit で型エラーをゼロにする。",
            completionCondition: "型エラーが 0 件であること（TypeScript プロジェクトの場合のみ）",
            timing: "Step 7-1 直後",
            refs: [],
            checks: [
              { type: "hook-block", text: "dispatch-pre-bash-checks.sh（docs textlint）", desc: "コミットメッセージの命名規則を検査し、docs の追加行に textlint を実行する。公開可否もチェックする", meta: "対応規約: pre-bash-dispatch-rules | PreToolUse(Bash)" }
            ]
          },
          {
            id: "7-3",
            title: "テスト全実行",
            detail: "全テストスイートを実行し通過を確認する。ドキュメントルートは HTML 構文チェック・リンク切れ検出に置換する。",
            completionCondition: "全テストスイートが通過していること（ドキュメントルートは HTML 構文チェックとリンク切れ検出を通過していること）",
            timing: "Step 7-2 直後",
            refs: [
            ],
            checks: [
              { type: "hook-block", text: "dispatch-pre-bash-checks.sh", desc: "コミットメッセージの命名規則を検査し、docs の追加行に textlint を実行する。公開可否もチェックする", meta: "対応規約: pre-bash-dispatch-rules | PreToolUse(Bash)" }
            ]
          },
        ] },

      { n: 18, section: "phases", phase: "8", phaseTitle: "プッシュ前最終確認", color: "accent",
        detail: "diff に意図しない変更がないか確認。review gate（pre-push）を通過。push 実行。",
        flowSummary: "「最終確認」diff 確認 → レビューゲート → push 実行",
        completionCondition: "diff が確認されていること・review gate を通過していること・push が成功していること",
        routes: ["full", "quick", "config", "refactor"],
        skill: "module-reviewing-pre-push", stop: false, stopDetail: null,
        phaseSteps: [
          {
            id: "8-1",
            title: "diff 確認",
            detail: "staged 全体の diff を確認し、意図しない変更が含まれていないことを確認する。",
            completionCondition: "staged 全体の diff に意図しない変更が含まれていないことが確認されていること",
            timing: "Phase 開始直後",
            refs: [
              { type: "context", text: "変更注意パス", desc: "変更時に注意が必要なファイルパターン" },
            ],
            checks: [
              { type: "hook-notify", text: "check-flow-progress.sh（進捗追跡チェック）", desc: "フロー進捗ファイルの存在を検査する", meta: "対応規約: orchestrating-dev-flow | PreToolUse(Bash)" }
            ]
          },
          {
            id: "8-2",
            title: "review gate 呼び出し",
            detail: "プッシュ前レビューゲートが設定されていれば Skill ツールで呼び出す。",
            completionCondition: "プッシュ前レビューゲートを通過していること（設定されている場合）",
            timing: "Step 8-1 直後",
            refs: [
              { type: "module", text: "module-reviewing-pre-push", desc: "プッシュ前の最終レビューを実行する" },
              { type: "context", text: "プッシュ前レビューゲート", desc: "プッシュ前レビューゲートのスキル名" },
              { type: "rule", text: "subagent-delegation-rules", desc: "メインエージェントの直接作業を制限し、サブエージェントへの委任を促進する" }
            ],
            checks: [
              { type: "hook-block", text: "check-review-gate.sh（プッシュ前 PASS 必須）", desc: "レビューゲートの PASS マーカーが存在するか検査する。レビュースキルが内部でコードレビューを実行する", meta: "対応規約: orchestrating-dev-flow | PreToolUse(Bash)" }
            ]
          },
          {
            id: "8-3",
            title: "push 実行",
            detail: "git push -u origin <branch-name> で push する。",
            completionCondition: "リモートへの push が成功していること",
            timing: "Step 8-2 直後",
            refs: [
              { type: "rule", text: "pre-bash-dispatch-rules", desc: "git commit/branch/PR 作成時の命名規則・textlint・公開可否を検査する" },
            ],
            checks: [
              { type: "hook-block", text: "pre-bash-dispatch（コミット時）", desc: "コミットメッセージの命名規則を検査し、docs の追加行に textlint を実行する。公開可否もチェックする", meta: "対応規約: pre-bash-dispatch-rules | PreToolUse(Bash)" }
            ]
          },
        ] },

      { n: 19, section: "phases", phase: "9", phaseTitle: "PR 作成・マージ", color: "accent",
        detail: "PR フォーマット整形 → CI 通過確認 → マージ。",
        flowSummary: "「PR 完了」PR 作成 → CI 確認 → マージ",
        completionCondition: "PR が作成されていること・CI が通過していること・マージが完了していること",
        routes: ["full", "quick", "config", "refactor", "incident"],
        skill: "module-formatting-pr", stop: false, stopDetail: null,
        phaseSteps: [
          {
            id: "9-1",
            title: "PR 作成",
            detail: "gh pr create で PR を作成する。タイトルとボディは命名規約（rules: always/naming/commit-branch）に従う。",
            completionCondition: "PR が命名規約に従い作成されていること",
            timing: "Phase 開始直後",
            refs: [
              { type: "module", text: "module-formatting-pr", desc: "PR のタイトル・本文を整形して作成する" },
              { type: "context", text: "PR テンプレート", desc: "PR テンプレートファイルのパス" },
              { type: "rule", text: "response-guard-rules", desc: "ユーザーへの操作依頼と先送り表現を禁止する" },
            ],
            checks: [
              { type: "hook-block", text: "pre-bash-dispatch（PR 本文）", desc: "コミットメッセージの命名規則を検査し、docs の追加行に textlint を実行する。公開可否もチェックする", meta: "対応規約: pre-bash-dispatch-rules | PreToolUse(Bash)" },
              { type: "hook-block", text: "check-no-deferral-pre-bash.sh", desc: "gh pr/issue create の body に先送り表現がないか検査する", meta: "対応規約: response-guard-rules | PreToolUse(Bash)" },
              { type: "hook-notify", text: "dispatch-pre-bash-checks.sh", desc: "コミットメッセージの命名規則を検査し、docs の追加行に textlint を実行する。公開可否もチェックする", meta: "対応規約: pre-bash-dispatch-rules | PreToolUse(Bash)" }
            ]
          },
          {
            id: "9-2",
            title: "CI 確認",
            detail: "CI が通過するまで待機する。失敗した場合は修正して再 push する。",
            completionCondition: "CI が通過していること",
            timing: "Step 9-1 直後",
            refs: [],
            checks: [
              { type: "hook-block", text: "dispatch-pre-bash-checks.sh（commit 時）", desc: "コミットメッセージの命名規則を検査し、docs の追加行に textlint を実行する。公開可否もチェックする", meta: "対応規約: pre-bash-dispatch-rules | PreToolUse(Bash)" }
            ]
          },
          {
            id: "9-3",
            title: "マージ",
            detail: "CI 通過後、gh pr merge でマージする。",
            completionCondition: "マージが完了していること",
            timing: "Step 9-2 直後",
            refs: [],
            checks: [
              { type: "hook-block", text: "dispatch-pre-bash-checks.sh（docs textlint）", desc: "コミットメッセージの命名規則を検査し、docs の追加行に textlint を実行する。公開可否もチェックする", meta: "対応規約: pre-bash-dispatch-rules | PreToolUse(Bash)" }
            ]
          },
        ] },

      { n: 20, section: "phases", phase: "10", phaseTitle: "マージ後片付け", color: "accent",
        detail: "worktree 削除 + ポート kill + ブランチ削除。残留プロセスなしを確認。",
        flowSummary: "「環境復元」進捗クリーンアップ → worktree 削除 → ブランチ削除 → 完了報告",
        completionCondition: "worktree が削除されていること・残留プロセスがないこと",
        routes: ["full", "quick", "config", "refactor", "incident"],
        skill: null, stop: false, stopDetail: null,
        phaseSteps: [
          {
            id: "10-1",
            title: "進捗ファイルのクリーンアップ",
            detail: "ステータスライン進捗ファイルとセッション固有の一時ファイルを削除する。セッション跨ぎ進捗ファイルは PR マージ済みの場合のみ削除する（レビュー中は残す）。",
            completionCondition: "進捗ファイルと一時ファイルが削除されていて、セッション跨ぎ進捗ファイルの状態（削除 or 保持）が確定していること",
            timing: "マージ確認後",
            refs: [
              { type: "context", text: "フローログ出力先", desc: "フローログの出力ディレクトリ" },
            ],
            checks: [
              { type: "hook-notify", text: "cleanup-session-markers.sh（SessionEnd でマーカー自動清掃）", desc: "スキル発火ログを記録し、impl-session マーカーを書き込む", meta: "対応規約: session-infra-rules | PreToolUse(Skill)" }
            ]
          },
          {
            id: "10-2",
            title: "worktree 削除",
            detail: "PR マージ済みなら worktree を削除し、ポート管理規約に従い該当スロットのポート範囲を一括 kill する。PR オープン中は worktree を残す。",
            completionCondition: "worktree が削除されていること（PR マージ済み）またはそのまま保持されていること（PR オープン中）で、残留プロセスがないこと",
            timing: "Step 10-1 直後",
            refs: [
              { type: "skill", text: "parallel-dev-worktree", desc: "git worktree で実装用の独立作業ディレクトリを作成する" },
              { type: "rule", text: "port-management-rules", desc: "開発サーバーのポート番号を計算式で一意に決定し、ランダムポートを禁止する" }
            ],
            checks: [
              { type: "hook-block", text: "check-worktree-required.sh", desc: "メインツリーでの実装ファイル編集を禁止し、worktree 内での作業を強制する", meta: "対応規約: worktree-required-rules | PreToolUse(Write|Edit)" }
            ]
          },
          {
            id: "10-3",
            title: "ブランチ削除",
            detail: "マージ済みのリモートブランチを削除する（gh pr merge で自動削除されていない場合）。",
            completionCondition: "マージ済みのリモートブランチが削除されていること",
            timing: "Step 10-2 直後",
            refs: [],
            checks: [
              { type: "hook-notify", text: "check-main-agent-direct-work.sh（メインツリーでは解除）", desc: "メインエージェントの直接編集を防ぎ、サブエージェントへの委任を強制する", meta: "対応規約: subagent-delegation-rules | PreToolUse(Write|Edit|Bash)" }
            ]
          },
          {
            id: "10-4",
            title: "完了報告",
            detail: "PR URL・実行 Phase 一覧・スキップ Phase とその理由・進捗ファイルの状態をユーザーに報告する。",
            completionCondition: "PR URL・実行 Phase・スキップ Phase・進捗ファイルの状態がユーザーに報告されていること",
            timing: "Step 10-3 直後",
            refs: [
            ],
            checks: [
              { type: "hook-block", text: "check-no-delegation-stop.sh（最終報告）", desc: "最終応答にユーザーへの操作依頼が含まれていないか検査する", meta: "対応規約: response-guard-rules | Stop" }
            ]
          },
        ] },

      { n: 21, section: "phases", phase: "11", phaseTitle: "メイン同期・自己改善", color: "accent",
        detail: "git pull origin main で最新化。フロー改善メモの記録。",
        flowSummary: "「改善記録」main 最新化 → フロー改善メモ",
        completionCondition: "main ブランチが最新化されていること",
        routes: ["full", "quick", "config", "refactor", "incident"],
        skill: null, stop: false, stopDetail: null,
        phaseSteps: [
          {
            id: "11-1",
            title: "main 最新化",
            detail: "git pull origin main で main ブランチを最新化する。",
            completionCondition: "git pull が成功し、main ブランチが最新の状態であること",
            timing: "マージ後",
            refs: [
            ],
            checks: [
              { type: "hook-notify", text: "dispatch-pre-bash-checks.sh（rebase/merge 時）", desc: "コミットメッセージの命名規則・textlint・公開可否を検査する", meta: "対応規約: pre-bash-dispatch-rules | PreToolUse(Bash)" }
            ]
          },
          {
            id: "11-2",
            title: "フロー改善メモ",
            detail: "実行中に感じた摩擦・改善案があれば記録する。",
            completionCondition: "フロー改善メモが記録されていること（摩擦・改善案がない場合はスキップ済みであること）",
            timing: "Step 11-1 直後",
            refs: [
              { type: "context", text: "phase-11-main-sync-and-improve.md Step 11-2", desc: "フロー実行中の摩擦を記録し改善提案する手順（フロー本体にインライン化済み）" },
              { type: "rule", text: "managing-review-gate-rules", desc: "managed ファイル編集時にレビュー・テスト実行を機械強制する" }
            ],
            checks: [
              { type: "hook-block", text: "check-managing-configs-commit-gate.sh", desc: "managed ファイルの commit 時にテスト完了マーカーを検査する", meta: "対応規約: managing-review-gate-rules | PreToolUse(Bash)" },
              { type: "hook-notify", text: "check-managing-configs-review-needed.sh", desc: "managed ファイル編集後に対応する managing スキルの実行を促す", meta: "対応規約: managing-review-gate-rules | PostToolUse(Write|Edit)" }
            ]
          },
        ] },

      { n: 24, section: "phases", phase: "D", phaseTitle: "ドキュメント編集", color: "gold",
        detail: "変更対象特定 → 編集計画 → EnterPlanMode → ExitPlanMode → 編集 → 品質チェック（HTML 構文・リンク切れ・textlint）。",
        flowSummary: "「ドキュメント更新」対象特定 → 編集計画 → 計画承認 → 編集実行 → 品質チェック",
        completionCondition: "ドキュメント編集が完了していること・品質チェックを通過していること",
        routes: ["config"],
        skill: null, stop: true, stopDetail: "EnterPlanMode → ExitPlanMode（設定・docs ルートの停止点）",
        phaseSteps: [
          {
            id: "D-1",
            title: "変更対象の特定",
            detail: "編集対象のドキュメントファイルを特定する。",
            completionCondition: "編集対象のドキュメントファイルが特定されていること",
            timing: "Phase 開始直後",
            refs: [
            ],
            checks: [
              { type: "hook-notify", text: "check-main-agent-direct-work.sh（Read は通過）", desc: "メインエージェントの直接編集を防ぎ、サブエージェントへの委任を強制する", meta: "対応規約: subagent-delegation-rules | PreToolUse(Write|Edit|Bash)" }
            ]
          },
          {
            id: "D-2",
            title: "編集計画",
            detail: "変更内容の計画を策定する。",
            completionCondition: "変更内容の計画が策定されていること",
            timing: "Step D-1 直後",
            refs: [],
            checks: [
              { type: "hook-block", text: "check-worktree-required.sh", desc: "メインツリーでの実装ファイル編集を禁止し、worktree 内での作業を強制する", meta: "対応規約: worktree-required-rules | PreToolUse(Write|Edit)" },
              { type: "hook-block", text: "check-main-agent-direct-work.sh", desc: "メインエージェントの直接編集を防ぎ、サブエージェントへの委任を強制する", meta: "対応規約: subagent-delegation-rules | PreToolUse(Write|Edit|Bash)" }
            ]
          },
          {
            id: "D-3",
            title: "計画承認",
            detail: "EnterPlanMode で変更計画をユーザーに提示し、ExitPlanMode で承認を得る。ドキュメントルートの唯一の停止点。",
            completionCondition: "ExitPlanMode によるユーザー承認が得られていること",
            timing: "Step D-2 直後",
            refs: [
              { type: "rule", text: "no-premature-deferral-rules", desc: "作業の先送り（別セッション / 次回対応）を禁止する" }
            ],
            checks: [
              { type: "hook-guard", text: "EnterPlanMode → ExitPlanMode（docs ルートの停止点）", desc: "計画モードで実装ファイルの編集をブロックし、承認フローを強制する" }
            ]
          },
          {
            id: "D-4",
            title: "編集実行",
            detail: "承認された計画に従いドキュメントを編集する。",
            completionCondition: "承認された計画に従いドキュメントの編集が完了していること",
            timing: "Step D-3 承認後",
            refs: [
              { type: "rule", text: "pre-bash-dispatch-rules", desc: "git commit/branch/PR 作成時の命名規則・textlint・公開可否を検査する" }
            ],
            checks: [
              { type: "hook-block", text: "pre-bash-dispatch（git commit 時）", desc: "コミットメッセージの命名規則を検査し、docs の追加行に textlint を実行する。公開可否もチェックする", meta: "対応規約: pre-bash-dispatch-rules | PreToolUse(Bash)" }
            ]
          },
          {
            id: "D-5",
            title: "品質チェック",
            detail: "HTML 構文チェック・リンク切れ検出・textlint（日本語ドキュメントの場合）を実行する。完了後は Phase 7（完了チェック）に合流する。",
            completionCondition: "HTML 構文チェック・リンク切れ検出・textlint の品質チェックを通過していること",
            timing: "Step D-4 直後",
            refs: [
              { type: "rule", text: "pre-bash-dispatch-rules", desc: "git commit/branch/PR 作成時の命名規則・textlint・公開可否を検査する" },
            ],
            checks: [
              { type: "hook-block", text: "pre-bash-dispatch（コミット時）", desc: "コミットメッセージの命名規則を検査し、docs の追加行に textlint を実行する。公開可否もチェックする", meta: "対応規約: pre-bash-dispatch-rules | PreToolUse(Bash)" }
            ]
          },
        ] },

      { n: 25, section: "phases", phase: "I", phaseTitle: "インシデント独自フロー（I1-I7）", color: "danger",
        detail: "I1 障害確認 → I2 再現 → I3 修正 → I4 本番承認 → I5 デプロイ → I6 復旧確認 → I7 事後処理。本番操作は安全な手段のみ。I6 で復旧確認後は手続き省略可能。",
        flowSummary: "「障害復旧」状況確認 → 再現確認 → 修正実装 → 本番操作承認 → デプロイ → 復旧確認 → 事後処理",
        completionCondition: "障害復旧が確認されていること・修正が main にマージされていること",
        routes: ["incident"],
        skill: null, stop: true, stopDetail: "I4 で EnterPlanMode → ExitPlanMode（本番操作承認）",
        phaseSteps: [
          {
            id: "I1",
            title: "障害状況の確認",
            detail: "何が壊れているか（症状）・いつから壊れているか・影響範囲（ユーザー数・機能範囲）・直前のデプロイや変更との関連を把握する。",
            completionCondition: "障害状況（症状・発生時期・影響範囲・直前変更との関連）が把握されていること",
            timing: "Phase 1-2 完了後（incident ルート分岐直後）",
            refs: [
            ],
            checks: [
              { type: "hook-notify", text: "check-main-agent-direct-work.sh（Read は通過）", desc: "メインエージェントの直接編集を防ぎ、サブエージェントへの委任を強制する", meta: "対応規約: subagent-delegation-rules | PreToolUse(Write|Edit|Bash)" }
            ]
          },
          {
            id: "I2",
            title: "再現確認",
            detail: "ローカル環境で再現を試みる。再現できない場合はログ・メトリクスから根本原因を推定する。",
            completionCondition: "ローカルでの再現確認または根本原因の推定が完了していること",
            timing: "Step I1 直後",
            refs: [],
            checks: [
              { type: "hook-notify", text: "check-main-agent-direct-work.sh（Read は通過）", desc: "メインエージェントの直接編集を防ぎ、サブエージェントへの委任を強制する", meta: "対応規約: subagent-delegation-rules | PreToolUse(Write|Edit|Bash)" }
            ]
          },
          {
            id: "I3",
            title: "修正実装",
            detail: "最小限の修正で暫定復旧を目指す。TDD 省略可、回帰テストは後で追加する。",
            completionCondition: "最小限の修正が実装されていること",
            timing: "Step I2 直後",
            refs: [],
            checks: [
              { type: "hook-block", text: "check-main-agent-direct-work.sh", desc: "メインエージェントの直接編集を防ぎ、サブエージェントへの委任を強制する", meta: "対応規約: subagent-delegation-rules | PreToolUse(Write|Edit|Bash)" },
              { type: "hook-block", text: "check-worktree-required.sh", desc: "メインツリーでの実装ファイル編集を禁止し、worktree 内での作業を強制する", meta: "対応規約: worktree-required-rules | PreToolUse(Write|Edit)" }
            ]
          },
          {
            id: "I4",
            title: "本番操作承認（唯一の停止点）",
            detail: "EnterPlanMode で操作計画を提示し、ExitPlanMode で承認を得る。本番操作は安全な手段のみ許可（生コマンド直接実行は禁止）。",
            completionCondition: "操作計画が ExitPlanMode でユーザーに承認されていること",
            timing: "Step I3 直後",
            refs: [
              { type: "rule", text: "no-premature-deferral-rules", desc: "作業の先送り（別セッション / 次回対応）を禁止する" }
            ],
            checks: [
              { type: "hook-guard", text: "EnterPlanMode → ExitPlanMode（本番操作承認）", desc: "計画モードで実装ファイルの編集をブロックし、承認フローを強制する" }
            ]
          },
          {
            id: "I5",
            title: "デプロイ・適用",
            detail: "承認された修正を prod-op-plan.sh 等の安全な手段でデプロイする。生コマンド直接実行は禁止。",
            completionCondition: "承認済みの修正がデプロイされていること",
            timing: "Step I4 承認後",
            refs: [
              { type: "rule", text: "response-guard-rules", desc: "ユーザーへの操作依頼と先送り表現を禁止する" }
            ],
            checks: [
              { type: "hook-block", text: "check-no-delegation-pre-bash.sh（生コマンド直接実行禁止）", desc: "対話必須コマンドの発行を禁止し、token ベースの代替手段を使わせる", meta: "対応規約: response-guard-rules | PreToolUse(Bash)" }
            ]
          },
          {
            id: "I6",
            title: "復旧確認（停止チェックポイント）",
            detail: "障害症状・メトリクス・影響ユーザーの復旧を確認する。復旧確認後は以降の手続きを省略してよい。",
            completionCondition: "障害症状が解消し、メトリクスが正常値に戻っていることが確認されていること",
            timing: "Step I5 直後",
            refs: [],
            checks: [
              { type: "hook-block", text: "check-no-delegation-stop.sh（停止点）", desc: "最終応答にユーザーへの操作依頼が含まれていないか検査する", meta: "対応規約: response-guard-rules | Stop" },
              { type: "hook-block", text: "check-no-deferral-stop.sh（停止点）", desc: "最終応答に先送り表現が含まれていないか検査する", meta: "対応規約: response-guard-rules | Stop" }
            ]
          },
          {
            id: "I7",
            title: "事後処理",
            detail: "PR 作成（Phase 9 に合流）・回帰テストの追加（後日でも可）・ポストモーテムの起票（任意）を実行する。マージ後処理（Phase 10）とメイン同期（Phase 11）に合流する。",
            completionCondition: "PR 作成と事後処理が完了し、Phase 9 に合流していること",
            timing: "Step I6 直後",
            refs: [
            ],
            checks: [
              { type: "hook-block", text: "dispatch-pre-bash-checks.sh（PR 作成時）", desc: "コミットメッセージの命名規則を検査し、docs の追加行に textlint を実行する。公開可否もチェックする", meta: "対応規約: pre-bash-dispatch-rules | PreToolUse(Bash)" }
            ]
          },
        ] },

      // 事前準備 (section: "setup")
      { n: 26, section: "setup", setupNum: 1, setupTitle: "scaffold 実行", title: "【準備】scaffold 実行", detail: "creating-new-project スキルを実行。プロジェクト固有設定ファイル（flow-values.yml）/ layers.yml / project-portal / glossary.js / .gitignore を自動生成。", skill: "creating-new-project" },
      { n: 27, section: "setup", setupNum: 2, setupTitle: "必須ツール確認", title: "【準備】必須ツール確認", detail: "Node.js / Python / git / gh CLI / textlint / lychee / gitleaks / プロジェクト固有 lint が利用可能か確認。" },
      { n: 28, section: "setup", setupNum: 3, setupTitle: "初回動作確認", title: "【準備】初回動作確認", detail: "起動前チェックで全 PASS を確認してからフロー開始。プロジェクト固有設定ファイルがないプロジェクトではフローは起動しない。" }
    ],
    diagram: [
      "依頼 → Phase 1: 調査 + ルート判定",
      "       ├─ feature-with-full-planning    → Phase 1〜11",
      "       ├─ feature-with-quick-delivery    → Phase 5-6 スキップ",
      "       ├─ config-with-review-and-verify  → Phase D のみ",
      "       ├─ refactor-with-safety-guarantee → TDD なし",
      "       └─ incident-with-emergency-path   → I1-I7（最速）"
    ].join("\n"),
    notes: [
      "初回は creating-new-project スキルを実行してプロジェクト構造を生成する",
      "プロジェクト固有設定ファイルがないプロジェクトではフローは起動しない",
      "全ルートで worktree 内作業が必須",
      "承認は方針ミスの手戻りが大きいルートでのみ（クイックは承認なし全自走）",
      "data/*.js の並列セッションコンフリクトは機械的自動解消手順あり"
    ]
  }
];
