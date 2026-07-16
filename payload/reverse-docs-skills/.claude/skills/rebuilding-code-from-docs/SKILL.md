---
name: rebuilding-code-from-docs
description: "設計書だけから画面単位でコード再生成し元と突合、欠落発見。 TRIGGER when: 往復品質検証。 SKIP: 通常の機能実装・環境同期。"
invocation: rebuilding-code-from-docs
type: orchestration
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob]
---

# 設計書からのコード再構築スキル

リバースエンジニアリングで作成した画面詳細設計書（起動引数 `template_root` 配下の画面詳細設計書テンプレートに準拠、章の役割キー（16 種、既定 §1〜§16）で構成）は納品物であり、「設計書だけを読んで忠実にコーディングできる」詳細度が求められる。本スキルはその品質を検証するため、**設計書だけからコードを再生成し、元コードと機械突合して設計書の欠落を発見する**往復検証を行う。

コードを直すことは目的ではない。フィードバック先は (a) 当該画面設計書の該当章（役割キー）、(b) 欠落が汎用的ならテンプレート自体の記載粒度改善の 2 つ。

環境管理・比較エンジンは管理者が仲介する。本スキルは値を保持せず、起動引数 `mode`（`implement` | `judge`）と mode ごとの args から受け取る。`mode=implement` は白紙化 → TDD 実装 → 自己完結チェック → 凍結コミットまでを実行して停止し（比較は行わない）、`mode=judge` は管理者から渡された比較結果を判定根拠に NG 分類・修正指示書・最終報告までを実行する。1 回の起動では `mode` のどちらか一方のみを実行する。

## 使用タイミング

- リバース済み設計書の往復検証・粒度検証・品質検証を行いたいとき
- 起動引数は `mode`（`implement` | `judge`）と、mode ごとの args 全量（後述の「起動引数」参照）
  - `mode=implement`: 白紙化 → TDD 実装 → 自己完結チェック → 凍結コミットまでを実行し、`status=NEED-COMPARE` と拡張フィールド `compare_request`（scope・design_doc・freeze_commit・scenarios_ready）を返して停止する
  - `mode=judge`: 起動引数 `compare_result`（管理者が比較〔dry-run〕を実行して取得した結果ブロック）・`reverse_worktree`（reverse-code worktree パス）・`freeze_commit`（`mode=implement` の `compare_request` で返した凍結コミットハッシュ。管理者が保持して渡す）を受け取り、NG 分類 → 修正指示書 → 最終報告までを実行する
- 前提: 基準タグ `reverse-baseline/<scope>` が確立済みであること。未確立の場合、`mode=implement` は Phase 1 で `status=BLOCKED` を返して管理者へ差し戻す
- 設計書そのものの直接修正が目的なら本スキルは使わない（本スキルは修正指示書を出すだけで、設計書もコードも直接書き換えない）

## 設計原則

1. **正本一元化**: 環境固有値（ポート・worktree パス）の正は起動引数の env_block（`scope` / `reverse_worktree` / `ports` / `baseline_tag_status` / `docs_root`）。画面固有値の正は設計書 frontmatter（`doc_id` / `scenarios`（旧 `route`） / `source_repo` / `unit_test_sheet` / `integration_test_sheet` 等）。本スキル専用の config.yml は新設しない
2. 比較エンジンは自前実装しない。`mode=judge` は起動引数 `compare_result`（管理者が比較〔dry-run〕を実行した結果ブロック）のみを判定根拠とする
3. **1 起動 = 1 往復**。設計書修正が必要になった場合、修正後の再往復は管理者による本スキルの再起動として扱う（同一起動内でループしない）
4. **検証役と生成役の分離**: `mode=implement`（実装）の自己申告では判定しない。判定は `mode=judge` が受け取る `compare_result` の決定的出力のみで行う

## 基本ワークフロー（Phase 1〜9）

### Phase 1: 入力ロード + preflight

#### 起動引数の解決

`mode=implement` は args として `screen_dir`（画面ディレクトリパス。例: `<docs_root>/画面/screen-<画面ID>/詳細設計`）・`scope`・`reverse_worktree`・`ports`・`baseline_tag_status`・`docs_root`・`template_root`・`audit_script_path`・`chapter_map_path`・`user-approved`・`saved_test_paths`（上流 rebuilding-screen-unit-from-docs が保存した単体テストコードのパス一覧。上流未実施の画面では省略される）を受け取る。これらは管理者が事前解決して渡す値であり、本スキル自身は取得・導出しない。`docs_root` が欠落している場合は Phase 1 で `status=BLOCKED` として管理者へ差し戻す。

