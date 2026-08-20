# Phase 5 業務語彙検査

## 読み込み時点

このファイルは Phase 1 の開始時に必ず Read する。選択対象と期待台帳を作る前に、台帳名・導出規則・検証関数を読み込む。

Phase 5 の実行直前にも必ず Read する。ここにある関数をその Bash セッション内で定義し、検査1から検査9まで同じセッションで順番に実行する。

## 永続ファイル

output-layout の `recordsRoot` 配下に次を置く。`recordsRoot` の既定値は `docs/tasks/work-records` である。

| ファイル | 内容 |
|---|---|
| `api-basic-phase5-selection.json` | 選択範囲と `unitKey` を持つJSONオブジェクト |
| `api-basic-phase5-expected.tsv` | マニフェストと選択JSONから導出した期待対象 |
| `api-basic-phase5-generated.tsv` | Phase 3で実際に生成した対象 |
| `api-basic-phase5-attempt.txt` | Phase 5の試行回数 |

選択JSONは `{"scope":"all"|"selected","unitKeys":[...]}` とする。TSVはヘッダなしとし、各行を `<encoded unitKey>\t<API基本設計書の絶対パス>` とする。`encoded unitKey` は jq の `@tsv` で符号化した値である。

## 共通関数

Phase 1とPhase 5は、それぞれのBashセッションで次の関数を定義する。

```bash
derive_phase5_expected_targets() {
  manifest_path="$1"
  selection_path="$2"
  output_dir_path="$3"
  api_unit_root="$4"
  expected_targets_path="$5"

  case "$output_dir_path" in
    /*) ;;
    *)
      printf 'ERROR: output_dirが絶対パスではありません: %s\n' \
        "$output_dir_path" >&2
      return 1
      ;;
  esac

  jq -er \
    --slurpfile selected "$selection_path" \
    --arg output_dir "$output_dir_path" \
    --arg api_unit_root "$api_unit_root" '
      def safe_unit_key:
        explode
        | map(if . == 47 or . < 32 or . == 127 then 45 else . end)
        | implode;
      if ($selected | length) == 1
        then .
        else error("選択JSONはtop-level JSONを1件だけ持つ必要があります")
        end
      | ($selected[0]) as $selection
      | if ($selection | type) == "object"
          and ($selection.scope == "all" or $selection.scope == "selected")
          and (($selection.unitKeys | type) == "array")
        then .
        else error("選択JSONの構造が不正です")
        end
      | ($selection.unitKeys) as $keys
      | [.units[].unitKey] as $manifest_keys
      | if ($manifest_keys | all(.[]; type == "string" and length > 0))
          and (($manifest_keys | unique | length) == ($manifest_keys | length))
        then .
        else error("マニフェストのunitKeyが空、文字列以外、または重複です")
        end
      | if ($keys | type) != "array" or ($keys | length) == 0
        then error("選択unitKeyが0件または配列ではありません")
        else .
        end
      | if ($keys | all(.[]; type == "string" and length > 0))
        then .
        else error("選択unitKeyに空値または文字列以外があります")
        end
      | if ($keys | unique | length) == ($keys | length)
        then .
        else error("選択unitKeyが重複しています")
        end
      | if $selection.scope == "all"
          and (($keys | sort) != ($manifest_keys | sort))
        then error("scope=allのunitKey集合がマニフェスト全件と一致しません")
        else .
        end
      | [.units[] | select(.unitKey as $key | $keys | index($key))] as $units
      | if ($units | length) == ($keys | length)
        then .
        else error("選択unitKeyとマニフェストが1対1ではありません")
        end
      | $keys[] as $key
      | ($units | map(select(.unitKey == $key)) | .[0]) as $unit
      | (($unit.unitId // "")
          | if type == "string" then . else error("unitIdが文字列ではありません") end
        ) as $unit_id
      | (if $unit_id != "" then $unit_id else ($key | safe_unit_key) end) as $identifier
      | [
          $key,
          ($output_dir + "/" + $api_unit_root + "/api-" + $identifier
            + "/基本設計/API基本設計書.md")
        ]
      | @tsv
    ' "$manifest_path" > "$expected_targets_path"
}

validate_phase5_targets() {
  ledger_path="$1"
  ledger_label="$2"

  if ! test -f "$ledger_path"; then
    printf 'ERROR: %sが存在しません: %s\n' "$ledger_label" "$ledger_path" >&2
    return 1
  fi

  if ! awk -F '\t' '
    NF != 2 || $1 == "" || $2 == "" || $2 !~ /^\// { invalid = 1 }
    {
      unit_key_count[$1] += 1
      path_count[$2] += 1
    }
    END {
      for (key in unit_key_count) {
        if (unit_key_count[key] > 1) invalid = 1
      }
      for (path in path_count) {
        if (path_count[path] > 1) invalid = 1
      }
      exit invalid ? 1 : 0
    }
  ' "$ledger_path"; then
    printf 'ERROR: %sの列、空値、絶対パス、または重複が不正です: %s\n' \
      "$ledger_label" "$ledger_path" >&2
    return 1
  fi
}

append_phase5_generated_target() {
  generated_targets_path="$1"
  unit_key="$2"
  design_doc_path="$3"

  jq -rn --arg key "$unit_key" --arg path "$design_doc_path" \
    '[$key, $path] | @tsv' >> "$generated_targets_path"
}

validate_phase5_attempt_file() {
  attempt_path="$1"
  awk 'NR != 1 || $0 !~ /^(0|1|2)$/ { invalid = 1 }
    END { exit (NR == 1 && !invalid) ? 0 : 1 }' "$attempt_path"
}

run_phase5_gate() {
  for phase5_check_number in 1 2 3 4 5 6 7 8 9; do
    phase5_check_callback="run_phase5_check${phase5_check_number}"
    : > "$phase5_check_log_path"
    if ! declare -F "$phase5_check_callback" >/dev/null; then
      printf 'ERROR: 検査%sのcallbackが未定義です: %s\n' \
        "$phase5_check_number" "$phase5_check_callback" \
        > "$phase5_check_log_path"
      report_phase5_failure \
        "検査${phase5_check_number}を実行できません。Phase 3へ差し戻します" \
        "$phase5_check_log_path"
      return 1
    fi
    if ! "$phase5_check_callback" > "$phase5_check_log_path" 2>&1; then
      report_phase5_failure \
        "検査${phase5_check_number}が不合格です。Phase 3へ差し戻します" \
        "$phase5_check_log_path"
      return 1
    fi
    cat "$phase5_check_log_path"
  done
  printf 'status=DONE\n'
}
```

