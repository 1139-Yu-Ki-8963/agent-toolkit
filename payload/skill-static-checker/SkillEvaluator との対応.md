# SkillEvaluator との対応

この文書は、このフォルダの 2 本のスキルが、SkillEvaluator のどの検査を、どこから写したかの記録を持つ。スキルのフォルダの中の文書は、スキルの外のツールとスキルに触れない形で書いており、写し元の記録は、この文書にだけ置く。

## スキルと SkillEvaluator の Tier の対応

| スキル | SkillEvaluator の Tier | 扱わない Tier |
|---|---|---|
| scoring-skill-structure-and-danger | Tier 1(構造と危険の静的チェック) | Tier 2(重複の検査)、Tier 3(スキルを動かして確かめる検査) |
| checking-skill-duplication | Tier 2(重複の検査) | Tier 1、Tier 3 |

- checking-skill-duplication は、SkillEvaluator の Tier 2 と違い、文を数の並びに変える埋め込みで近さを測らない。SkillEvaluator の Tier 2 は、埋め込みのために、外部の AI の提供元に節の本文を送る。このスキルは、手元の文字の近さで候補を挙げる。
- SkillEvaluator の Tier 2 は、`.py`、`.sh`、`.mdc` のファイルも比べる。根拠は、SkillEvaluator の `docs/tier2-reference.mdx` の 149〜156 行目である。

## scoring-skill-structure-and-danger の写し元

### 重さと点数

- 細かい重さ(CRITICAL、HIGH、MEDIUM、LOW、INFO)は、SkillEvaluator の 5 つの重さである。
- SkillEvaluator の品質の検査の error、warning、info は、`validators/quality_score.py` の 445 行目のとおり、HIGH、MEDIUM、LOW に当てる。
- 点数の出し方は、SkillEvaluator の `models/quality.py` と `constants.py` の値を写したものである。合格ラインの 70 点は、QUALITY_DEFAULT_MIN_SCORE である。
- 減点の値は、SkillEvaluator(`src/skillevaluator/`)の値を写したものである。SkillEvaluator が減点の値を持たない項目は、細かい重さごとの既定の値(HIGH は 15、MEDIUM は 10、LOW は 5)とした。
- 区分「助言」を点数と合否に入れないのは、SkillEvaluator の `validators/harness.py` が、自分を助言だけの検査としているためである。
- 構造の合否は、元の `models/result.py` の is_error のとおり、重さ HIGH か CRITICAL の構造の指摘が 1 件でもあれば、点数に関わらず不合格にする。
- 合否は、元のとおり、丸める前の点数で 70 と比べる。表示の点数は、元の Python の round と同じ偶数丸めで、小数点以下 1 桁にする。
- 報告の HTML は、SkillEvaluator の `reporting/html.py` の形をまねる。

| 分野 | SkillEvaluator の分野 |
|---|---|
| 正しさ | correctness |
| 見つけやすさ | discoverability |
| 信頼性 | reliability |
| 効率 | efficiency |

### 構造の静的チェックの項目の写し元