起動引数の `screen_dir` から以下の設計資産を frontmatter 経由でロードする。

**画面単位（`画面/詳細設計/` 配下）**:
- 画面詳細設計書.md（必須。無ければ即エラー）
- DESIGN.md（frontmatter `design_md` キーがあれば必須）
- 単体テスト観点表.md・結合テスト観点表.md（frontmatter `unit_test_sheet` / `integration_test_sheet` キーがあれば必須）

**画面単位（`画面/テスト項目書/` 配下）**:
- 単体テスト仕様書.md・結合テスト仕様書.md（frontmatter `unit_test_spec` / `integration_test_spec` キーがあれば必須。キー自体が無ければ「不在」と記録し、Phase 4 では観点表から直接テストケースを作成する）
- 操作シナリオ仕様書.md（frontmatter `operation_test_spec` キーがあれば必須）

**プロジェクト共通（`プロジェクト共通/` 配下）**:
- 共通設計書.md（frontmatter `common_spec` キーがあれば必須）
- メッセージ定義書.md（frontmatter `messages` キーがあれば必須）
- DESIGN.md（frontmatter `common_design_md` キーがあれば必須）
- 規約/ 配下の 4 ファイル（コーディング規約.md・命名規約.md・ディレクトリ構成規約.md・コンポーネント設計規約.md）。規約ファイルは frontmatter キーを持たず、`../../../プロジェクト共通/規約/` を固定パスで探索する。存在するファイルをすべてロードし、存在しないファイルは「不在」と記録して続行する（規約ファイルは任意）

上記のうち「キーがあるのに実体が無い」ファイルは preflight エラーとする。

`scope`・両環境のパス（`reverse_worktree`）・確定ポート（`ports`）・基準タグ状態（`baseline_tag_status`）は、管理者が事前解決して args（env_block）で渡す値をそのまま使う（本スキルは自ら導出・取得しない。参考導出式: `<system>` は `source_repo` 末尾 basename から `.git` を除いた値、`<画面ID>` は frontmatter `doc_id: screen-<画面ID>` から `screen-` 接頭辞を除いた値、`<scope>` = `<system>-<画面ID>`）。`baseline_tag_status` が基準タグ未確立を示す場合は Phase 1 で停止し、`status=BLOCKED` を返して管理者へ差し戻す。
完了条件: 設計書一式・規約ファイル群がロード済みで、基準タグの存在が確認できている（未確立なら `status=BLOCKED` で停止）

### Phase 2: 設計書内部整合性監査

起動引数 `audit_script_path` を Bash 実行 + 目視で以下を突合する: 機能一覧章の機能一覧表（既定 §2）× 観点表の機能キー集合（両方向一致）、API通信章の API 型（既定 §7）× 実装契約章の型定義（既定 §15.2）、状態管理章の状態変数（既定 §5）× 領域別仕様章/実装契約章の経路（既定 §9/§15）、意味キー連番検出、未記入プレースホルダ検出。詳細な突合式は `references/phase-details.md` を参照。
**内部矛盾があれば実装せず Phase 8 へ直行する**（欠陥のある設計書からの実装は無意味なため）。
併せて、§16要確認事項一覧に未解消（状態≠解消済み）の行が残っていないかを確認する（audit-consistency.shの検査i）。既定はWARNであり自動的にPhaseを止めない。往復検証に入る前に§16をゼロ解消へ揃えたい場合は、管理者がAUDIT_STRICT_P16=1を設定した上でaudit_script_pathを再実行し、違反として明示的にブロックさせることができる。
完了条件: 監査結果（一致/不一致の一覧）が記録されている

### Phase 3: 白紙化ゲート

起動引数 `audit_script_path --list-contract-files <画面ディレクトリ>` を Bash 実行し、実装契約章のファイル分割表（既定 §15.1）に列挙された対象ファイル一覧を取得する（正常時は 1 行 1 パスで stdout に出力される）。取得不可（`exit 1`）の場合は Phase 3 を ERROR とし「実装契約章の不備」として Phase 8 へ直行する。**全消しフォールバックは禁止**（取得に失敗したからといって環境の全ファイルを削除してはならない、fail-closed）。取得できた対象ファイルのみを削除対象とする。削除コミットを打つ**前に**、起動引数 `user-approved`（白紙化承認。管理者が事前取得済みの値）を確認する。`user-approved` が無ければ Phase 3 を `status=BLOCKED` として管理者へ差し戻す。**全消しフォールバックは禁止**のため、`user-approved` が無い場合も取得済みの対象ファイル一覧はそのまま検証記録に残す。`user-approved` があれば対象ファイルを `git rm` で個別に削除する（追跡外・不存在のファイルは「既に白紙」として記録し続行する）。コミットメッセージは `【リファクタ】<画面ID> の設計書対象ファイルを白紙化` とする。以降 Phase 7 まで **オリジナルコード環境の Read を禁止**する（カンニング防止）。
完了条件: 対象ファイル一覧を取得済み（取得不可なら ERROR で Phase 8 直行）・起動引数 `user-approved` 確認済み（無ければ `status=BLOCKED` で差し戻し）・白紙化コミットが完了し、以降の禁止事項をタスク内で宣言している

