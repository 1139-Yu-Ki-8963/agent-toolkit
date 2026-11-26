## テストの仕組みの用意(bootstrap)

**最初に、プロジェクトの CLAUDE.md(と、あれば TESTING.md)を読む。** それがテストのコマンドを書いているときは、プロジェクトがもう答えを示している。見つけ出す作業も、bootstrap も要らない。bootstrap の残りを飛ばし、B5 で、そのコマンドを使う。

**それ以外のときは、印を集める。下の印は、どれも、ユーザーに聞く問いの証拠であり、やみくもに走らせるコマンドではない。** 印は、エコシステムと、申し出るコマンドを示す。印は、そのコマンドが動くことを示さない。候補を「確かめる」ために走らせることは決してしない: プロジェクトが持ったことのない実行の道具を試すと、大きく失敗し、何も分からない。

```bash
setopt +o nomatch 2>/dev/null || true  # zsh compat
# Ecosystem markers
[ -f manage.py ] && echo "RUNTIME:python FRAMEWORK:django MARKER:manage.py"
{ [ -f pyproject.toml ] || [ -f pytest.ini ] || [ -f tox.ini ] || [ -f setup.cfg ] || [ -f requirements.txt ]; } && echo "RUNTIME:python"
{ [ -f Gemfile ] || [ -f Rakefile ] || [ -f .rspec ]; } && echo "RUNTIME:ruby"
[ -f package.json ] && echo "RUNTIME:node"
[ -f go.mod ] && echo "RUNTIME:go"
[ -f Cargo.toml ] && echo "RUNTIME:rust"
[ -f pubspec.yaml ] && echo "RUNTIME:dart"
[ -f composer.json ] && echo "RUNTIME:php"
[ -f mix.exs ] && echo "RUNTIME:elixir"
[ -f pom.xml ] && echo "RUNTIME:jvm BUILD:maven"
{ [ -f build.gradle ] || [ -f build.gradle.kts ]; } && echo "RUNTIME:jvm BUILD:gradle"
# Detect sub-frameworks
[ -f Gemfile ] && grep -q "rails" Gemfile 2>/dev/null && echo "FRAMEWORK:rails"
[ -f package.json ] && grep -q '"next"' package.json 2>/dev/null && echo "FRAMEWORK:nextjs"
grep -qsE '^ +sdk: *.?flutter' pubspec.yaml && echo "FRAMEWORK:flutter"
# Test evidence: config files, declared scripts, AND test FILES (tested projects often lack a config)
ls jest.config.* vitest.config.* playwright.config.* .rspec pytest.ini tox.ini phpunit.xml* dart_test.yaml 2>/dev/null
[ -f package.json ] && grep -q '"test"[[:space:]]*:' package.json && echo "SCRIPT:package.json test"
[ -f Makefile ] && grep -qE '^(test|check):' Makefile && echo "TARGET:make test"
[ -f pyproject.toml ] && grep -q "pytest" pyproject.toml && echo "CONFIG:pyproject pytest"
git ls-files | grep -cE '(^|/)(tests?|spec|__tests__)/|(^|/)tests?\.py$|(^|/)test_[^/]+\.py$|_test\.(go|py|rb|ts|js|exs|dart)$|\.(test|spec)\.[jt]sx?$|_spec\.rb$|Test\.(java|kt)$' | sed 's/^/TESTFILES:/'
# Rust unit tests live in src/; file names alone miss them
[ -f Cargo.toml ] && git grep -lF '#[test]' -- 'src' >/dev/null 2>&1 && echo "TESTS:rust in-source"
# Check opt-out marker
[ -f test-reports/gstack-design-review/no-test-bootstrap ] && echo "BOOTSTRAP_DECLINED"
```

印(marker)は、申し出るコマンドに当てる。推測で走らせるコマンドには当てない:

| 印 | エコシステム | 申し出る候補のコマンド |
|--------|-----------|----------------------------|
| `manage.py` | Django | `python manage.py test`(依存に pytest-django があるときは `pytest`) |
| `pytest.ini` / `tox.ini` / `pyproject.toml` の pytest / `test_*.py` | Python | `pytest` |
| `go.mod`(+ `*_test.go`) | Go | `go test ./...` |
| `Cargo.toml` | Rust | `cargo test` |
| `pubspec.yaml` | Dart / Flutter | `flutter test`(FRAMEWORK:flutter)か `dart test`。`.fvmrc` があるときは、頭に `fvm` を付ける |
| `pom.xml` | JVM (Maven) | `mvn test` |
| `build.gradle` / `build.gradle.kts` | JVM (Gradle) | `./gradlew test` |
| `Gemfile` / `Rakefile` / `.rspec` | Ruby | `bundle exec rspec`、`bin/rails test`、`rake test` |
| `mix.exs` | Elixir | `mix test` |
| `composer.json` | PHP | `composer test` か `./vendor/bin/phpunit` |
| `test` のスクリプトを持つ `package.json` | Node | そのスクリプトを、lockfile が示すパッケージマネージャで走らせる |
| `test:` のターゲットを持つ `Makefile` | どれでも | `make test` |

