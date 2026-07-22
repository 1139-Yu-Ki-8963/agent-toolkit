/** 一覧取得クエリのレスポンス型。 */
export type ItemListResponse = {
  items: {
    id: string;
    code: string;
    name: string;
    category: string;
    quantity: number;
    updatedAt: string;
  }[];
  totalCount: number;
};

/** 一覧取得クエリの変数型。 */
export type ItemListVariables = {
  keyword: string;
  limit: number;
  offset: number;
};

/** 削除ミューテーションの変数型。 */
export type DeleteItemVariables = {
  id: string;
};

export const ITEM_LIST_QUERY = /* GraphQL */ `
  query ItemList($keyword: String, $limit: Int!, $offset: Int!) {
    items(keyword: $keyword, limit: $limit, offset: $offset) {
      id
      code
      name
      category
      quantity
      updatedAt
    }
    totalCount(keyword: $keyword)
  }
`;

export const DELETE_ITEM_MUTATION = /* GraphQL */ `
  mutation DeleteItem($id: ID!) {
    deleteItem(id: $id) {
      id
    }
  }
`;