### Phase 4: 設計書からの TDD 実装

**唯一コードを書けるフェーズ**。本スキルを実行しているセッション自身が、以下の 4 ステップを直接実行する。進捗は Step 単位で TaskCreate/TaskUpdate により可視化する。

#### Step 1: READ（設計書・規約の読み込み）

対象設計書の該当章のみを読む。オリジナルコード環境は一切読まない（カンニング防止）。加えて、Phase 1 でロード済みの規約ファイル群（`プロジェクト共通/規約/` 配下）を参照し、コーディングスタイル・命名パターン・ディレクトリ配置・コンポーネント設計パターンを把握する。

読み込み対象:
- `画面/詳細設計/画面詳細設計書.md` — 実装の元となる設計書
- `画面/詳細設計/DESIGN.md` — スタイル数値の正
- `プロジェクト共通/共通設計書.md` — 共通挙動の正
- `プロジェクト共通/メッセージ定義書.md` — 文言の正
- `プロジェクト共通/DESIGN.md` — 共通デザイン値の正
- `プロジェクト共通/規約/コーディング規約.md` — コードスタイル・フォーマット
- `プロジェクト共通/規約/命名規約.md` — ファイル名・変数名・コンポーネント名のパターン
- `プロジェクト共通/規約/ディレクトリ構成規約.md` — ファイル配置のルール
- `プロジェクト共通/規約/コンポーネント設計規約.md` — コンポーネントの構造パターン
- reverse環境内の共通コンポーネント Props interface — 設計書 §9.n.1「使用する共通コンポーネント」に列挙された各コンポーネントの `src/components/` 配下の型定義ファイル。**共通コンポーネントの型定義ファイルはカンニング禁止の対象外**（禁止対象はオリジナル画面コードのみ）

Step 1 完了条件: 上記の読み込みが完了し、DESIGN.md の `components.*` 全トークン（キーと具体値）を一覧化して検証記録に書き出したこと（後段 STYLE-GATE の入力になる）

#### Step 2: SPEC（テストコード調達 = TDD の Red）

**単体テストコードは自作しない**。単体テストの正本は上流 rebuilding-screen-unit-from-docs が持つ。起動引数 `saved_test_paths`（上流が設計書リポジトリ `<画面ディレクトリ>/テスト項目書/テストコード/単体/<basename>/` 配下に保存済みの単体テストコード一覧）を受け取っている場合、そのテストコードを起動引数 `reverse_worktree`（本スキルが操作する対象コードリポジトリ。上流の起動引数 `target_repo_path` とは別スキルの別引数であり同一物ではない）の対応パス（`プロジェクト共通/規約/ディレクトリ構成規約.md` に従う配置先）へ配置して実行する。単体テストコードの新規作成は行わない。

**代替経路（上流未実施画面）**: `saved_test_paths` が空または未提供の画面（基準未確立/往復未検証 開始でファイル単位検証をスキップした画面等、上流の単体テストが存在しない場合）に限り、単体テスト観点表（`画面/詳細設計/単体テスト観点表.md`）の各観点キーから直接テストケースを導出して自作する。これは正規の代替経路だが、自作した単体テストは検証用の一時テストであり、テストコード正本ディレクトリ（`<画面ディレクトリ>/テスト項目書/テストコード/単体/`）への保存を禁止する。単体テストコード正本の生産者は rebuilding-screen-unit-from-docs のみである（一本化）。自作した場合は、一時テストである旨を検証記録に明記する。

結合テストコードは従来どおり本スキルが自作する。結合テスト仕様書（`画面/テスト項目書/結合テスト仕様書.md`）が存在すれば、その具体的な入力値・期待結果に基づいてテストコードを書く。結合テスト仕様書が不在の場合は、結合テスト観点表（`画面/詳細設計/結合テスト観点表.md`）の各観点キーから直接テストケースを導出する。

