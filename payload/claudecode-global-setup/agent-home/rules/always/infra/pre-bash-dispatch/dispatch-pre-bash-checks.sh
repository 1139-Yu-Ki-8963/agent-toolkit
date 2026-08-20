#!/usr/bin/env bash

# PreToolUse(Bash) hook: コマンドに応じて命名規則・textlint・安全確認の additionalContext を注入する。

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# node 解決（hook は nvm 未ロードの非対話シェルで走るため多段フォールバック）
# 未解決時は textlint 検査のみ skip する。secret 検出・命名チェックは node 不要で影響なし
_node="$(command -v node 2>/dev/null)"
[ -z "$_node" ] && _node="$(ls -1 "$HOME/.nvm/versions/node"/*/bin/node 2>/dev/null | sort -V | tail -1)"
if [ -z "$_node" ]; then
  for _p in /opt/homebrew/bin/node /usr/local/bin/node; do
    [ -x "$_p" ] && _node="$_p" && break
  done
fi

# プロジェクト辞書の合成: cwd のリポジトリに委譲辞書があれば rulePaths に追記した一時 config を生成
_hook_cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$_hook_cwd" ] && _hook_cwd="$PWD"

. "$HOME/.claude/rules/scoped/agent-config/hooks/shared/transcript-query.sh"

resolve_textlint_config() {
  _rtc_static="$1"
  _rtc_ctx_dir="${2:-$_hook_cwd}"
  _rtc_root=$(git -C "$_rtc_ctx_dir" rev-parse --show-toplevel 2>/dev/null)
  _rtc_proj="${_rtc_root}/.claude/rules/always/review-checklist/text-dictionary/prh.yml"
  if [ -n "$_rtc_root" ] && [ -f "$_rtc_proj" ]; then
    _rtc_tmp=$(mktemp /tmp/textlintrc_merged_XXXXXX.json)
    if jq --arg p "$_rtc_proj" '.rules.prh.rulePaths += [$p]' "$_rtc_static" > "$_rtc_tmp" 2>/dev/null; then
      printf '%s' "$_rtc_tmp"
      return 0
    fi
    rm -f "$_rtc_tmp"
  fi
  printf '%s' "$_rtc_static"
}

