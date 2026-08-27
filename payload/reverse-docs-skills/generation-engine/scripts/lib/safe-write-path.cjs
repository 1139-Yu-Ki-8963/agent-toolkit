// 書き込み先の各階層を辿り、意図しない場所を指すシンボリックリンクを拒否する。
//
// なぜ共通化するか: 同じ判定が6ファイル12箇所へ散っていた。実測（2026-08-27）で
//   $TMPDIR 配下へ出力すると「write path must not contain a symbolic link: /var」で
//   落ちることが分かったが、1箇所を直しても別の箇所で同じエラーが出た。
//   判定を1箇所へ持たせ、直しが全箇所へ届くようにする。
//
// なぜ /private 配下を通すか: macOS は /var /tmp /etc を /private 配下への標準の
//   リンクとして持つ。$TMPDIR は /var/folders/... にあるため、これを拒否すると
//   一時領域へ書けない。検証する側が一時領域へ出力して繰り返し検証する経路が塞がる。
//   意図しない場所への書き込みを防ぐという目的は、それ以外のリンクを拒否することで保つ。
const fs = require("node:fs");
const path = require("node:path");

// OSが標準で持つリンクだけを通す。macOS の /var /tmp /etc がこれにあたる。
// 解決先が /private 配下かどうかでは判定しない。$TMPDIR 配下に作った任意のリンクも
// 解決先が /private 配下になるため、それを通すと危険なリンクまで許してしまう。
// 実測（2026-08-27）でこの誤りを確認した。リンク自身の位置で判定する。
const OS_STANDARD_LINKS = new Set(["/var", "/tmp", "/etc"]);

function isOsStandardLink(target) {
  return OS_STANDARD_LINKS.has(target);
}

function assertSafeWritePath(raw, label) {
  const tag = label || "write path";
  const absolute = path.isAbsolute(raw) ? raw : process.cwd() + path.sep + raw;
  const parsed = path.parse(absolute);
  let current = parsed.root;
  for (const segment of absolute.slice(parsed.root.length).split(path.sep)) {
    if (!segment || segment === ".") continue;
    if (segment === "..") {
      current = path.dirname(current);
      continue;
    }
    current = path.join(current, segment);
    let stat;
    try {
      stat = fs.lstatSync(current);
    } catch (error) {
      if (error && error.code === "ENOENT") break;
      throw error;
    }
    if (stat.isSymbolicLink() && !isOsStandardLink(current)) {
      throw new Error(tag + " must not contain a symbolic link: " + current);
    }
  }
}

module.exports = { isOsStandardLink, assertSafeWritePath };