**E2E テストの作成とベースライン実測（本スキルの確定責務）**: E2E（`RT-` / `SM-` / `IT-` / `CMP-` 接頭辞）テストの作成と、元コード（オリジナルコード環境）でのベースライン実測は本スキル（`mode=implement`）が担う。操作シナリオ仕様書・結合テスト観点表・設計書 frontmatter の `scenarios` に基づいて E2E テストを作成し、オリジナルコード環境に対して実行してベースライン結果を検証記録に残す（実測はオリジナル環境の起動・操作のみで行い、オリジナルコードの Read は行わない。カンニング禁止は維持される）。作成とベースライン実測の完了可否は Phase 6 で返す `compare_request.scenarios_ready` に反映し、両環境突合としての実行は管理者（orchestrating-reverse-docs-flow）が dynamic 検査（`scenarios` 引数）として担う。

テストコードのファイル名・配置先は `プロジェクト共通/規約/命名規約.md`・`ディレクトリ構成規約.md` に従う。テストが全て Red（失敗）であることを確認してから Step 3 へ進む。

**既存テストの保護と配置衝突の回避**: テストコードを `reverse_worktree` へ配置する際、対象リポジトリに既存のテストファイルがある場合は上書き・削除を禁止する。配置先パスが既存ファイルと衝突する場合は別ディレクトリへ配置し、テストランナーへ実行対象のファイル引数を明示して実行する（既存テストスイートを侵さない）。

#### Step 3: WRITE（最小実装 = TDD の Green）

テストを通す最小実装を書く。以下の規律を守る:

- **規約準拠**: `プロジェクト共通/規約/` 配下の 4 ファイルに記録されたスタイル・命名・配置・設計パターンに従う
- **import/export/Props 名の完全一致**: 実装契約章のファイル分割表の export 名（既定 §15.1）、依存の import 名（既定 §15.3）、コンポーネント Props 名は設計書の記載と **文字列完全一致** させる
- **キー集合 EXTRA/MISSING 両方向一致**: 設計書に記載されたキー集合（型フィールド・状態変数・定数名等）と実装のキー集合を両方向で突合する
- **常時マウント則**: 絶対配置+座標で表示制御する要素は DOM 常時マウント・条件付きレンダリング禁止（DESIGN.md・設計書 §3.6 のスタイル適用パターンに従う）
- **DESIGN.mdトークン適用則**: 設計書が「DESIGN.md 参照」と書いた箇所は、対応する具体値を styled/sx として必ず実装する。`styled("th")({})` のような空のスタイル定義で置くことを禁止する
- **props実在則**: 共通コンポーネントへ渡す props は Step 1 で読んだ interface に存在するフィールドのみ。設計書に書いてない props 名を発明して渡すことを禁止する
- **常時マウント則の完全履行**: 「DOM にマウントする」と「絶対配置 CSS で隠す」はセットで1つの実装。マウントだけ実装して隠す CSS を省略することを禁止する
- **書き込み範囲**: Phase 3 の白紙化リスト（`--list-contract-files` の出力）内のファイルのみ。リスト外への書き込みは禁止

#### Step 4: VERIFY（実装契約との過不足チェック）

実装契約章のファイル分割表（既定 §15.1）と実装ファイルの過不足を機械チェックする:
- 設計書にあるが実装にないファイル → MISSING
- 実装にあるが設計書にないファイル → EXTRA
- MISSING または EXTRA が 1 件でもあれば Step 3 へ戻る

#### Step 5: STYLE-GATE（DESIGN.md トークン突合）

DESIGN.md から数値トークン（px 値・色コード）を抽出し、白紙化リスト内の実装ファイル群と grep で機械突合する。

- 欠落トークンが 1 件でもあれば Step 3 へ差し戻す（fail-closed）。欠落一覧を検証記録に残す
- 除外できるのは「共通コンポーネント固定値。画面コードでは指定しない」と DESIGN.md 自身に注記のあるトークンのみ。除外は理由付きで記録する
- Step 1 で書き出したトークン一覧と突合することで、漏れを機械的に検出する

Step 5 完了条件: 全トークンが実装ファイル内に出現する（除外分は理由付き記録済み）こと

完了条件: 実装契約章のファイル分割表（既定 §15.1）と実装ファイルが過不足なく一致し、STYLE-GATE が PASS していること

### Phase 5: 自己完結チェック

本スキルを実行しているセッション自身が、型チェック・単体テスト（Step 2 で配置した上流提供の単体テストコード、または代替経路で自作した一時テストコード）・結合テスト・Playwright スモーク（reverse 側 9110 番台のみ）を直接実行する。内側ループは上限 3 回、同一エラーシグネチャ 3 連続で発散確定とし、発散したエラー自体を設計書欠落候補として Phase 8 へ渡す。検証コマンドの詳細は `references/phase-details.md` を参照。