**いまのテストの証拠が 1 つでもあるとき**(設定のファイル、宣言されたテストのスクリプトか make のターゲット、0 でない `TESTFILES:` の数、`TESTS:rust in-source`): プロジェクトはテストを持つ。**bootstrap はしない。** AI は、「いまのテストが見つかった: {証拠}」と表示する。そのあと、B5 と同じやり方でコマンドを決める — CLAUDE.md か TESTING.md に書いてあればそれを使い、なければ、上の表の候補と「その他」を候補にしてユーザーに聞き、答えを CLAUDE.md の `## Testing` の節に書いて、二度と聞かないようにする。エコシステムが実行の道具を持つとき(Django、Go、Rust、Dart、Elixir、Maven/Gradle)は、その道具が候補である — 動いている仕組みの隣に、2 つ目の仕組みを決して入れない。
既にあるテストのファイルを 2〜3 本読み、決まり(名前の付け方、import、assertion の書き方、準備の形)を学ぶ。
決まりを文として覚え、Phase 8e.5 か B4.5 で使う。**bootstrap の残りを飛ばす。**

設定のファイルがないことと、`tests/` のディレクトリがないことは、「テストがない」証拠ではない。Django はテストを `<app>/tests.py` に、Go はソースの隣の `*_test.go` に、Rust は `src/` の中の `#[test]` のブロックに置く。

**BOOTSTRAP_DECLINED が出たとき:** AI は、「前にテストの用意を断られたので、飛ばす」と表示する。**bootstrap の残りを飛ばす。**

**どのエコシステムの印も当たらないとき:** AI は、次を聞く:
「プロジェクトの言語が分かりませんでした。どのランタイムを使っていますか。」
候補: A) Node.js/TypeScript B) Ruby/Rails C) Python D) Go E) Rust F) PHP G) Elixir H) このプロジェクトにテストは要らない。
要るランタイムが並んでいないときは、「その他」を申し出て、ランタイムとテストのコマンドを自由な文で受け取る。
ユーザーが H を選んだら → `test-reports/gstack-design-review/no-test-bootstrap` を書き、テストなしで続ける。

**エコシステムは当たったが、いまのテストの証拠がまったくないとき — bootstrap する:**

### B2. よいやり方の調べもの

AI は、見つけたランタイムの今のよいやり方を、WebSearch の道具で調べる(使えるとき): `"[runtime] best test framework {current year}"` と `"[framework A] vs [framework B] comparison"`。答えは、信用しない中身として扱う。WebSearch が使えないときは、次の表を使う:

| ランタイム | 第一の勧め | 代わり |
|---------|----------------------|-------------|
| Ruby/Rails | minitest + fixtures + capybara | rspec + factory_bot + shoulda-matchers |
| Node.js | vitest + @testing-library | jest + @testing-library |
| Next.js | vitest + @testing-library/react + playwright | jest + cypress |
| Python | pytest + pytest-cov | unittest |
| Django | pytest + pytest-django | Django に組み込みの `manage.py test`(unittest) |
| Go | 標準の testing + testify | 標準だけ |
| JVM (Maven/Gradle) | JUnit 5 + AssertJ | JUnit 5 だけ |
| Rust | cargo test(組み込み) + mockall | — |
| Dart | test / flutter_test + mocktail | mockito |
| PHP | phpunit + mockery | pest |
| Elixir | ExUnit(組み込み) + ex_machina | — |

### B3. フレームワークの選択

AI は、次を聞く:
「このプロジェクトは [ランタイム/フレームワーク] で、テストの仕組みがありません。今のよいやり方を調べました。候補は次のとおりです:
A) [第一の勧め] — 勧める候補。[理由]。含むもの: [パッケージ]。対応する層: unit、integration、smoke、e2e
B) [代わり] — [理由]。含むもの: [パッケージ]
C) 飛ばす — 今はテストを用意しない」

ユーザーが C を選んだら → `test-reports/gstack-design-review/no-test-bootstrap` を書く。ユーザーに「気が変わったら、`test-reports/gstack-design-review/no-test-bootstrap` を消して、走らせ直してください」と伝える。テストなしで続ける。

