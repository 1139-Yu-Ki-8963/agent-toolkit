import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import CircularProgress from '@mui/material/CircularProgress';
import Table from '@mui/material/Table';
import TableBody from '@mui/material/TableBody';
import TableCell from '@mui/material/TableCell';
import TableContainer from '@mui/material/TableContainer';
import TableRow from '@mui/material/TableRow';
import TextField from '@mui/material/TextField';
import Typography from '@mui/material/Typography';
import Paper from '@mui/material/Paper';

import { columns, HeaderCell, sortItemsByKey, SortDirection } from './ItemListColumns';
import { ITEM_LIST_QUERY, DELETE_ITEM_MUTATION } from './ItemListPage.gql';
import type { ItemListResponse, ItemListVariables } from './ItemListPage.gql';

/** 画面内でのみ使うアイテム表示行の型（ローカル型定義）。 */
type ItemRow = ItemListResponse['items'][number];

/** 検索フォームの入力値をまとめるローカル型定義。 */
type SearchFormState = {
  keyword: string;
};

const PAGE_SIZE = 20;

async function fetchItemList(variables: ItemListVariables): Promise<ItemListResponse> {
  const response = await fetch('/api/graphql', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: ITEM_LIST_QUERY, variables }),
  });
  if (!response.ok) {
    throw new Error(`一覧の取得に失敗しました（status: ${response.status}）`);
  }
  const body = await response.json();
  return body.data as ItemListResponse;
}

async function deleteItem(id: string): Promise<void> {
  const response = await fetch('/api/graphql', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: DELETE_ITEM_MUTATION, variables: { id } }),
  });
  if (!response.ok) {
    throw new Error(`削除に失敗しました（status: ${response.status}）`);
  }
}

export default function ItemListPage() {
  const navigate = useNavigate();
  const [items, setItems] = useState<ItemRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [form, setForm] = useState<SearchFormState>({ keyword: '' });

  useEffect(() => {
    let cancelled = false;

    async function load() {
      setLoading(true);
      setError(null);
      try {
        const result = await fetchItemList({ keyword: form.keyword, limit: PAGE_SIZE, offset: 0 });
        if (!cancelled) {
          setItems(sortItemsByKey(result.items, 'updatedAt', SortDirection.Desc));
        }
      } catch (err) {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : '不明なエラーが発生しました');
        }
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    }

    load();
    return () => {
      cancelled = true;
    };
  }, [form.keyword]);

  const handleSearchSubmit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    try {
      setLoading(true);
      const result = await fetchItemList({ keyword: form.keyword, limit: PAGE_SIZE, offset: 0 });
      setItems(result.items);
    } catch (err) {
      window.alert(err instanceof Error ? err.message : '検索に失敗しました');
    } finally {
      setLoading(false);
    }
  };

  const handleAddClick = () => navigate('/items/new');
  const handleRowClick = (id: string) => navigate(`/items/${id}`);
  const handleDeleteClick = async (id: string) => {
    try {
      await deleteItem(id);
      setItems((prev) => prev.filter((item) => item.id !== id));
    } catch (err) {
      window.alert(err instanceof Error ? err.message : '削除でエラーが発生しました');
    }
  };

  return (
    <Box sx={{ padding: 3 }}>
      <Typography variant="h5" component="h1" sx={{ marginBottom: 2 }}>
        アイテム一覧
      </Typography>

      <Box
        component="form"
        onSubmit={handleSearchSubmit}
        sx={{ display: 'flex', gap: 2, marginBottom: 2, alignItems: 'center' }}
      >
        <TextField
          label="キーワード"
          size="small"
          value={form.keyword}
          onChange={(event) => setForm({ keyword: event.target.value })}
        />
        <Button type="submit" variant="contained">
          検索
        </Button>
        <Button variant="outlined" onClick={handleAddClick}>
          新規追加
        </Button>
      </Box>

      {error && (
        <Typography color="error" sx={{ marginBottom: 2 }}>
          {error}
        </Typography>
      )}

      {loading ? (
        <CircularProgress size={24} />
      ) : (
        <TableContainer
          component={Paper}
          sx={{
            '& .MuiTableCell-root': {
              fontSize: '0.875rem',
              padding: '8px 16px',
            },
            '& .MuiTableRow-root:hover': {
              backgroundColor: 'action.hover',
              cursor: 'pointer',
            },
          }}
        >
          <Table size="small">
            <TableBody>
              <TableRow>
                {columns.map((column) => (
                  <HeaderCell key={column.key} sx={{ width: column.width }}>
                    {column.label}
                  </HeaderCell>
                ))}
                <HeaderCell sx={{ width: 80 }}>操作</HeaderCell>
              </TableRow>
              {items.map((item) => (
                <TableRow key={item.id} onClick={() => handleRowClick(item.id)}>
                  <TableCell>{item.code}</TableCell>
                  <TableCell>{item.name}</TableCell>
                  <TableCell>{item.category}</TableCell>
                  <TableCell>{item.quantity}</TableCell>
                  <TableCell>{item.updatedAt}</TableCell>
                  <TableCell>
                    <Button
                      size="small"
                      color="error"
                      onClick={(event) => {
                        event.stopPropagation();
                        handleDeleteClick(item.id);
                      }}
                    >
                      削除
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </TableContainer>
      )}
    </Box>
  );
}
