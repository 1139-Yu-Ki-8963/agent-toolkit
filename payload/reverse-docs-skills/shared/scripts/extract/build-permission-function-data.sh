#!/usr/bin/env bash
# permission-matrix.json の features[] を権限機能マトリクス用JSONへ決定的に変換する。
set -euo pipefail

self_test() {
  local script="$0" tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/permission-function-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN
  jq -n '{roles:["member","admin"],features:[
    {unitKey:"write",crud:{admin:"CRU",member:"R"}},
    {unitKey:"read",crud:{admin:"R"}}
  ]}' > "$tmp/in.json"
  bash "$script" "$tmp/in.json" "$tmp/a.json" \
    --generated-at 2026-07-28T00:00:00Z \
    --manifest-content-hash aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  bash "$script" "$tmp/in.json" "$tmp/b.json" \
    --generated-at 2026-07-28T00:00:00Z \
    --manifest-content-hash aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  cmp "$tmp/a.json" "$tmp/b.json"
  jq -e '
    .roles == [{key:"admin",name:"admin"},{key:"member",name:"member"}]
    and .functions == [
      {functionKey:"read",functionName:"read",category:"",permissions:{admin:"-R--",member:"----"}},
      {functionKey:"write",functionName:"write",category:"",permissions:{admin:"CRU-",member:"-R--"}}
    ]
    and .manifestContentHash == ("a"*64)
  ' "$tmp/a.json" >/dev/null
  if jq '.features += [.features[0]]' "$tmp/in.json" > "$tmp/bad.json" \
    && bash "$script" "$tmp/bad.json" "$tmp/bad-out.json" \
      --generated-at 2026-07-28T00:00:00Z \
      --manifest-content-hash aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
      >/dev/null 2>&1; then
    echo "FAIL: duplicate feature accepted" >&2
    return 1
  fi
  echo "self-test 全項目 PASS"
}

if [ "${1:-}" = "--self-test" ]; then self_test; exit $?; fi

usage="Usage: build-permission-function-data.sh <permission-matrix.json> <output.json> --generated-at <iso8601> --manifest-content-hash <sha256>"
input="${1:-}"; output="${2:-}"
[ -n "$input" ] && [ -n "$output" ] || { echo "$usage" >&2; exit 1; }
shift 2
generated_at=""; content_hash=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --generated-at) generated_at="${2:-}"; shift 2 ;;
    --manifest-content-hash) content_hash="${2:-}"; shift 2 ;;
    *) echo "$usage" >&2; exit 1 ;;
  esac
done
[ -f "$input" ] && jq empty "$input" >/dev/null 2>&1 || { echo "ERROR: invalid input" >&2; exit 1; }
[ -n "$generated_at" ] || { echo "ERROR: --generated-at is required" >&2; exit 1; }
printf '%s' "$content_hash" | grep -Eq '^[0-9a-f]{64}$' \
  || { echo "ERROR: invalid manifest content hash" >&2; exit 1; }

jq -e '
  (.roles | type == "array" and all(.[]; type == "string" and length > 0))
  and (.features | type == "array")
  and ([.roles[]] | length == (unique | length))
  and ([.features[].unitKey] | length == (unique | length))
  and all(.features[];
    (.unitKey | type == "string" and length > 0)
    and (.crud | type == "object")
    and all(.crud | to_entries[];
      (.key | type == "string")
      and (.value | type == "string" and test("^[CRUD]*$"))
      and ((.value | split("") | length) == (.value | split("") | unique | length))
    )
  )
' "$input" >/dev/null || { echo "ERROR: permission matrix schema invalid" >&2; exit 1; }

mkdir -p "$(dirname "$output")"
tmp_output="$(mktemp "$(dirname "$output")/.permission-function.XXXXXX")"
trap 'rm -f "$tmp_output"' EXIT
jq -S \
  --arg generatedAt "$generated_at" \
  --arg manifestContentHash "$content_hash" '
  def bytesort: sort;
  def expand:
    . as $v | ["C","R","U","D"]
    | map(. as $letter | if ($v | contains($letter)) then $letter else "-" end)
    | join("");
  (.roles | bytesort) as $roles
  | {
      generatedAt: $generatedAt,
      manifestContentHash: $manifestContentHash,
      roles: [$roles[] | {key: ., name: .}],
      functions: [
        .features[] |
        {
          functionKey: .unitKey,
          functionName: .unitKey,
          category: "",
          permissions: (
            .crud as $crud
            | [$roles[] | {key: ., value: (($crud[.] // "") | expand)}]
            | from_entries
          )
        }
      ] | sort_by(.functionKey)
    }
' "$input" > "$tmp_output"
mv "$tmp_output" "$output"
trap - EXIT
echo "OK: wrote $output" >&2