`unitId` が非空なら出力識別子にその値を使う。空なら `unitKey` の `/` と制御文字を `-` に置換して使う。

## 台帳作成の手順

1. `unit_keys` が未指定なら、マニフェストの全 `unitKey` から `{"scope":"all","unitKeys":[...]}` を機械生成する。指定時は引数JSONから `{"scope":"selected","unitKeys":[...]}` を機械生成する。
2. `derive_phase5_expected_targets` で保存済み期待台帳を作る。
3. 期待台帳が1件以上で、対象件数と一致することを確認する。
4. `validate_phase5_targets` で列・空値・絶対パス・各列の重複を検査する。
5. 生成台帳を0バイト、試行回数を `0` と改行で初期化する。Phase 3では、終了値0と出力ファイルの実在を確認した直後に `append_phase5_generated_target` を使う。期待台帳と生成台帳の `unitKey` は同じ `@tsv` 符号化を経由させる。

不成立なら `status=ERROR` とし、Phase 1で停止する。

## 検査1の関数

検出式はコード構文に限定する。通常の業務文に現れうる単語だけでは検出しない。

```bash
business_vocabulary_pattern='interface[[:space:]]+[A-Za-z_][A-Za-z0-9_]*|\bclass[[:space:]]+[A-Za-z_][A-Za-z0-9_]*([[:space:]]*\([^)]*\))?[[:space:]]*:|\bdef[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(|(^|[(,]|[-*+][[:space:]]+|\|[[:space:]]*|>[[:space:]]*|`[[:space:]]*)[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:[[:space:]]*((([A-Za-z_][A-Za-z0-9_]*\.)*[A-Z][A-Za-z0-9_]*)|str|int|float|bool|dict|list|tuple|set|bytes|Any|Optional)([[:space:]]|,|\)|=|\[|\||`|$)|\)[[:space:]]*->[[:space:]]*[A-Za-z_][A-Za-z0-9_.]*|\bsub[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(\{|\(|;)|: *(string|number|boolean)\b|\bstyled-components\b|\bFastAPI\b|\bExpress\b|@(app|router)\.[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(|\.(py|pl|pm|cgi)\b|api-manifest|unitId|unitKey|ioSummary|authRequired|dispatch-entry'

run_business_vocabulary_check() {
  design_doc_path="$1"
  if findings="$(grep -nE "$business_vocabulary_pattern" "$design_doc_path")"; then
    grep_status=0
  else
    grep_status=$?
  fi

  case "$grep_status" in
    0)
      finding_count="$(printf '%s\n' "$findings" | awk 'NF { count += 1 } END { print count + 0 }')"
      printf 'FAIL: %s: %s件\n%s\n' "$design_doc_path" "$finding_count" "$findings"
      return 1
      ;;
    1)
      printf 'PASS: %s: 0件\n' "$design_doc_path"
      return 0
      ;;
    *)
      printf 'ERROR: %s: grep終了値=%s\n' "$design_doc_path" "$grep_status" >&2
      return 1
      ;;
  esac
}

run_business_vocabulary_checks() {
  expected_targets_path="$1"
  generated_targets_path="$2"

  if ! validate_phase5_targets "$expected_targets_path" '期待台帳'; then
    return 1
  fi
  if ! validate_phase5_targets "$generated_targets_path" '生成台帳'; then
    return 1
  fi
  if ! test -s "$expected_targets_path"; then
    printf 'ERROR: 期待台帳が0件です: %s\n' "$expected_targets_path" >&2
    return 1
  fi
  if ! cmp -s \
    <(LC_ALL=C sort "$expected_targets_path") \
    <(LC_ALL=C sort "$generated_targets_path"); then
    printf 'ERROR: 期待台帳と生成台帳が一致しません\n' >&2
    return 1
  fi

  while IFS=$'\t' read -r unit_key design_doc_path; do
    if ! test -f "$design_doc_path"; then
      printf 'ERROR: 生成物が存在しません: %s: %s\n' \
        "$unit_key" "$design_doc_path" >&2
      return 1
    fi
  done < "$generated_targets_path"

  business_vocabulary_check_passed=true
  while IFS=$'\t' read -r unit_key design_doc_path; do
    if ! run_business_vocabulary_check "$design_doc_path"; then
      business_vocabulary_check_passed=false
    fi
  done < "$generated_targets_path"

  test "$business_vocabulary_check_passed" = true
}
```

## 単一Bashの実行契約

Phase 5の開始時に、試行回数を永続ファイルから読み、1増やして書き戻す。値は `0`、`1`、`2` のいずれかだけを受け付ける。

fresh期待台帳と検査ログは `recordsRoot` 内へ `mktemp` で作る。両方を同じtrapで削除する。

```bash
phase5_records_root='<output_dir>/<recordsRoot>'
phase5_selection_path="$phase5_records_root/api-basic-phase5-selection.json"
phase5_expected_targets_path="$phase5_records_root/api-basic-phase5-expected.tsv"
phase5_generated_targets_path="$phase5_records_root/api-basic-phase5-generated.tsv"
phase5_attempt_path="$phase5_records_root/api-basic-phase5-attempt.txt"

if ! validate_phase5_attempt_file "$phase5_attempt_path"; then
  printf 'status=ERROR\nhint=Phase 5試行回数は0、1、2のいずれか1行である必要があります\n'
  exit 1
fi
IFS= read -r phase5_previous_attempt < "$phase5_attempt_path"
phase5_attempt=$((phase5_previous_attempt + 1))
printf '%s\n' "$phase5_attempt" > "$phase5_attempt_path"

phase5_fresh_expected_path="$(
  mktemp "$phase5_records_root/api-basic-phase5-fresh-expected.XXXXXX"
)" || exit 1
phase5_check_log_path="$(
  mktemp "$phase5_records_root/api-basic-phase5-check.XXXXXX"
)" || exit 1
cleanup_phase5_temporary_files() {
  rm -f -- "$phase5_fresh_expected_path" "$phase5_check_log_path"
}
trap cleanup_phase5_temporary_files EXIT HUP INT TERM

emit_phase5_hints() {
  failure_summary="$1"
  failure_log_path="$2"
  printf 'hint=%s\n' "$failure_summary"
  if test -s "$failure_log_path"; then
    while IFS= read -r failure_detail || test -n "$failure_detail"; do
      printf 'hint=%s\n' "$failure_detail"
    done < "$failure_log_path"
  fi
}

report_phase5_failure() {
  failure_summary="$1"
  failure_log_path="$2"
  if test "$phase5_attempt" -lt 3; then
    printf 'phase5_result=RETRY\n'
    emit_phase5_hints "$failure_summary" "$failure_log_path"
    return 1
  fi
  printf 'status=ERROR\n'
  emit_phase5_hints "$failure_summary" "$failure_log_path"
  return 1
}

run_phase5_check1() {
  if ! derive_phase5_expected_targets \
    '<api_manifest_path>' "$phase5_selection_path" '<output_dir>' \
    '<apiUnitRoot>' "$phase5_fresh_expected_path"; then
    return 1
  fi
  if ! validate_phase5_targets "$phase5_expected_targets_path" '保存済み期待台帳'; then
    return 1
  fi
  if ! validate_phase5_targets "$phase5_fresh_expected_path" '再導出した期待台帳'; then
    return 1
  fi
  if ! cmp -s \
    <(LC_ALL=C sort "$phase5_expected_targets_path") \
    <(LC_ALL=C sort "$phase5_fresh_expected_path"); then
    printf 'ERROR: 保存済み期待台帳が現在の選択対象と一致しません\n' >&2
    return 1
  fi
  run_business_vocabulary_checks \
    "$phase5_fresh_expected_path" "$phase5_generated_targets_path"
}

if ! run_phase5_gate; then
  exit 1
fi
```

`run_phase5_check2` から `run_phase5_check9` は、SKILL.mdに定義済みの各検査に対応するcallbackとして呼び出し元が定義する。引数なしで呼び、合格時は0、不合格または実行不能時は非0を返す。既存の検査内容はこのreferenceで置き換えない。

`run_phase5_gate` は同じBashセッションで検査1から検査9を順番に呼ぶ。各検査の前に検査ログを0バイトへ切り詰める。不合格時は標準出力と標準エラーを同じログへ捕捉し、共通の `report_phase5_failure` へ検査名とログを渡す。

1回目と2回目は `phase5_result=RETRY` と `hint` を返す。`status=ERROR` と `status=DONE` は返さない。

3回目は `status=ERROR` と `hint` を返す。検査1のhintには、検出ファイル・件数・行、または台帳などの構造エラー詳細が入る。

9つのcallbackがすべて0を返した後だけPhase 5を `completed` にし、`status=DONE` を返す。検査ごとに別のBashを起動してはならない。

## 合成フィクスチャ

次を検収する。

1. 正常文書は検査1が0件になる。
2. `authRequired` 1件は検査1が1件になる。
3. 対象0件は非0になる。
4. 同件数の別対象へ保存済み期待台帳を替えると非0になる。
5. `unitKey` 重複は非0になる。
6. パス重複は非0になる。
7. 相対パスは非0になる。
8. 存在しないパスは非0になる。
9. grep終了値2以上は非0になる。
10. 1回目の不合格はRETRYとhintを返し、ERRORとDONEを返さない。
11. 2回目の不合格もRETRYとhintを返し、ERRORとDONEを返さない。
12. 3回目の不合格はERRORとhintを返し、DONEを返さない。
13. 別Bashでも永続ファイルから同じ対象を復元できる。
14. `unitId` が空の場合は、`unitKey` の禁止文字を安全化したパスを導出する。
15. `interface\tOrder {` を1件検出する。
16. `def update(order: OrderInput) -> OrderResult:` を1件検出する。
17. `@app.patch(...)` を1件検出する。
18. `scope=all` でマニフェスト2件・選択1件なら非0になる。
19. `@router.get(...)` を1件検出する。
20. Pythonの `class OrderService:` を1件検出する。
21. Perlの `sub update_order {` を1件検出する。
22. 制御文字を含む `unitKey` でも、期待台帳と生成台帳の符号化済みキーが一致する。
23. 試行回数ファイルが2行なら、各行が許容値でも非0になる。
24. 9つのcallbackがすべて0を返すと `status=DONE` を1回だけ返す。
25. 行頭の `order: OrderInput` を1件検出する。
26. 行頭の `order_id: str` を1件検出する。
27. `status: authored` は検出0件になる。
28. 箇条書きの `- order: OrderInput` を1件検出する。
29. 表セルの `| order: OrderInput |` を1件検出する。
30. inline codeの `` `order: OrderInput` `` を1件検出する。
31. qualified型の `order: models.OrderInput` を1件検出する。
32. 小文字型名の `interface order {` を1件検出する。
33. Perlの前方宣言 `sub update_order;` を1件検出する。
34. `@router.api_route(...)` を1件検出する。
35. `@app.custom_method(...)` を1件検出する。
36. 選択JSONにtop-level JSONが2件あれば非0になる。
