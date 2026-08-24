#!/usr/bin/env node
'use strict';

// ブラウザを使う検査が、実行環境の制約でブラウザを起動・接続できないときに、
// 不合格(終了コード1)ではなく判定不能(終了コード2・[UNKNOWN])を返すための
// 共通ヘルパー。判定不能規約
// (.claude/rules/always/verification/indeterminate-result/rule.md)が定める
// 「既存の合格・不合格ラベルへ理由を書き添えるだけの表現を使わない」を守るため、
// 出力は固定の1行のみとし、ブラウザのstderr等の未知の文字列を含めない。
//
// 出力を固定文言に絞る理由: 第1層の集約(run-layer-machine-checks.sh)の
// has_indeterminate_contract()は、出力全体に error/usage/unknown argument 等の
// 行頭語を含む場合、判定不能とみなさず不合格へ落とす。ブラウザの標準エラー出力
// (Chrome/Chromiumのクラッシュログ等)を[UNKNOWN]行へそのまま連結すると、
// 行頭に紛れ込んだそれらの語で判定不能の判定自体が壊れうる。原因の詳細は
// error.cause / error.detail にのみ保持し、標準エラーへは出さない。

const UNKNOWN_REASON = 'ブラウザを起動できないため判定できません（実行環境の制約が原因である可能性があります）';

class BrowserUnavailableError extends Error {
  constructor(detail) {
    super(UNKNOWN_REASON);
    this.name = 'BrowserUnavailableError';
    this.detail = detail;
  }
}

// launchBrowser/connectCdp/findBrowser/chromium.launch/requireの失敗など、
// ブラウザの起動・接続フェーズで捕まえた例外を BrowserUnavailableError として
// 包み直す。呼び出し側は「起動・接続フェーズだけ」をtry/catchで囲み、
// 計測フェーズ(Runtime.evaluate等)の例外は包まないこと。
function markUnavailable(cause) {
  const detail = cause && cause.message ? cause.message : String(cause);
  const wrapped = new BrowserUnavailableError(detail);
  wrapped.cause = cause;
  return wrapped;
}

// 最終catchで使う判定関数。BrowserUnavailableErrorなら[UNKNOWN]を出力して
// true(処理済み)を返す。そうでなければ何もせずfalseを返す(呼び出し側が
// 従来どおりの不合格処理を続ける)。
function reportIfUnavailable(error) {
  if (error instanceof BrowserUnavailableError) {
    console.error(`[UNKNOWN] ${error.message}`);
    return true;
  }
  return false;
}

module.exports = { BrowserUnavailableError, markUnavailable, reportIfUnavailable, UNKNOWN_REASON };