**実行規律**:
- 納品/配置されたテストは全ファイル・全件実行を必須とし、部分実行を禁止する。テスト失敗時に修正してよいのは実装（白紙化リスト内ファイル）のみで、テストコード側は変更しない
- テストランナーが vitest の場合は必ず `vitest run --ui=false` で実行する（対象リポジトリの vitest.config が `ui:true` でも watch/UI モードに入らせない。config は変更禁止）
- E2E 系スクリプト（`RT-` / `SM-` / `IT-` / `CMP-` 接頭辞。Step 2 で本スキルが作成し元コードでベースライン実測済みのもの）を実行する。作成に至らなかった場合は「未実施」と記録し、PASS 判定の根拠に数えない

完了条件: 型チェック・テスト・スモークの結果がすべて記録されている（PASS または発散確定のいずれか）。かつ全テストケースの実行結果（PASS/FAIL/未実施）が漏れなく記録されている（未実施を残したまま PASS としない）

### Phase 6: 凍結コミット

前提条件: Phase 4 の STYLE-GATE と Phase 5 の全ゲート（型チェック・テスト・スモーク）が PASS していること。ゲート未 PASS での凍結コミットを禁止する。

`feature/reverse-code-<scope>` へコミットする。**push は禁止**。このコミットハッシュを凍結基準点とする。

**凍結コミット対象は Phase 3 白紙化リスト内の実装ファイルのみ**。Step 2 で配置・自作したテストコードはコミット対象に含めない（`git add` は白紙化リスト内の実装ファイルを個別指定する。テストコードは凍結コミット前に撤去するか、最初から git 管理外に置く）。

**`mode=implement` はここで終了する**。`status=NEED-COMPARE` と拡張フィールド `compare_request { scope, design_doc（設計書パス）, freeze_commit（凍結コミットハッシュ）, scenarios_ready（真偽値） }` を返し、比較の実行は管理者に委ねて停止する（本スキルは比較エンジンを呼び出さない）。`scenarios_ready` は Step 2 で作成した E2E テストが元コードでのベースライン実測まで完了し、管理者が実行する dynamic 検査（`scenarios` 引数）で実行可能な状態にあるかを表す。

完了条件: 凍結コミットハッシュが確定し、`status=NEED-COMPARE` と `compare_request` を返却している

### Phase 7: 答え合わせ（`mode=judge` の入口）

`mode=judge` はここから開始する。起動引数 `compare_result`（管理者が比較〔dry-run〕を実行して取得した、静的 3 分類・env_check 全項目・Playwright L1〜L5（L5 は `operations` を持つ画面のみ評価対象）・`hint`・`status` を含む比較結果ブロック）のみを判定根拠とする。起動引数 screen_dir（Phase 9 の検証記録保存先に用いる）も受け取る。起動引数 `reverse_worktree`・`freeze_commit` も併せて受け取り、Phase 9 の凍結検証に用いる。設計書 frontmatter の `scenarios[].query` / `path_params` / `ready` / `assert` / `mask` は、比較結果ブロック内の描画到達（render-ready）判定・テーブル/データ内容一致判定・非決定領域マスクの入力として、管理者側の比較実行時に既に反映されている前提で評価する。**比較の自前実装は禁止**。`compare_result.status` が `DESIGN-INCOMPLETE`（両環境とも同様に render-ready 未到達）の場合は Phase 8 へ「設計書 frontmatter の scenarios に query/path_params/ready を追加する」修正指示として渡す。`compare_result.status` が `DYNAMIC-UNVERIFIED`（MCP・Playwright とも不在で動的検証不能）の場合は静的一致のみで PASS 扱いにせず、Phase 9 の最終報告に「動的未検証のため往復検証完了としない」旨を明記する。

**PASS/FAIL 判定は `compare_result.status` をそのまま転用しない**。管理者から渡される比較結果ブロックは計測事実（`static_diff` / `dynamic` / `env_check`）であり、往復検証の PASS/FAIL の意味解釈は本スキル（`mode=judge`）が単独で担う（契約正本 orchestrating-reverse-docs-flow の `references/contract.md` の解釈責務の規定に従う）。本スキルは Phase 3 の白紙化 + Phase 4 のカンニング禁止実装により設計書だけから独立に書き直す用途のため、変数名・コメント差による実差分は原理的に非ゼロになる。よって mode=judge は `compare_result.static_diff`（実差分行）を PASS/FAIL の判定材料に使わず、`compare_result.env_check`（全項目）と `compare_result.dynamic`（render-ready 到達・内容一致〔L2'〕・L2 ARIA・L3 画素・L4 コンソール・該当時 L5）のみで独自に PASS/FAIL を判定する。判定式: `env_check` 全通過 ∧ 全 scenario で render-ready 到達 ∧ L2' 内容一致 ∧ L2 一致 ∧ L4 一致 ∧ L3 閾値内 ∧（`operations` を持つ scenario がある画面は L5 一致も必須）。`env_check` が正式13項目チェックリスト（正本: `syncing-reverse-env-guide.html` の env_check 全項目）の完全実施でない場合（簡略実施・未実施を含む）は、上記判定式を満たしていても `DYNAMIC-UNVERIFIED` として扱い、PASS 判定にしない。`compare_result.status` が `PASS` ならこの判定式は自動的に満たされる。`status` が `FAIL` でも `static_diff` のみが原因で上記判定式を満たす場合は、本スキルとしては PASS 相当として扱う。`static_diff` は Phase 8 で NG の直接的な根拠にせず、動的差異の原因調査を補助する参考情報としてのみ扱う。

