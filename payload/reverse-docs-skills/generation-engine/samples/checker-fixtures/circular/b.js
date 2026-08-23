// 実際の書き方で検査を試すための見本。a を取り込む。
// a.js は b.js を取り込んでおり、2 つのファイルが互いを参照する形になる。
import { a } from "./a";
export const b = a;