| 節 | 項目 | SkillEvaluator の当たるもの |
|---|---|---|
| フロントマターの項目 | フロントマターの有無 | `validators/schema.py` の frontmatter_format |
| フロントマターの項目 | name と description の有無 | `models/skill.py` の必須の項目 |
| フロントマターの項目 | name の形 | `validators/quality_score.py` の Invalid name format(15 点) |
| フロントマターの項目 | name の予約語 | `config/quality-default.yaml` の reserved_name(15 点) |
| フロントマターの項目 | name とフォルダの名前 | `validators/schema.py` の name_consistency |
| フロントマターの項目 | description の字数 | `models/skill.py` の DESCRIPTION_MAX_LENGTH |
| フロントマターの項目 | XML のタグ | `validators/quality_score.py` の XML tags(15 点) |
| フロントマターの項目 | 同じキー | `validators/schema.py` の duplicate_key |
| フロントマターの項目 | キーの型 | `validators/schema.py` の yaml_syntax |
| フロントマターの項目 | BOM | `validators/schema.py` の manifest_bom |
| フロントマターの項目 | タブの字下げ | `validators/schema.py` の yaml_syntax |
| フロントマターの項目 | alwaysApply と globs | `models/skill.py` の FORBIDDEN_SKILL_FIELDS |
| フロントマターの項目 | metadata.version の形 | `models/skill.py` の SEMVER_RE |
| 本文とフォルダの項目 | 「目的:」の行 | `## Purpose`(5 点) |
| 本文とフォルダの項目 | description の発動する場面 | description の use、when(10 点) |
| 本文とフォルダの項目 | description の短さ | `config/quality-default.yaml` の description_too_short(20 点) |
| 本文とフォルダの項目 | description の一人称と二人称 | first/second person(15 点) |
| 本文とフォルダの項目 | description の曖昧な語 | vague words(15 点) |
| 本文とフォルダの項目 | description の広い語 | negative triggers(5 点) |
| 本文とフォルダの項目 | 「## 前提ツール」の章 | `## Prerequisites`(5 点) |
| 本文とフォルダの項目 | 「## phase」の章 | `## Instructions`(schema の MEDIUM) |
| 本文とフォルダの項目 | 「## 使用するスクリプト」の章 | `## Available Scripts`(10 点) |
| 本文とフォルダの項目 | 使用するスクリプトの表 | No documented scripts in table format(10 点) |
| 本文とフォルダの項目 | scripts の中身 | scripts/ exists but contains no files(10 点) |
| 本文とフォルダの項目 | 「## できないこと」の章 | `## Limitations`(5 点) |
| 本文とフォルダの項目 | 「## 使い方の例」の章 | No examples provided(5 点) |
| 本文とフォルダの項目 | エラーの扱いの語 | error handling の mentioned(10 点) |
| 本文とフォルダの項目 | 使わない語 | complex/corporate language(5 点) |
| 本文とフォルダの項目 | 行の繰り返し | High line repetition(10 点) |
| 本文とフォルダの項目 | references の中の文書でないもの | Non-doc file in references/(5 点) |
| 本文とフォルダの項目 | リファレンスのファイル名 | Non-descriptive filename(5 点) |
| 本文とフォルダの項目 | リファレンスの参照の深さ | Deeply nested references(10 点) |
| 本文とフォルダの項目 | SKILL.md が指さないリファレンス | 規約 skill-writing-rule の「リファレンス」規則 2。減点は Deeply nested references と同じ |
| 本文とフォルダの項目 | README.md へのリンク | SKILL.md references README.md(5 点) |
| 本文とフォルダの項目 | 相対リンクの先 | `validators/hygiene.py` の Dead link |
| 本文とフォルダの項目 | パスの区切り | Windows-style paths(10 点) |
| 本文とフォルダの項目 | スクリプトのシェバンと実行権限 | 規約 skill-writing-rule の「スキルのフォルダが持つもの」規則 1 |
| 本文とフォルダの項目 | スクリプトの説明書とテスト | 規約 skill-writing-rule の「スクリプト」規則 1 |
| 本文とフォルダの項目 | 部品の版の固定 | `validators/hygiene.py` の Unpinned |
| 本文とフォルダの項目 | スキルのフォルダが持つもの | `validators/schema.py` の unexpected_file |
| 道具ごとの読み込みの項目 | 同じ名前のスキル | `harness/overlay.py` の duplicate_name と user copy、`harness/profiles/claude-code.yaml` の CC-PRECEDENCE と CC-USER-COPY |
| 参考の数の値 | SKILL.md の行数 | `constants.py` の QUALITY_MAX_BODY_LINES |
| 参考の数の値 | SKILL.md の推定トークン | `config/quality-default.yaml` の token_budget |
| 参考の数の値 | SKILL.md の大きさ | `validators/schema.py` の manifest_size |
| 参考の数の値 | SKILL.md の最も長い行の字数 | 道具ごとの読み込みの上限 |
| 参考の数の値 | description の字数 | `config/quality-default.yaml` の description_too_long |
| 参考の数の値 | name の字数 | `validators/quality_score.py` の Skill name very short |

