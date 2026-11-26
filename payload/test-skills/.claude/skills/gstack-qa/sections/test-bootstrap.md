# テストの枠組みの準備

AI は、この節を、ユーザーが直接呼んだ実行の、ブラウザの面にだけ使う。機能だけの実行と、報告だけの権限の実行では使わない。

AI は、最初に CLAUDE.md と TESTING.md を読む。文書にテストのコマンドがあるときは、枠組みの準備を飛ばし、そのコマンドを使い、テストを 2〜3 本読む。ないときは、AI は、コマンドを推し量らず、次で証拠を集める。

```bash
setopt +o nomatch 2>/dev/null || true
[ -f manage.py ] && echo "RUNTIME:python FRAMEWORK:django MARKER:manage.py"
for group in 'python:pyproject.toml pytest.ini tox.ini setup.cfg requirements.txt' 'ruby:Gemfile Rakefile .rspec' node:package.json go:go.mod rust:Cargo.toml php:composer.json elixir:mix.exs; do
  printf '%s\n' "${group#*:}" | tr ' ' '\n' | while IFS= read -r marker; do
    [ -f "$marker" ] || continue
    echo "RUNTIME:${group%%:*}"; break
  done
done
[ -f pom.xml ] && echo "RUNTIME:jvm BUILD:maven"
{ [ -f build.gradle ] || [ -f build.gradle.kts ]; } && echo "RUNTIME:jvm BUILD:gradle"
[ -f Gemfile ] && grep -q "rails" Gemfile 2>/dev/null && echo "FRAMEWORK:rails"
[ -f package.json ] && grep -q '"next"' package.json 2>/dev/null && echo "FRAMEWORK:nextjs"
ls jest.config.* vitest.config.* playwright.config.* .rspec pytest.ini tox.ini phpunit.xml* 2>/dev/null
[ -f package.json ] && grep -q '"test"[[:space:]]*:' package.json && echo "SCRIPT:package.json test"
[ -f Makefile ] && grep -qE '^(test|check):' Makefile && echo "TARGET:make test"
[ -f pyproject.toml ] && grep -q "pytest" pyproject.toml && echo "CONFIG:pyproject pytest"
git ls-files | grep -cE '(^|/)(tests?|spec|__tests__)/|(^|/)tests?\.py$|(^|/)test_[^/]+\.py$|_test\.(go|py|rb|ts|js|exs)$|\.(test|spec)\.[jt]sx?$|_spec\.rb$|Test\.(java|kt)$' | sed 's/^/TESTFILES:/'
[ -f Cargo.toml ] && git grep -lF '#[test]' -- 'src' >/dev/null 2>&1 && echo "TESTS:rust in-source"
[ -f test-reports/gstack-qa/no-test-bootstrap ] && echo "BOOTSTRAP_DECLINED"
```

テストの設定、テストのスクリプト、make の target、0 でない TESTFILES、Rust のソースの中のテストのどれかがあるときは、`tests/` がなくても、AI は**枠組みを入れない**。AI は、「Existing tests detected: {証拠}.」と表示し、テストのコマンドを、下の候補と「そのほか」で聞く。AI は、答えのコマンドを CLAUDE.md の `## Testing` に書き、テストを 2〜3 本読んで、名前の付け方、import、アサーション、準備の書き方を確かめ、そこで止まる。本物のテストの横に、2 つ目の枠組みを入れない。

申し出るコマンド: Django は `python manage.py test`(pytest-django とともに pytest)、Python は `pytest`、Ruby は `bundle exec rspec`/`bin/rails test`/`rake test`、Go は `go test ./...`、Rust は `cargo test`、JVM は `mvn test`/`./gradlew test`、PHP は `composer test`/`./vendor/bin/phpunit`、Elixir は `mix test`、Node は lockfile が示すパッケージマネージャで走らせる test のスクリプト、Makefile は `make test` とする。

**BOOTSTRAP_DECLINED のとき:** AI は、そのことを告げて飛ばす。

**ランタイムが分からないとき:** AI は、ランタイムの候補、「そのほかのランタイムかコマンド」、「テストは要らない」で聞く。