合否宣言の規律:
- L3 画素比較（閾値内）と L2 ARIA 一致を「達成」宣言の必須条件とする。L2'（テキスト内容一致）のみの状態で、コミットメッセージ・報告書に「達成」「完全一致」と書くことを禁止し、「視覚未達」と明記する
- L3 判定は証跡（スクリーンショット・画素差分値の保存パス）が存在しない場合は未実施扱いとする
- 実測委譲プレースホルダ（セレクタ未確定）が操作シナリオ仕様書に残存する場合、L5 操作突合はスキップし `DYNAMIC-UNVERIFIED` 注記を付与する。L5 操作突合は操作シナリオ仕様書のセレクタが実測値で埋まっていることを前提とする

**セレクタ確定責務**: judge PASS 時、操作シナリオ仕様書の実行用 YAML ブロック内に実測委譲プレースホルダが残っていれば、比較結果ブロックの dynamic（L5 操作突合の実測）で確認された実セレクタ・URL・断定値へ更新して確定する。更新は実測値の転記に限り、操作手順の創作・追加は禁止する。

完了条件: 起動引数 `compare_result` を受領し、`static_diff` を除く `env_check`/`dynamic` のみで PASS/FAIL を判定している

### Phase 8: NG 分類 → フィードバック

`references/ng-classification.md` で検出シグナルを失敗クラスに分類し、(a) 当該設計書の該当章（役割キー）への修正指示書、(b) 汎用的失敗クラスはテンプレート改善提案 + `references/test-item-patterns.md` への台帳追記を作る。`compare_result.status` が `DESIGN-INCOMPLETE` の場合、帰着先は frontmatter の `scenarios` とし「query/path_params/ready の追加」を修正指示とする。`DYNAMIC-UNVERIFIED` は失敗クラスではなく報告注記として扱い、NG 一覧には計上しない。**コード・設計書とも修正禁止。指示書の作成と台帳追記のみ許可**する。書式は `references/report-format.md` に従う。
完了条件: 修正指示書（NG があった場合）または「NG なし」の明示が完了している

### Phase 9: 証跡保存 + 最終報告

起動引数 `reverse_worktree`・`freeze_commit` を用いて `scripts/check-freeze.sh <reverse_worktree> <freeze_commit>` を実行し、現状（HEAD・作業ツリー）と突合する。不一致なら結果全体を無効宣言する。全証跡・`[未実行]` 0 件・NG 分類を含む最終報告を `references/report-format.md` の書式で作成し、`status=PASS | FAIL | DESIGN-INCOMPLETE | DYNAMIC-UNVERIFIED` を返す。**基準タグ更新は本スキルでは実行しない**。最終報告には「PASS 時の基準タグ更新は管理者が比較エンジンの本番実行（非 dry-run）で行う」旨を明記する。

最終報告の定量欄（必須）:
- DESIGN.md トークン適用率 n/m（Step 1 で書き出したトークン数を分母、実装ファイルで出現したトークン数を分子）
- 対象ファイル型エラー数（Phase 5 の白紙化リスト内ファイル限定）
- L3 画素差分値（証跡パス付き。未実施の場合は「未実施」と明記）
- テストケース識別子別 実行結果表（テストファイルが公開する test 名 / id → PASS / FAIL / 未実施）。連番 ID を発明せず、テストファイルが持つ識別子をそのまま列挙する。未実施が 1 件でもあれば `status=PASS` にできない

完了条件: 最終報告が作成され、凍結検証の結果が明示されている