参考の数の上限は、SkillEvaluator の既定の値である。

### 日本語の見出しと語の写し元

| SkillEvaluator の見出し | 日本語のスキルの見出しか行 |
|---|---|
| `## Purpose` | 「目的:」の行 |
| `## Prerequisites` | 「## 前提ツール」 |
| `## Instructions`、`## Usage` | 「## phase <番号> <名前>」 |
| `## Available Scripts` | 「## 使用するスクリプト」 |
| `## Limitations` | 「## できないこと」 |
| `## Examples` | 「## 使い方の例」 |

`## Troubleshooting` に当たる章は求めない。

| 日本語の語 | SkillEvaluator の当たる語 |
|---|---|
| あなた、私、私たち | i can、you should、your など |
| いろいろ、様々 | something、various など |
| 活用、促進、シナジー、パラダイム | utilize、facilitate、leverage、paradigm、synergy |

### 危険の静的チェックの型の写し元

- 型と重さは、SkillEvaluator(`src/skillevaluator/`)の設定のファイルを写したものである。
- 秘密の値と個人の情報の型: `config/pii_patterns.yaml` と、`validators/secrets.py`(Gitleaks)の重さの決め方
- 見えない文字の型: `config/unicode_smuggle_patterns.yaml` と `validators/unicode_smuggle.py`。紛らわしい空白は、SkillEvaluator でも既定で見ない。
- 危ないコードの型: `config/semgrep_rules.yaml` を node のスクリプトに当てたもの
- 許可するライセンスの一覧: `config/license_config.yaml`
- 部品の脆弱性: SkillEvaluator の `validators/dependencies.py` は Python の部品だけを見るので、npm の部品に置き換えた。
- AI を乗っ取る書き方: SkillEvaluator の `validators/security.py`(SkillSpector)の、AI の推論で見る検査に当たる。

### 2026-11-20 に元に合わせたもの

2026-11-20 に、元のソースとこちらのスクリプトを読み比べ、試しのスキルに動かして、元と違う結果を出す箇所を見つけ、次のとおり元に合わせた。リファレンスどうしの食い違い(スキルのフォルダの直下の LICENSE)は、節「元と違うまま残したもの」に書いた。前の版のこの文書が持っていた「スクリプトの行ごとの写し元」の表は、スクリプトの行が変わったので消した。写し元は、上の節の検査ごとの対応で引く。

- 構造の合否: 重さ HIGH の構造の指摘で不合格にする(`models/result.py`)。
- ライセンス(`validators/license.py`):
  - 制限のある名前を 1 つでも持つ式は、OR でも AND でも重大にする(_license_policy)。
  - -only、-or-later、+、-with-...-exception を外した名前でも比べる(_is_blocked_license)。
  - NOTICE を読まない(_is_license_declaration_filename)。
  - 食い違いと、見分けられない LICENSE と COPYING を重大にする。
  - ファイルのライセンスがフロントマターの式の名前に含まれるときは、食い違いとしない。
  - 読めない式を、重大の「ライセンスの式の誤り」にする(unsupported_license_expression)。
- 秘密の値と個人の情報(`validators/security.py`、`config/pii_patterns.yaml`):
  - 例外の語を、大文字と小文字を区別して比べる(_scan_lines_for_pattern)。型の照合は、大文字と小文字を区別しない。
  - 1 行の候補をすべて見て、除く条件で絞ってから指摘する。
  - exceptions.allowed_paths(/tmp/、/var/tmp/、/opt/、/usr/local/)を、すべての型の例外の語に足す。
  - コメントの行を飛ばす(_comment_line_numbers)。
  - Google の API のキーと AI の API のキー(sk-)に、例外の語(example、test、your)を当てる。