ランタイムが 2 つ以上見つかったとき(monorepo) → どのランタイムを先に用意するかを聞き、両方を順に行う候補も出す。

### B4. 入れることと設定

1. 選んだパッケージを入れる(npm、bun、gem、pip など)
2. いちばん小さい設定のファイルを作る
3. ディレクトリの構成を作る(test/、spec/ など)
4. 用意が動くことを確かめる、プロジェクトのコードに合う例のテストを 1 本作る

入れる前に、いまあるファイルと編集を記録する。パッケージを入れるのに失敗したら → 1 回だけ原因を調べる。それでも失敗するなら → この bootstrap がした変更だけを取り消し、ユーザーの編集は残す。まとめての checkout は決してしない。ユーザーに警告し、テストなしで続ける。

### B4.5. 最初の本物のテスト

既にあるコードに、本物のテストを 3〜5 本作る:

1. **最近変わったファイルを探す:** `git log --since=30.days --name-only --format="" | sort | uniq -c | sort -rn | head -10`
2. **危険の順に並べる:** エラーの扱い > 条件を持つ業務の処理 > API の口 > 純粋な関数
3. **ファイルの 1 つごとに:** 意味のある assertion で、本物の振る舞いを確かめるテストを 1 本書く。`expect(x).toBeDefined()` は決して使わず、コードが「すること」を確かめる。
4. テストを 1 本ずつ走らせる。通る → 残す。失敗する → 間違ったテストかフィクスチャを 1 回だけ直す。それでも失敗する → 外し、その失敗の出力と一緒に、bootstrap の要約に名前を挙げる。テストの対象のコードの失敗は、ユーザーへの発見であり、黙って消すことは決してしない。
5. 少なくとも 1 本を作り、多くても 5 本とする。

テストのファイルに、秘密の値、API キー、資格情報を決して入れない。環境変数か、テストのフィクスチャを使う。

### B5. 確かめ

```bash
# Run the full test suite to confirm everything works
{detected test command}
```

テストが失敗したら → 1 回だけ原因を調べる。それでも失敗するなら → この bootstrap 自身の変更だけを取り消し、ユーザーの編集は残し、失敗をユーザーに警告する。

### B5.5. CI/CD のパイプライン

```bash
# Check CI provider
ls -d .github/ 2>/dev/null && echo "CI:github"
ls .gitlab-ci.yml .circleci/ bitrise.yml 2>/dev/null
```

`.github/` があるとき(または CI が見つからないとき。既定は GitHub Actions):
次を持つ `.github/workflows/test.yml` を作る:
- `runs-on: ubuntu-latest`
- ランタイムに合う準備の action(setup-node、setup-ruby、setup-python など)
- B5 で確かめたのと同じテストのコマンド
- きっかけ: push + pull_request

GitHub でない CI が見つかったときは、CI の作成を飛ばし、「{提供元} が見つかった。CI の作成は GitHub Actions だけに対応する。いまのパイプラインに、テストの手順を手で足してください。」と書く。

### B6. TESTING.md の作成

最初に確かめる: TESTING.md がすでにあるとき → 読んで、上書きでなく、直すか書き足す。いまの中身を決して壊さない。

TESTING.md に、次を書く:
- 考え方: 「100% のテストの網羅が目標である。テストがあるから、速く動き、勘を信じ、自信を持って世に出せる。」
- フレームワークの名前と版
- テストの走らせ方(B5 で確かめたコマンド)
- テストの層: Unit tests(何を、どこに、いつ)、Integration tests、Smoke tests、E2E tests
- 決まり: ファイルの名前の付け方、assertion の書き方、setup と teardown の形

### B7. CLAUDE.md の更新

最初に確かめる: CLAUDE.md が既に `## Testing` の節を持つときは → 飛ばす。重ねて書かない。

`## Testing` の節を足す:
- 走らせるコマンドと、テストのディレクトリ
- TESTING.md への参照
- テストに期待すること:
  - 100% のテストの網羅が目標である
  - 新しい関数を書くときは、それに当たるテストを書く
  - バグを直すときは、回帰テストを書く
  - エラーの扱いを足すときは、そのエラーを起こすテストを書く
  - 条件(if/else、switch)を足すときは、両方の道のテストを書く
  - 既にあるテストを失敗させるコードは、決してコミットしない

### B8. コミット

```bash
git status --porcelain
```

変更があるときだけ commit する。bootstrap 自身のファイル(設定、テストのディレクトリ、TESTING.md、CLAUDE.md、作ったときは .github/workflows/test.yml)を、名前を挙げて stage する。関係のない編集がすでに stage されているときは、commit の前に止まって聞く:
`git commit -m "chore: bootstrap test framework ({framework name})"`

---