最終報告作成後、チャットでの最終応答は `references/chat-report-format.md` の書式に従って作成する。設計書リポジトリに保存する最終報告（`references/report-format.md`）とは別に、ユーザーが今すぐ目視確認・判断できる要約として作成する。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 設計書一式がロード済み・基準タグの存在確認済み（未確立なら `status=BLOCKED` で停止） |
| Phase 2 | 監査結果が記録済み（内部矛盾なら Phase 8 へ直行） |
| Phase 3 | 起動引数 `user-approved` 確認済み・白紙化コミット完了・カンニング禁止を宣言済み |
| Phase 4 | 実装契約章のファイル分割表（既定 §15.1）と実装が過不足なく一致し、STYLE-GATE が PASS |
| Phase 5 | 型チェック・テスト・スモークの結果が記録済み・全テストケースの実行結果（PASS/FAIL/未実施）が漏れなく記録済み |
| Phase 6 | Phase 4 STYLE-GATE と Phase 5 全ゲートが PASS・凍結コミットハッシュが確定・凍結コミットにテストコードが含まれていない・`status=NEED-COMPARE` と `compare_request` を返却（`mode=implement` の終了点） |
| Phase 7 | 起動引数 `compare_result` を受領済み（`mode=judge` の入口）・PASS/FAIL は `static_diff` を除く `env_check`/`dynamic` のみで判定・L3 画素比較+L2 ARIA 一致が「達成」判定の必須条件 |
| Phase 8 | 修正指示書または「NG なし」の明示が完了 |
| Phase 9 | 最終報告作成済み（定量欄: トークン適用率・型エラー数・L3 画素差分値を含む）・凍結検証の結果が明示済み・チャット最終応答が `references/chat-report-format.md` の書式で作成済み |
| **Goal** | 全 Phase 完了（`mode=implement` は Phase 1〜6、`mode=judge` は Phase 7〜9）・`[未実行]` 0 件（テスト実行結果表の未実施 0 件を含む）・凍結検証 PASS・修正指示書または PASS 報告が検証記録に保存済み |

## ループ設計

| 要素 | 内容 |
|---|---|
| 反復条件（内側・Phase 5） | 型チェック/テスト/スモークが FAIL した場合、Phase 4 の該当箇所へ戻り修正する |
| 上限回数（内側） | 3 回 |
| 停止条件（内側） | 収束停止: 全チェック通過 / リソース上限: 3 回到達 / 発散検知: 同一エラーシグネチャ 3 連続 |
| 反復条件（外側） | 設計書修正が必要と判明した場合の再起動判定・上限管理は管理者が担う |
| 上限回数（外側） | 本スキルは 1 起動 = 1 往復（`mode=implement` または `mode=judge` の単発実行）。外側ループの反復自体は本スキルの範囲外 |
| 検証役の分離 | `mode=judge` の判定は起動引数 `compare_result` の決定的内容のみで行う。`mode=implement` 実装時点の自己申告では判定しない |

## 重要な注意事項

- Phase 4 以外でコードを書いてはならない
- Phase 3〜Phase 7 の間、オリジナルコード環境への Read は禁止（カンニング防止）
- Phase 8 ではコード・設計書とも修正禁止。修正指示書の作成と `test-item-patterns.md` への台帳追記のみ許可
- push は一切禁止。凍結コミットはローカルブランチに留める
- 凍結コミットは実装ファイル（Phase 3 白紙化リスト内）のみ。テストコード（上流提供・自作いずれも）を凍結コミットに含めることを禁止する
- Step 2 で配置した上流提供の単体テストコードを、緑にする目的で修正・削除してはならない。テストが壊れている・不足している場合は実装で辻褄を合わせず、`status=BLOCKED` で管理者へ差し戻す（上流 rebuilding-screen-unit-from-docs の成果物不備として扱う）
- Phase 管理: 次の Phase に入る前に、その Phase 内の全 Step を TaskCreate で登録する。各 Step 完了時に TaskUpdate で completed にする。Phase の全 Step が completed になるまで次の Phase に進まない。一括登録（全 Phase 分を最初に登録）は禁止し、1 Phase ずつ登録する
- 基準タグ更新は本スキルでは実行しない。管理者が比較エンジンの本番実行（非 dry-run）で行う

## 予想を裏切る挙動