**断られたとき:** AI は、どの断りでも、`test-reports/gstack-qa/no-test-bootstrap` を作り、このファイルを消すとまた申し出ることを説明する。

**monorepo のとき:** AI は、どれを先にするかを聞くか、両方を順に行う。

テストの証拠がまったくないときは、AI は、次の表から候補を選ぶ。

| ランタイム | 第一の候補 | ほかの候補 |
|---|---|---|
| Rails | minitest + fixtures + capybara | rspec + factory_bot + shoulda-matchers |
| Node | vitest + @testing-library | jest + @testing-library |
| Next.js | vitest + @testing-library/react + playwright | jest + cypress |
| Python | pytest + pytest-cov | unittest |
| Django | pytest + pytest-django | manage.py test |
| Go | stdlib testing + testify | stdlib |
| JVM | JUnit 5 + AssertJ | JUnit 5 |
| Rust | cargo test + mockall | built-in |
| PHP | phpunit + mockery | pest |
| Elixir | ExUnit + ex_machina | built-in |

**AI は聞いて待つ:** A) 第一の候補、B) ほかの候補(理由、入れるパッケージ、テストの層)、C) 飛ばす。AI は 1 つを勧め、選ばれたものだけを入れる。

## 入れることと確かめること

AI は、今あるファイルと編集を記録する。AI は、承認されたパッケージと、最小の設定とフォルダと、プロジェクトに合ったテストを 1 本入れる。入れるのに失敗したら、AI は 1 回だけ原因を調べる。それでも進めないときは、この実行が入れた変更だけを戻し、ユーザーの編集は残し、テストなしで報告して続ける。AI は、作業ツリー全体の checkout で戻さない。

**最初の本物のテスト:** AI は、`git log --since=30.days --name-only --format="" | sort | uniq -c | sort -rn | head -10` で、よく変わるファイルを見る。AI は、危険の大きい順(エラーの処理 > 条件の分かれ > API > 純粋な関数)に選ぶ。テストは 3〜5 本(最小 1 本、最大 5 本)とし、意味のあるアサーション(`toBeDefined()` でないもの)を持ち、fixture と環境変数を使い、認証情報を使わない。

AI は、テストを 1 本ずつ走らせ、そのあと、確かめたコマンドで全体を走らせる。AI は、準備か fixture の失敗と、欠陥を分ける。誤った fixture は 1 回だけ直す。準備の失敗が続くときは、この実行が入れた変更だけを戻し、報告に残す。**AI は、正しい赤の回帰テストを、黙って消さない。** AI は、テストと証拠を残し、欠陥を SKILL.md の原因の調べと直しの関門に戻す。AI は、壊れた振る舞いを正しいとせず、緑だと言い張らない。

## 仕上げ

AI は、`.github/`、`.gitlab-ci.yml`、`.circleci/`、`bitrise.yml` を見る。GitHub Actions(どれもないときの既定)では、`.github/workflows/test.yml` を作るか広げ、push と pull_request、ubuntu-latest、ランタイムの準備、確かめたコマンドを入れる。今ある workflow は残す。ほかの CI では、テストの手順を手で足すことを報告する。

AI は、TESTING.md を上書きせずに更新する。書くものは、枠組みとバージョン、コマンド、単体、結合、smoke、E2E の層、名前の付け方、アサーション、準備と片付けの書き方、安心してコードを書けるようにするためのテストの網羅 100% の方針とする。CLAUDE.md の `## Testing` は、ないときだけ足し、コマンドとフォルダ、TESTING.md へのリンク、新しい関数、回帰、エラー、条件の両方の分かれをテストすることを書く。AI は、失敗する今のテストをコミットしない。

AI は、`git status --porcelain` を走らせ、この実行が持つ名前のファイルと変更の塊だけを stage する。関係のない stage 済みの変更があるときは止まる。枠組みの準備がうまくいったときは、`chore: bootstrap test framework ({枠組みの名前})` でコミットする。変更がないときは、コミットを飛ばす。
