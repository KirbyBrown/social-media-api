# Query plans

Captured locally on a handful of rows. The planner will not pick the same path at 1M posts. What matters is which index each query can use, and what we would look for once the table is large.

## Unfiltered timeline

```sql
SELECT "posts".* FROM "posts"
WHERE "posts"."deleted_at" IS NULL
ORDER BY "posts"."created_at" DESC
LIMIT 20
```

```
Limit
  ->  Index Scan using index_posts_on_created_at on posts
```

This is the partial `(created_at DESC) WHERE deleted_at IS NULL` index. At 1M kept rows we still want this Index Scan plus a short Limit, not a sort of the whole table.

## Min-rating timeline

```sql
SELECT "posts".* FROM "posts"
WHERE "posts"."deleted_at" IS NULL
  AND "posts"."average_rating" >= 4.0
ORDER BY "posts"."created_at" DESC
LIMIT 20
```

```
Limit
  ->  Index Scan using index_posts_on_created_at on posts
        Filter: (average_rating >= 4.0)
```

On a tiny table Postgres prefers the created_at partial and filters. That is honest.

`index_posts_kept_on_average_rating_created_at` is `(average_rating, created_at DESC) WHERE deleted_at IS NULL`. The range predicate (`average_rating >= 4`) is on the leading column, so matching entries are ordered by `(average_rating, created_at)`, not by `created_at` globally. Postgres cannot walk that index and emit rows in `created_at DESC` order. It must collect the matches and top-N sort them.

The realistic 1M-row plan on that index is Bitmap Index Scan + Sort + Limit. The planner will only prefer it over walk-created_at-and-filter when the rating filter is selective (few rows to sort, which is also when the sort is cheap). The created_at partial wins otherwise. The index is still justified for that selective case. We would not look for a plain Index Scan that satisfies `ORDER BY created_at DESC` from this index; the range on the leading column forfeits that.

## Metadata containment

```sql
SELECT "posts".* FROM "posts"
WHERE "posts"."deleted_at" IS NULL
  AND (metadata @> '{"source":"obd"}'::jsonb)
```

```
Index Scan using index_posts_kept_on_average_rating_created_at on posts
  Filter: (metadata @> '{"source": "obd"}'::jsonb)
```

Same small-table story: the GIN on `metadata` exists (`jsonb_path_ops`, sized for `@>`) and the planner ignored it because a sequential-ish index walk is cheaper at n=4. At real volume we would look for a Bitmap Index Scan on `index_posts_on_metadata`.

## Rating row lock

```sql
SELECT "ratings".* FROM "ratings"
WHERE "ratings"."user_id" = $1 AND "ratings"."post_id" = $2
FOR UPDATE
```

```
LockRows
  ->  Index Scan using index_ratings_on_user_id_and_post_id on ratings
        Index Cond: ((user_id = $1) AND (post_id = $2))
```

The unique pair index is the lookup for the correctness lock. That should stay an Index Scan at any scale.

## Rating stats write

```sql
UPDATE posts
SET ratings_sum = ratings_sum + $1,
    ratings_count = ratings_count + $2,
    average_rating = ...
WHERE id = $3
```

```
Update on posts
  ->  Index Scan using posts_pkey on posts
        Index Cond: (id = $3)
```

Point update by primary key. Incremental stats stay O(1) per write. We would not want a plan that `SUM`s the ratings table here.