- Phase 2 で内部矛盾を検出した場合、Phase 4 の実装は行わない。欠陥設計書からの実装検証は往復検証として無意味なため、直ちに Phase 8 の指示書作成に移る
- Phase 5 の発散確定は失敗ではなく手がかり。発散したエラー自体を設計書欠落候補として Phase 8 に渡す
- 検証成果物は `<verification_dir>/screen-<画面ID>/<timestamp>/` に置く（`verification_dir` は docs と同階層の `verification/`。検証記録の出力先は docs 内ではなく verification/ である）。worktree 内には置かない（静的比較を汚すため）
- 生証跡（スクリーンショット・テストログ・返却ブロック全文）は `<verification_dir>/screen-<画面ID>/<timestamp>/` 配下に同梱し、指示書からは同ディレクトリ内の相対パスで参照する（設計書リポジトリ外のセッション記録フォルダへの配置・参照は廃止）
- 管理者から渡される比較結果ブロックは計測事実（`static_diff` / `dynamic` / `env_check`）であり、往復検証の PASS/FAIL の意味解釈は judge（本スキル `mode=judge`）が単独で担う。解釈責務の規定は契約正本（orchestrating-reverse-docs-flow の `references/contract.md`）に従い、`compare_result.status` を直接転用せず Phase 7 に記載の判定式（`env_check`/`dynamic` のみ）で判定すること

## 完了報告

`managing-agent-configs/references/skills/completion-report-format.md` の共通骨格（作業報告型）に従う。

固有の検証行:
- 凍結検証 PASS・最終報告（トークン適用率・型エラー数・画素差分値）の作成完了

## 設計判断

### audit-consistency.sh

**必要性**: Phase 2 の設計書内部整合性監査（機能一覧章の機能一覧表〔既定 §2〕× 観点表の機能キー集合〔両方向一致〕、API通信章の API 型〔既定 §7〕× 実装契約章の型定義〔既定 §15.2〕、状態管理章の状態変数〔既定 §5〕× 領域別仕様章/実装契約章の経路〔既定 §9/§15〕、意味キー連番検出、未記入プレースホルダ検出）は複数の突合式を組み合わせた決定的検査であり、毎回手書き grep で実行すると突合条件がぶれて再現性が失われる。`--list-contract-files` モードは Phase 3 白紙化ゲートの対象ファイル抽出にも使う。章マップ解決（役割キー→§→節キーワード）を Phase 2 の検査と Phase 3 の白紙化で共有することで、同じ解決ロジックの二重実装によるズレを防ぐ。本スキルはスクリプト本体を持たず、起動引数 `audit_script_path` として管理者から渡されるスクリプトを Bash 実行する。

**代替案を採用しなかった理由**:
- Bash 直叩き: 複数検査の組合せと終了コード集計が都度手書きになり回帰検証不能
- hook 化: Phase 2 というフェーズスコープの検査であり、全セッション常駐は過剰

**保守責任者**: 人手（ユーザー）

**廃棄条件**: 本スキル廃止時

### check-freeze.sh

**必要性**: Phase 9 の凍結検証は「答え合わせ後の修正禁止」ガードの事後機械検証であり、Phase 6 の凍結コミットハッシュと現状（HEAD・作業ツリー）の一致確認をエージェントの自己申告に委ねると信頼できない。

**代替案を採用しなかった理由**:
- Bash 直叩き: 複数検査の組合せと終了コード集計が都度手書きになり回帰検証不能
- hook 化: Phase 9 のみのフェーズスコープ検査であり、全セッション常駐は過剰

**保守責任者**: 人手（ユーザー）

**廃棄条件**: 本スキル廃止時

## 参照資料

- `references/phase-details.md` — Phase 2 突合式・Phase 4 実装規律・Phase 5 検証コマンド詳細
- `references/ng-classification.md` — 検出シグナル→失敗クラス→章（役割キー）帰着のマッピング
- `references/test-item-patterns.md` — 失敗クラス台帳（追記型）
- `references/report-format.md` — 修正指示書・最終報告の書式
- `references/chat-report-format.md` — チャットでユーザーに返す最終報告の書式（`report-format.md` はファイル保存用、こちらは対話画面表示用）
- `references/rebuilding-code-from-docs-guide.html` — スキルガイド（単一ファイル自己完結）
- `~/reverse-docs-skills/.claude/skills/orchestrating-reverse-docs-flow/references/contract.md` — 完全仲介方式の契約正本。本スキルはこの契約に準拠し、`mode` を含む args 全量指定で単独起動できる
- 起動引数で受け取る資産の移設先（管理者が args で配布）:
  - `audit_script_path`: `~/reverse-docs-skills/shared/scripts/audit-consistency.sh`
  - `template_root`: `~/reverse-docs-skills/shared/templates/リバース検証`（画面詳細設計書テンプレート〔章の役割キー 16 種、既定 §1〜§16〕・プロジェクト共通規約〔コーディング規約・命名規約・ディレクトリ構成規約・コンポーネント設計規約〕を含む。Phase 1 でロード、Phase 4 で準拠）
  - `chapter_map_path`: `~/reverse-docs-skills/shared/references/chapter-map.md`（章の役割キー→§対応表）