# ─────────────────────────────────────────────────────────────
# git commit: textlint (docs)・命名規則・公開可否チェック
# セグメント認識により `git -C <dir> commit` / `cd <dir> && git commit` でも
# 実効コンテキストディレクトリを解決してから検査する。
# ─────────────────────────────────────────────────────────────
resolve_git_ctx_dir "$cmd" "$CMD_CTX_GIT_COMMIT_RE" "$_hook_cwd"
if [ -n "$RGCD_MATCHED_SEG" ]; then
  # 再帰防止
  [ -n "$CLAUDE_HOOK_DICT_RUNNING" ] && exit 0

  _git_ctx_dir="$RGCD_CTX_DIR"
  git_in_ctx() { git -C "$_git_ctx_dir" "$@"; }

  # ── secret 検出（staged 追加行）: 検出時は値を出力せず件数とファイル名のみ ──
  _secret_re='ntn_[A-Za-z0-9]{30,}|ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{24,}|AKIA[0-9A-Z]{16}|xox[baprs]-[0-9A-Za-z-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY'
  _seccnt=$(git_in_ctx diff --cached 2>/dev/null | grep '^+' | grep -cE "$_secret_re" || true)
  if [ "${_seccnt:-0}" -gt 0 ]; then
    _secfiles=$(git_in_ctx diff --cached --name-only -G"$_secret_re" 2>/dev/null | head -5)
    printf '[SECRET-BLOCK] staged 差分の追加行に API トークン/秘密鍵らしき文字列を %s 件検出しました。コミットを中止します。\n該当ファイル: %s\n値を除去し、macOS Keychain（security add-generic-password）または環境変数へ退避してから再 commit してください。値そのものは再出力しないこと。\n' "$_seccnt" "$_secfiles" >&2
    exit 2
  fi

  _dld="$HOME/agent-home/tools/linter"

  # ── docs ファイルの textlint ──────────────────────────────
  _docsf=$(
    git_in_ctx diff --cached --name-only --diff-filter=ACM 2>/dev/null \
      | grep -E '^docs/.*\.md$' \
      | grep -vE '^docs/01_規約・標準/自動化規約/Claude実行ルール/' \
      || true
  )

  if [ -n "$_docsf" ] && [ -n "$_node" ]; then
    _accf=$(mktemp /tmp/docsacc_XXXXXX)
    _cfg=$(resolve_textlint_config "$_dld/.textlintrc.json" "$_git_ctx_dir")

    while IFS= read -r _f; do
      [ -z "$_f" ] && continue

      # 追加行の行番号を収集
      _ADDED=$(
        git_in_ctx diff --cached -U0 -- "$_f" 2>/dev/null \
          | perl -ne '
              if (/^@@ .* \+(\d+)(?:,(\d+))? @@/) {
                my $s = $1;
                my $c = defined $2 ? $2 : 1;
                for (my $i = 0; $i < $c; $i++) {
                  print +($s + $i), " "
                }
              }
            '
      )
      [ -z "$_ADDED" ] && continue

      # staged 版を一時ファイルに書き出して textlint
      _tmp=$(mktemp /tmp/docslint_XXXXXX.md)
      git_in_ctx show ":$_f" > "$_tmp" 2>/dev/null

      ADDED="$_ADDED" \
        "$_node" \
          "$_dld/node_modules/textlint/bin/textlint.js" \
          --config "$_cfg" \
          "$_tmp" \
          --format compact \
          2>/dev/null \
        | grep "Error -" \
        | ADDED="$_ADDED" perl -ne '
            BEGIN { %s = map { $_ => 1 } split /\s+/, $ENV{ADDED} }
            if (/line (\d+)/ && $s{$1}) { print }
          ' \
        | sed "s|$_tmp|$_f|" \
        >> "$_accf"

      rm -f "$_tmp"
    done < <(printf '%s\n' "$_docsf")

    if [ -s "$_accf" ]; then
      _r=$(cat "$_accf")
      rm -f "$_accf"
      [ "$_cfg" != "$_dld/.textlintrc.json" ] && rm -f "$_cfg"
      jq -n --arg r "$_r" \
        '{
          "systemMessage": "[textlint] docs 追加行に文章ルール違反",
          "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "additionalContext": (
              "[TEXTLINT-BLOCK]\nfile=<docs 差分>\n"
              + $r
              + "\n\ndocs の追加・変更行に文章品質ルール違反があります（既存行の債は対象外・新規行のみ）。~/agent-home/tools/linter/.textlintrc.json 準拠で修正してから再 commit してください。"
            )
          }
        }'
      exit 2
    fi

    rm -f "$_accf"
    [ "$_cfg" != "$_dld/.textlintrc.json" ] && rm -f "$_cfg"
  fi

  # ── HTML ファイルの textlint（prh 語彙のみ・追加行限定）──────
  # 文体ルール（.textlintrc.json）はマークアップ行に誤検知するため適用しない。
  # HTML パーサ plugin は未導入のため、staged 内容を .txt として prh 辞書のみで lint する。
  # 辞書カタログ自身（prh エントリの検出パターン文字列を内容に持つ）は自己言及で必ず違反するため除外
  _htmlf=$(
    git_in_ctx diff --cached --name-only --diff-filter=ACM 2>/dev/null \
      | grep -E '\.html$' \
      | grep -vE '(^|/)node_modules/' \
      | grep -vE '(^|/)ai-management-portal/catalog/dictionaries\.html$' \
      || true
  )

  if [ -n "$_htmlf" ] && [ -n "$_node" ]; then
    _haccf=$(mktemp /tmp/htmlacc_XXXXXX)
    _hcfg=$(resolve_textlint_config "$_dld/.textlintrc.pr.json" "$_git_ctx_dir")

    while IFS= read -r _f; do
      [ -z "$_f" ] && continue

      _ADDED=$(
        git_in_ctx diff --cached -U0 -- "$_f" 2>/dev/null \
          | perl -ne '
              if (/^@@ .* \+(\d+)(?:,(\d+))? @@/) {
                my $s = $1;
                my $c = defined $2 ? $2 : 1;
                for (my $i = 0; $i < $c; $i++) {
                  print +($s + $i), " "
                }
              }
            '
      )
      [ -z "$_ADDED" ] && continue

      _tmp=$(mktemp /tmp/htmllint_XXXXXX.txt)
      git_in_ctx show ":$_f" > "$_tmp" 2>/dev/null

      ADDED="$_ADDED" \
        "$_node" \
          "$_dld/node_modules/textlint/bin/textlint.js" \
          --config "$_hcfg" \
          "$_tmp" \
          --format compact \
          2>/dev/null \
        | grep "Error -" \
        | ADDED="$_ADDED" perl -ne '
            BEGIN { %s = map { $_ => 1 } split /\s+/, $ENV{ADDED} }
            if (/line (\d+)/ && $s{$1}) { print }
          ' \
        | sed "s|$_tmp|$_f|" \
        >> "$_haccf"

      rm -f "$_tmp"
    done < <(printf '%s\n' "$_htmlf")

    if [ -s "$_haccf" ]; then
      _r=$(cat "$_haccf")
      rm -f "$_haccf"
      [ "$_hcfg" != "$_dld/.textlintrc.pr.json" ] && rm -f "$_hcfg"
      jq -n --arg r "$_r" \
        '{
          "systemMessage": "[textlint] HTML 追加行に語彙ルール違反",
          "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "additionalContext": (
              "[TEXTLINT-BLOCK]\nfile=<HTML 差分>\n"
              + $r
              + "\n\nHTML の追加・変更行に語彙ルール違反があります（prh 辞書のみ・文体ルール対象外・新規行のみ）。~/.claude/rules/always/review-checklist/text-dictionary/prh.yml の該当エントリの expected 値に従って修正してから再 commit してください。"
            )
          }
        }'
      exit 2
    fi

    rm -f "$_haccf"
    [ "$_hcfg" != "$_dld/.textlintrc.pr.json" ] && rm -f "$_hcfg"
  fi

  # ── 英語 type による命名規則チェック (-m フラグ版) ──────────
  if printf '%s' "$cmd" \
      | grep -qE -- '-m[[:space:]]+"(feat|fix|docs|chore|refactor|test|style|ci|perf|revert)(\([^)]+\))?!?:'; then
    printf '[NAMING-BLOCK] 英語 type (feat/fix/docs/chore/refactor/test/style/ci/perf/revert) は廃止されました。日本語 prefix を使ってください: 【機能追加】【バグ修正】【ドキュメント】【設定変更】【リファクタ】【テスト】【スタイル】【CI】【パフォーマンス】【取り消し】\n' >&2
    exit 2
  fi

  # ── HEREDOC コミット本文の命名規則チェック ────────────────
  hd_first=$(
    printf '%s' "$cmd" \
      | perl -0777 -ne '
          while (/<<\s*[\x27"]?(\w+)[\x27"]?\s*\n(.+?)\n\1\b/sg) {
            my $b = $2;
            $b =~ s/^\s+//;
            my ($f) = split /\n/, $b, 2;
            print "$f\n" if $f;
          }
        '
  )

  if printf '%s' "$hd_first" \
      | grep -qE '^(feat|fix|docs|chore|refactor|test|style|ci|perf|revert)(\([^)]+\))?!?:'; then
    printf '[NAMING-BLOCK] HEREDOC コミット本文が英語 type で始まっています。日本語 prefix を使ってください: 【機能追加】【バグ修正】【ドキュメント】【設定変更】【リファクタ】【テスト】【スタイル】【CI】【パフォーマンス】【取り消し】\n' >&2
    exit 2
  fi

  # ── 公開可否・機密ファイル検出・author 注入 ──────────────
  n=$(git_in_ctx config user.name 2>/dev/null)
  e=$(git_in_ctx config user.email 2>/dev/null)

  sensitive=$(
    git_in_ctx diff --cached --name-only 2>/dev/null \
      | grep -E '(^|/)(\.env(\..+)?|id_rsa|id_ed25519|.*\.pem|credentials\.json|\.npmrc|\.pypirc|.*\.tfstate|.*\.tfstate\.backup)$' \
      | head -5 \
      || true
  )

  ctx=$(printf \
    '[NAMING] コミット: 【<type>】<subject> | type: 機能追加/バグ修正/ドキュメント/設定変更/リファクタ/テスト/スタイル/CI/パフォーマンス/取り消し | scope は任意でコロン区切り 例: 【設定変更:routine】 | subject: 日本語必須・ローマ字禁止・25文字以内・末尾ピリオドなし | 英語 type 禁止\n[PUBLISH-AUTHOR] author: %s <%s>（手順: ~/agent-home/skills/reviewing-public-readiness/SKILL.md）\n[PUBLISH-SAFETY-FULL]（手順: ~/agent-home/skills/reviewing-public-readiness/SKILL.md）' \
    "$n" "$e"
  )

  if [ -n "$sensitive" ]; then
    ctx=$(printf \
      '%s\n[PUBLISH-SAFETY] ステージング差分に機密ファイル名パターンを検出: %s。reviewing-public-readiness スキルで CRITICAL 観点を確認すること（~/agent-home/skills/reviewing-public-readiness/SKILL.md）' \
      "$ctx" "$sensitive"
    )
  fi

  jq -n --arg ctx "$ctx" \
    '{
      "systemMessage": "[フック発火] 命名規則 + 公開可否レビュー: コミット",
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "additionalContext": $ctx
      }
    }'
  exit 0
