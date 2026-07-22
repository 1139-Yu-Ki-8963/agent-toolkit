import { styled } from '@mui/material/styles';
import TableCell from '@mui/material/TableCell';

/**
 * カラム定義の設定型（ローカル型定義・非export）。
 * テーブル描画側だけが参照する内部構造のため export しない。
 */
type ColumnConfig = {
  key: string;
  label: string;
  width: number;
  sortable: boolean;
};

/**
 * ソート方向を表す列挙（enum定義）。
 * asc/desc の文字列を各所にベタ書きしないための集約。
 */
enum SortDirection {
  Asc = 'asc',
  Desc = 'desc',
}

/** 一覧に表示するカラムの定義配列。 */
export const columns: ColumnConfig[] = [
  { key: 'code', label: 'コード', width: 120, sortable: true },
  { key: 'name', label: '名称', width: 240, sortable: true },
  { key: 'category', label: '区分', width: 140, sortable: true },
  { key: 'quantity', label: '数量', width: 100, sortable: true },
  { key: 'updatedAt', label: '更新日時', width: 180, sortable: true },
];

type SortableItem = Record<string, string | number>;

/**
 * enum引数を受け取るソート関数。
 * direction には SortDirection の値のみを許容する。
 */
export function sortItemsByKey<T extends SortableItem>(
  items: T[],
  key: string,
  direction: SortDirection,
): T[] {
  const sorted = [...items].sort((a, b) => {
    const left = a[key];
    const right = b[key];
    if (left === right) {
      return 0;
    }
    return left > right ? 1 : -1;
  });
  return direction === SortDirection.Desc ? sorted.reverse() : sorted;
}

/** ヘッダーセルの見た目を統一する styled コンポーネント。 */
export const HeaderCell = styled(TableCell)(({ theme }) => ({
  fontWeight: theme.typography.fontWeightBold,
  backgroundColor: theme.palette.grey[100],
  whiteSpace: 'nowrap',
}));

export { SortDirection };
export type { ColumnConfig };