- 危ないコード: `config/semgrep_rules.yaml` の python.sql-query-construction を足す。
- 見えない文字(`validators/unicode_smuggle.py`): 空白だけを隠すタグ文字を重大にしない。3 字以上の連なりを注意にするのは、幅のない文字だけにする。
- 構造(`validators/quality_score.py`):
  - フロントマターの続く行の値を読む。
  - 日本語の名前のパスの区切りも見る(元の Python の \w は Unicode の字に当たる)。
  - XML のタグは、name と description で 1 回ずつ、ほかのキーで 1 回だけ数える。
  - argument-hint の短い引数の書き方を除いてから、タグを調べる(_mask_argument_hint)。
  - description が 20 字より短いときに、見つけやすさから 20 点引く(description_too_short)。
  - 版のセルの逆引用符を外して読む。

### 元と違うまま残したもの

- 元の減点のうち、metadata.author と metadata.tags、英語の動詞の手順、手順の箇条書きの形、20 行より短い本文、スクリプトのエラー処理、name の慣習は、写さない。日本語のスキルの雛形に、当たる決まりがないため。
- 「## 使用するスクリプト」の章は、scripts/ のないスキルにも求める。雛形が、すべてのスキルにこの章を求めるため(scripts/ がなければ「なし」の 1 行)。
- 「## 前提ツール」「## 使用するスクリプト」「## できないこと」の章の中身の検査と、ほかのスキルの文を写したままの章の検査は、元にない。日本語のスキルの雛形のために足した。
- スキルのフォルダの直下の LICENSE、LICENCE、COPYING は、項目「スキルのフォルダが持つもの」で指摘しない。ライセンスの検査が読むファイルのため。元の schema.py は指摘するが、点数に入れない。
- 構造の点数は、フロントマターの形の検査の指摘も入れる。元は、SchemaValidator の指摘を品質の点数に入れない。
- 元にない型を残す: sk-、xox、npm_、AIza、github_pat、gho、ghu、ghr のトークン、日本の電話番号、`~/` で始まるパス、行末の CR。
- 国際の電話番号は、`+` の前が英数字か点のときは除く。日本語の文書の `U+3000` のような書き方を指摘しないため。
- `/Users/<…>` のような山かっこの名前のパスは指摘しない。Linux のホームのパスは、作者ではなく、実行しているユーザーの名前と比べる。
- SPDX の見出しは、ファイルごとに、制限のあるものを指摘する。元は、ほかに手がかりがないときだけ、最も多い値を判定に使う。
- 位置の座標、GUID、版の数字、科学表記の除き方と、Python と YAML のコメントの行の見分け方は、元より簡単な形で近づけている。
- 部品の脆弱性は、元の Python の部品の代わりに、npm の部品を調べる。
- 重複の検査は、元の Tier 2 の埋め込みの代わりに、手元の文字の近さで候補を挙げ、判定者 2 人の多数で決める。そのため、近さの値と線は、元と比べられない。

## checking-skill-duplication で 2026-11-20 に直したもの

- 文字の近さは、丸める前の値で線の 0.60 と比べる。
- 調べるスキルの description を読めないときは、比べるスキルが 0 本でも「調べきれなかった」にする。

## checking-skill-duplication の線を決めた測りの記録

2026-11-19 に、skill-factory の fixing-skill に 4 種類の節を足して、写した節との近さを測った。同じ日に、skill-factory の 4 本のスキル(fixing-skill、drafting-skill-with-template、checking-skill-with-template、publishing-skills-to-public-repo)で近さを測った。値は、checking-skill-duplication のリファレンス `重複の検査の基準.md` の節「線を決めた測りの値」にある。
