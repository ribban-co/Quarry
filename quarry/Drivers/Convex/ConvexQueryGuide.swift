enum ConvexQueryGuide {
    // swiftlint:disable line_length
    static let content = """
    # Convex Query JSON Specification

    Convex does NOT use SQL. When using `run_query` with a Convex connection, pass a JSON object as the query string. The JSON is sent to the `_system/frontend/paginatedTableDocuments` endpoint.

    ## Query format

    Every query is a JSON object with these fields:

    ```json
    {
      "table": "tableName",
      "clauses": [ ... ],
      "order": "asc" | "desc",
      "index": { ... }
    }
    ```

    - `table` (required): The Convex table name to query.
    - `clauses` (required): Array of filter clauses. Use `[]` for no filtering.
    - `order` (optional): `"asc"` or `"desc"`. Defaults to `"desc"`.
    - `index` (optional): Index filter for efficient queries. Omit to scan by creation time.

    ## Filter clauses

    Each clause filters documents by field value. All clauses are AND-ed together.

    ```json
    {
      "field": "fieldName",
      "op": "eq",
      "value": <value>,
      "enabled": true,
      "id": "filter_0"
    }
    ```

    ### Available operators

    | Operator | Meaning | Example value |
    |----------|---------|---------------|
    | `eq` | equals | `"active"` |
    | `neq` | not equals | `"deleted"` |
    | `gt` | greater than | `100` |
    | `gte` | greater than or equal | `100` |
    | `lt` | less than | `1000` |
    | `lte` | less than or equal | `1000` |
    | `anyOf` | matches any value in array | `["active", "pending"]` |
    | `noneOf` | matches none of values in array | `["deleted", "archived"]` |
    | `type` | field is of given type | `"string"` |
    | `notype` | field is NOT of given type | `"null"` |

    Type filter values: `"string"`, `"boolean"`, `"number"`, `"bigint"`, `"null"`, `"id"`, `"array"`, `"object"`, `"bytes"`, `"unset"`

    ### Clause rules

    - Every clause must have `"enabled": true` to be applied.
    - `"id"` is an arbitrary unique string per clause (e.g. `"filter_0"`, `"filter_1"`).
    - `"field"` is the document field name to filter on.
    - For `anyOf`/`noneOf`, `"value"` is an array of values.
    - For `type`/`notype`, `"value"` is a type string from the list above.

    ## Index filters (optional)

    For efficient queries, specify an index. Without an index, Convex scans by `by_creation_time`.

    ### Database index

    ```json
    {
      "index": {
        "name": "by_status",
        "clauses": [
          { "type": "indexEq", "enabled": true, "value": "active" }
        ]
      }
    }
    ```

    Index clause types:
    - `indexEq`: Equality match on the index field. Fields are matched in index order.
    - `indexRange`: Range match (must be the LAST clause):
      ```json
      {
        "type": "indexRange",
        "enabled": true,
        "lowerOp": "gte",
        "lowerValue": 1700000000,
        "upperOp": "lt",
        "upperValue": 1700100000
      }
      ```

    Range operators: `"gte"`, `"gt"` for lower bound; `"lte"`, `"lt"` for upper bound. Both are optional.

    Index rules:
    - Clauses follow the index field order.
    - All `indexEq` clauses come before any `indexRange`.
    - At most one `indexRange`, and it must be the last clause.
    - Disabled clauses (`"enabled": false`) must come after all enabled clauses.

    ### Search index

    ```json
    {
      "index": {
        "name": "search_body",
        "search": "search query text",
        "clauses": [
          { "field": "status", "enabled": true, "value": "published" }
        ]
      }
    }
    ```

    - `"search"` is the full-text search query against the index's search field.
    - `"clauses"` are equality filters on the index's filter fields.
    - Search queries only support `"asc"` order.

    ## Common query examples

    ### List all documents in a table (no filters)
    ```json
    {
      "table": "users",
      "clauses": [],
      "order": "desc"
    }
    ```

    ### Filter by field value
    ```json
    {
      "table": "orders",
      "clauses": [
        { "field": "status", "op": "eq", "value": "active", "enabled": true, "id": "f0" }
      ],
      "order": "desc"
    }
    ```

    ### Multiple filters (AND)
    ```json
    {
      "table": "orders",
      "clauses": [
        { "field": "status", "op": "eq", "value": "completed", "enabled": true, "id": "f0" },
        { "field": "total", "op": "gt", "value": 100, "enabled": true, "id": "f1" }
      ],
      "order": "desc"
    }
    ```

    ### Using a database index with equality
    ```json
    {
      "table": "messages",
      "clauses": [],
      "order": "desc",
      "index": {
        "name": "by_channel",
        "clauses": [
          { "type": "indexEq", "enabled": true, "value": "general" }
        ]
      }
    }
    ```

    ### Using a database index with range
    ```json
    {
      "table": "events",
      "clauses": [],
      "order": "asc",
      "index": {
        "name": "by_creation_time",
        "clauses": [
          {
            "type": "indexRange",
            "enabled": true,
            "lowerOp": "gte",
            "lowerValue": 1700000000000,
            "upperOp": "lt",
            "upperValue": 1700100000000
          }
        ]
      }
    }
    ```

    ### Index equality + range (multi-field index)
    ```json
    {
      "table": "messages",
      "clauses": [],
      "order": "asc",
      "index": {
        "name": "by_channel_time",
        "clauses": [
          { "type": "indexEq", "enabled": true, "value": "general" },
          { "type": "indexRange", "enabled": true, "lowerOp": "gte", "lowerValue": 1700000000000 }
        ]
      }
    }
    ```

    ### Full-text search
    ```json
    {
      "table": "articles",
      "clauses": [],
      "order": "asc",
      "index": {
        "name": "search_body",
        "search": "convex database",
        "clauses": [
          { "field": "status", "enabled": true, "value": "published" }
        ]
      }
    }
    ```

    ### Filter by type (e.g. exclude null values)
    ```json
    {
      "table": "users",
      "clauses": [
        { "field": "email", "op": "notype", "value": "null", "enabled": true, "id": "f0" }
      ],
      "order": "desc"
    }
    ```

    ### Match any of multiple values
    ```json
    {
      "table": "orders",
      "clauses": [
        { "field": "status", "op": "anyOf", "value": ["pending", "processing"], "enabled": true, "id": "f0" }
      ],
      "order": "desc"
    }
    ```

    ## Aggregation (optional)

    Convex has no server-side aggregation. To compute GROUP BY, SUM, COUNT, etc., add an `aggregate` field. Documents are fetched first (up to 500), then aggregated client-side.

    ```json
    {
      "table": "orders",
      "clauses": [],
      "order": "desc",
      "aggregate": {
        "groupBy": ["category"],
        "measures": [
          { "column": "amount", "function": "sum" },
          { "column": "_id", "function": "count" }
        ]
      }
    }
    ```

    ### Available aggregation functions

    | Function | Meaning |
    |----------|---------|
    | `count` | Number of rows in group |
    | `countDistinct` | Number of unique values |
    | `sum` | Sum of numeric values |
    | `average` | Average of numeric values |
    | `min` | Minimum value |
    | `max` | Maximum value |

    ### Aggregation rules

    - `groupBy` is an array of field names to group by. Use `[]` for a single aggregate over all rows.
    - `measures` is an array of `{ "column": "fieldName", "function": "aggFunction" }`.
    - Result columns are named `fieldName_function` (e.g. `amount_sum`, `_id_count`).
    - Up to 500 documents are fetched for aggregation. For larger datasets, add filters to narrow the scope.
    - Without `aggregate`, raw documents are returned (up to 100).

    ### Aggregation examples

    Total revenue by category:
    ```json
    {
      "table": "orders",
      "clauses": [{ "field": "status", "op": "eq", "value": "completed", "enabled": true, "id": "f0" }],
      "aggregate": { "groupBy": ["category"], "measures": [{ "column": "amount", "function": "sum" }] }
    }
    ```

    Overall count (no grouping):
    ```json
    {
      "table": "users",
      "clauses": [],
      "aggregate": { "groupBy": [], "measures": [{ "column": "_id", "function": "count" }] }
    }
    ```

    Average order value by status:
    ```json
    {
      "table": "orders",
      "clauses": [],
      "aggregate": { "groupBy": ["status"], "measures": [{ "column": "total", "function": "average" }, { "column": "_id", "function": "count" }] }
    }
    ```

    ## Join (optional)

    Convex stores relationships as ID references (e.g. `v.id("customers")`). Use the `join` field to fetch and merge related documents from another table.

    ```json
    {
      "table": "orders",
      "clauses": [],
      "join": {
        "field": "customerId",
        "referencedTable": "customers",
        "includeFields": ["name", "email"]
      }
    }
    ```

    - `field`: The field in the primary table that contains an ID reference to another table.
    - `referencedTable`: The table to fetch the referenced documents from.
    - `includeFields` (optional): Array of field names to include from the referenced table. If omitted, all fields except `_id` and `_creationTime` are included.

    Result columns from the referenced table are prefixed with the table name (e.g. `customers.name`, `customers.email`).

    ### Join examples

    Orders with customer info:
    ```json
    {
      "table": "orders",
      "clauses": [{ "field": "status", "op": "eq", "value": "completed", "enabled": true, "id": "f0" }],
      "join": { "field": "customerId", "referencedTable": "customers", "includeFields": ["name", "email"] }
    }
    ```

    Messages with user info:
    ```json
    {
      "table": "messages",
      "clauses": [],
      "order": "desc",
      "join": { "field": "authorId", "referencedTable": "users", "includeFields": ["name"] }
    }
    ```

    Join + aggregation (revenue by customer name):
    ```json
    {
      "table": "orders",
      "clauses": [],
      "join": { "field": "customerId", "referencedTable": "customers", "includeFields": ["name"] },
      "aggregate": { "groupBy": ["customers.name"], "measures": [{ "column": "amount", "function": "sum" }] }
    }
    ```

    ### Join rules

    - Only one join per query (single level, no chained joins).
    - The `field` must contain Convex document IDs (`v.id("tableName")` type).
    - Use `get_table_schema` to discover which fields are foreign keys — they show as `[FK -> tableName]`.
    - Joined fields are available for `aggregate.groupBy` using the prefixed name (e.g. `customers.name`).

    ## Important limitations

    - Only single-level joins are supported (no chaining A → B → C).
    - Aggregation is computed client-side on fetched documents (max 500). Add filters to narrow scope for large tables.
    - Without an index filter, Convex scans by creation time — use index filters for efficient queries on large tables.

    ## Quick reference

    ```
    QUERY = {
      table: string,              // required
      clauses: CLAUSE[],          // required, can be []
      order?: "asc" | "desc",     // optional, default "desc"
      index?: INDEX,              // optional
      join?: JOIN,                // optional
      aggregate?: AGGREGATE       // optional (applied after join)
    }

    CLAUSE = {
      field: string,
      op: "eq"|"neq"|"gt"|"gte"|"lt"|"lte"|"anyOf"|"noneOf"|"type"|"notype",
      value: any,                 // array for anyOf/noneOf, type string for type/notype
      enabled: true,
      id: string
    }

    INDEX (database) = {
      name: string,
      clauses: (INDEX_EQ | INDEX_RANGE)[]
    }

    INDEX_EQ = { type: "indexEq", enabled: boolean, value: any }
    INDEX_RANGE = { type: "indexRange", enabled: boolean, lowerOp?: "gte"|"gt", lowerValue?: any, upperOp?: "lte"|"lt", upperValue?: any }

    INDEX (search) = {
      name: string,
      search: string,
      clauses: { field: string, enabled: boolean, value: any }[]
    }

    JOIN = {
      field: string,              // FK field in primary table
      referencedTable: string,    // table to fetch from
      includeFields?: string[]    // fields to merge (omit for all)
    }

    AGGREGATE = {
      groupBy: string[],          // field names to group by, [] for overall
      measures: MEASURE[]
    }

    MEASURE = { column: string, function: "count"|"countDistinct"|"sum"|"average"|"min"|"max" }
    ```

    ## JavaScript Query Mode (Advanced)

    For complex queries beyond what the JSON format supports, you can pass JavaScript code directly to `run_query`. The driver detects it automatically — anything that isn't a JSON object with a `table` key is treated as JavaScript and executed via `run_test_function`.

    ### Template
    ```javascript
    import { query } from "convex:/_system/repl/wrappers.js";

    export default query({
      handler: async (ctx) => {
        // Full ctx.db access here
        return await ctx.db.query("tableName").collect();
      },
    });
    ```

    ### When to use JS mode
    - Multi-table joins (server-side, no client round-trips)
    - Complex aggregations on large datasets
    - Computed/transformed fields
    - Conditional query logic

    ### When to use JSON mode
    - Simple table browsing and filtering
    - Single-level joins on small tables
    - Basic aggregations (< 500 rows)

    ### Constraints
    - Only `query` exports work — mutations/actions are rejected
    - Read-only — cannot modify data
    - No external imports besides the wrappers
    - Must be plain JavaScript (no TypeScript)
    - Return arrays of objects for best tabular display

    ### Examples

    Multi-table join:
    ```javascript
    import { query } from "convex:/_system/repl/wrappers.js";
    export default query({
      handler: async (ctx) => {
        const orders = await ctx.db.query("orders").collect();
        return Promise.all(orders.map(async (o) => {
          const customer = await ctx.db.get(o.customerId);
          return { ...o, customerName: customer?.name };
        }));
      },
    });
    ```

    Server-side aggregation:
    ```javascript
    import { query } from "convex:/_system/repl/wrappers.js";
    export default query({
      handler: async (ctx) => {
        const orders = await ctx.db.query("orders").collect();
        const byStatus = {};
        for (const o of orders) {
          byStatus[o.status] = (byStatus[o.status] || 0) + 1;
        }
        return Object.entries(byStatus).map(([status, count]) => ({ status, count }));
      },
    });
    ```

    ## Validation checklist

    1. `table` field is present and is the Convex table name.
    2. `clauses` is always an array, even when empty.
    3. Every clause has `field`, `op`, `value`, `enabled: true`, and a unique `id`.
    4. Index clauses follow index field order.
    5. `indexRange` is always the last index clause.
    6. All enabled index clauses come before disabled ones.
    7. Search index queries use `"asc"` order only.
    8. `anyOf`/`noneOf` values are arrays.
    9. `type`/`notype` values are valid type strings.
    """
    // swiftlint:enable line_length
}
