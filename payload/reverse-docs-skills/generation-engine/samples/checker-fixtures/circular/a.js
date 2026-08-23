// 実際の書き方で検査を試すための見本。b を取り込む。
// b.js は a.js を取り込んでおり、2 つのファイルが互いを参照する形になる。
import { b } from "./b";
export const a = b;