fi

# ─────────────────────────────────────────────────────────────
# git push: 未 push コミットの secret 検出（値は出力しない）
# ─────────────────────────────────────────────────────────────
resolve_git_ctx_dir "$cmd" "$CMD_CTX_GIT_PUSH_RE" "$_hook_cwd"
if [ -n "$RGCD_MATCHED_SEG" ]; then
  _secret_re='ntn_[A-Za-z0-9]{30,}|ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{24,}|AKIA[0-9A-Z]{16}|xox[baprs]-[0-9A-Za-z-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY'
  _seccnt=$(git -C "$RGCD_CTX_DIR" log --branches --not --remotes -p --max-count=100 2>/dev/null | grep '^+' | grep -cE "$_secret_re" || true)
  if [ "${_seccnt:-0}" -gt 0 ]; then
    printf '[SECRET-BLOCK] 未 push コミットの追加行に API トークン/秘密鍵らしき文字列を %s 件検出しました。push を中止します。\ngit log --branches --not --remotes --oneline で対象コミットを特定し、履歴から値を除去（rebase 等）してから再 push してください。値そのものは再出力しないこと。\n' "$_seccnt" >&2
    exit 2
  fi
fi

case "$cmd" in

  # ─────────────────────────────────────────────────────────────
  # git checkout / git branch / git switch: ブランチ命名規則
  # ─────────────────────────────────────────────────────────────
  "git checkout"*|"git branch"*|"git switch"*)
    printf \
      '{"systemMessage":"[フック発火] 命名規則: ブランチ","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"[NAMING] ブランチ: <prefix>/<slug> | prefix: feature/fix/docs/chore/refactor/release/hotfix | slug: ケバブケース・50文字以内"}}'
    ;;

  # ─────────────────────────────────────────────────────────────
  # mkdir: ディレクトリ命名規則
  # ─────────────────────────────────────────────────────────────
  "mkdir"*)
    printf \
      '{"systemMessage":"[フック発火] 命名規則: ディレクトリ","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"[NAMING] ディレクトリ名: ケバブケース必須。予約名: references/ scripts/ assets/ workflows/ shared_scripts/"}}'
    ;;

  # ─────────────────────────────────────────────────────────────
  # git rebase / git merge --no-ff|--squash: コンフリクト解消ガード
  # ─────────────────────────────────────────────────────────────
  "git rebase"*|"git merge --no-ff"*|"git merge --squash"*)
    printf \
      '{"systemMessage":"[フック発火] コンフリクト解消ガード","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"[CONFLICT-RESOLUTION-GUARD] git rebase / git merge を実行しようとしています。~/.claude/rules/always/infra/pre-bash-dispatch/rule.md の『[CONFLICT-RESOLUTION-GUARD] 受信』手順に従って、Step 1（事前影響分析）と Step 2（ユーザーへの報告・承認）を完了してからこのコマンドを実行してください。完了済みの場合はそのまま続行してください。"}}'
    ;;

  # ─────────────────────────────────────────────────────────────
  # gh pr create / gh issue create: PR・issue 本文の textlint
  # ─────────────────────────────────────────────────────────────
  "gh pr create"*|"gh issue create"*)
    _ldir="$HOME/agent-home/tools/linter"
    _tmpf=$(mktemp /tmp/textlint_body_XXXXXX.md)

    printf '%s' "$cmd" \
      | perl -0777 -e '
          $_ = do { local $/; <STDIN> };
          if (/--body\s+"\$\(\s*cat\s+<<\s*[\x27"]?(\w+)[\x27"]?\s*\n(.*?)\n\1\s*\n\s*\)\s*"/ms) {
            print $2
          } elsif (/--body\s+"((?:[^"\\]|\\.)*)"/s) {
            print $1
          }
        ' > "$_tmpf"

    if [ -s "$_tmpf" ] && [ -n "$_node" ]; then
      _cfg=$(resolve_textlint_config "$_ldir/.textlintrc.pr.json")
      _tres=$(
        "$_node" \
          "$_ldir/node_modules/textlint/bin/textlint.js" \
          --config "$_cfg" \
          "$_tmpf" \
          --format compact \
          2>&1
      ) || true
      rm -f "$_tmpf"
      [ "$_cfg" != "$_ldir/.textlintrc.pr.json" ] && rm -f "$_cfg"

      if [ -n "$_tres" ]; then
        jq -n --arg r "$_tres" \
          '{
            "systemMessage": "[textlint] PR/issue 本文にルール違反",
            "hookSpecificOutput": {
              "hookEventName": "PreToolUse",
              "additionalContext": (
                "[TEXTLINT-BLOCK]\nfile=<pr-issue-body>\n"
                + $r
                + "\n\nPR/issue 本文の語彙ルール違反です。上記の指摘箇所を ~/.claude/rules/always/review-checklist/text-dictionary/prh.yml の該当エントリの expected 値（推奨置き換え語）に従って修正してから再実行してください。辞書に該当エントリがない新規違反の場合は Skill(\"adding-textlint-dictionary-terms\") で辞書へ登録してから修正してください。"
              )
            }
          }'
        exit 2
      fi
    else
      rm -f "$_tmpf"
    fi
    ;;

  # ─────────────────────────────────────────────────────────────
  # gh pr comment / gh issue comment: コメント本文の textlint（通知のみ）
  # ─────────────────────────────────────────────────────────────
  "gh pr comment"*|"gh issue comment"*)
    _ldir="$HOME/agent-home/tools/linter"
    _tmpf=$(mktemp /tmp/textlint_body_XXXXXX.md)

    printf '%s' "$cmd" \
      | perl -0777 -e '
          $_ = do { local $/; <STDIN> };
          if (/--body\s+"\$\(\s*cat\s+<<\s*[\x27"]?(\w+)[\x27"]?\s*\n(.*?)\n\1\s*\n\s*\)\s*"/ms) {
            print $2
          } elsif (/--body\s+"((?:[^"\\]|\\.)*)"/s) {
            print $1
          }
        ' > "$_tmpf"

    if [ -s "$_tmpf" ] && [ -n "$_node" ]; then
      _cfg=$(resolve_textlint_config "$_ldir/.textlintrc.pr.json")
      _tres=$(
        "$_node" \
          "$_ldir/node_modules/textlint/bin/textlint.js" \
          --config "$_cfg" \
          "$_tmpf" \
          --format compact \
          2>&1
      ) || true
      rm -f "$_tmpf"
      [ "$_cfg" != "$_ldir/.textlintrc.pr.json" ] && rm -f "$_cfg"

      if [ -n "$_tres" ]; then
        jq -n --arg r "$_tres" \
          '{
            "systemMessage": "[textlint] コメント本文にルール違反（通知のみ）",
            "hookSpecificOutput": {
              "hookEventName": "PreToolUse",
              "additionalContext": (
                "[TEXTLINT-ADVISORY]\nfile=<comment-body>\n"
                + $r
                + "\n\nコメント本文の語彙ルール違反です。会話文のため block しません。気になる場合のみ prh 推奨語へ置換してください。"
              )
            }
          }'
        exit 0
      fi
    else
      rm -f "$_tmpf"
    fi
    ;;

  # ─────────────────────────────────────────────────────────────
  # その他: 何もしない
  # ─────────────────────────────────────────────────────────────
  *)
    exit 0
    ;;

esac
