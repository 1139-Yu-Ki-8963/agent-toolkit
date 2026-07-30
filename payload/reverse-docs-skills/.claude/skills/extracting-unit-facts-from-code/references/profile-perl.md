# profile-perl: perl プロファイルの再計数パターン

`extracting-unit-facts-from-code` の `profile=perl` 専用リファレンス。`scripts/recount-facts.sh` の Phase 3（独立再計数ゲート）が用いる決定的パターンを1つの表に集約する。`profile=screen` と同じ設計方針（正規表現・awkベースの近似計数。真の構文解析ではない）を、JSX・styled-components・React hooks のような JS/TS 固有構文を持たない言語（Perl相当の構文体系）へ適用する。

対象は再計数（Phase 3）のみ。本スキルの Phase 2（抽出）は現時点で `screen`/`python` の2種のみに対応しており、`perl` の抽出手順（Phase 2）は本ラウンドの対象外（別の改善サイクルで扱う）。すでに `profile: perl` を持つ `facts.yml`（手作業・別ツール由来を含む）を独立再計数で検証したい場合に本プロファイルを使う。

スキーマ本体（YAML構造・必須フィールド・孤児参照定義・normalize規則）は `shared/references/facts-schema.md` を正本とする。本ファイルは「どう独立再計数するか」の手順のみを持つ。

## 分類別再計数パターン

pythonプロファイルと同じ分類語彙（`import`/`function`/`local_assignment`/`external_call`/`exception_handling`/`measurement_pending`）を再利用する。ただし独立実装の方式は異なる（pythonはASTベース、perlはscreenと同じ正規表現ベース）。

| 分類 | Phase 3 独立再計数パターン（`recount-facts.sh` が使う正規表現・数え方） |
|---|---|
| import | 行頭 `^use[ \t]+<識別子>` に一致する行を対象にする。`qw(...)` を伴う場合はその中の空白区切りシンボル数を数える（`use POSIX qw(floor ceil);` は2件）。`qw(...)` を伴わない場合は1件（`use strict;` は1件）。加えて行頭 `^require[ \t]+<識別子>;` の行を1件として数える |
| function | 行頭 `^sub[ \t]+<識別子>` に一致する宣言行を1件として数える（前方宣言・本体ありのいずれも対象） |
| local_assignment | 行頭が `my`/`our`/`local` のいずれかで始まる行を1件として数える（分割代入 `my ($a, $b) = @_;` も1行=1件） |
| external_call | `-><メソッド名>(` 形式（アロー呼出し）と、キーワード（制御構文・宣言語・`my`/`our`/`local`/`use`/`require`/`sub` 等）に一致しない裸の `<識別子>(` 呼出しを合算する。`sub` 宣言行自体は対象外 |
| exception_handling | 行頭 `^eval[ \t]*\{`（eval ブロック開始）と、行頭 `^die[ \t(]`（die 文）を合算する |
| measurement_pending（再計数対象外） | screenプロファイルの⑨と同じ理由（動的値のため独立再計数できない）で対象外とする。空欄率検査（key・evidence）と孤児参照検査のみ本セクションにも適用する |

## 実行

facts.yml不要の軽量モード:

```bash
bash scripts/recount-facts.sh --recount-only --profile perl \
  <target_repo_path> <target_file_paths...>
```

facts.yml突合:

```bash
bash scripts/recount-facts.sh \
  <facts_dir>/facts.yml <target_repo_path> <target_file_paths...>
```

facts.yml の `profile:` フィールドに `perl` を指定していれば、上記コマンド（facts.yml突合形式）は自動的に本プロファイルの再計数パターンを使う。

## 完了条件

- 5分類（`measurement_pending` を除く）の件数が独立再計数と一致する（乖離率5%以内）。
- 全12分類共通の必須フィールド（key・evidence）空欄率が30%以内。
- 孤児参照（evidenceのファイル部分がtarget_file_pathsに含まれない項目）が0件。

## 再計数パターンの既知の限界

- 全パターンは正規表現ベースの近似計数であり、真の構文解析（AST）ではない。pythonプロファイルのようなAST由来の排他分類検査・関数本文網羅検査は持たない（Perl標準ライブラリに決定的なAST解析手段がないため）
- `import` の `qw(...)` 検知は丸括弧区切り（`qw(...)`）のみに対応する。角括弧・波括弧・スラッシュ等の代替デリミタ（`qw[...]`・`qw{...}`・`qw/.../`）には対応しない
- `local_assignment` は行頭が `my`/`our`/`local` で始まる行を機械的に1件と数える近似であり、1行に複数の宣言文が並ぶ場合（`my $a = 1; my $b = 2;` のようなセミコロン区切りの複数文）は1件にしか数えない
- `external_call` は宣言・制御構文の一般的なキーワード一覧をブロックリストとして除外する近似であり、リストに無い予約語やビルトイン関数を業務呼出しと誤検知する可能性がある。プロトタイプ付き `sub` 宣言（`sub foo ($$) { ... }`）は `sub` 判定で対象外にしているため呼出しとして誤検知しない
- `exception_handling` は `eval { ... }` ブロックと `die` 文のみを対象とする。`Try::Tiny` 等のモジュールが提供する `try`/`catch` 構文や `Carp::croak` は対象外（新たに検知が必要になった場合は本節に追記した上でパターンを拡張する）
- 乖離許容5%は近似計数と手動キー付けの粒度差を吸収するための閾値であり、0%一致を保証する設計ではない
