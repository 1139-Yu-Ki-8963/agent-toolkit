# アイテム一覧 スタイル設計書（DESIGN.md）

## HeaderCell（styled コンポーネント）

| プロパティ | 値 | evidence |
|---|---|---|
| fontWeight | theme.typography.fontWeightBold | ItemListColumns.tsx:57 |
| backgroundColor | theme.palette.grey[100] | ItemListColumns.tsx:58 |
| whiteSpace | 'nowrap' | ItemListColumns.tsx:59 |

## TableContainer インラインsx

| セレクタ | プロパティ | 値 | evidence |
|---|---|---|---|
| .MuiTableCell-root | fontSize | '0.875rem' | ItemListPage.tsx:150 |
| .MuiTableCell-root | padding | '8px 16px' | ItemListPage.tsx:151 |
| .MuiTableRow-root:hover | backgroundColor | 'action.hover' | ItemListPage.tsx:154 |
| .MuiTableRow-root:hover | cursor | 'pointer' | ItemListPage.tsx:155 |

## レイアウト sx

| 要素 | プロパティ | 値 | evidence |
|---|---|---|---|
| Box（ルート） | padding | 3 | ItemListPage.tsx:113 |
| Typography（h1） | marginBottom | 2 | ItemListPage.tsx:114 |
| Box（form） | display | 'flex' | ItemListPage.tsx:121 |
| Box（form） | gap | 2 | ItemListPage.tsx:121 |
| Box（form） | marginBottom | 2 | ItemListPage.tsx:121 |
| Box（form） | alignItems | 'center' | ItemListPage.tsx:121 |
| Typography（error） | marginBottom | 2 | ItemListPage.tsx:138 |
