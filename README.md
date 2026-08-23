# Social Media API

Rails 8.1 API-only app on Ruby 4.0.6 and PostgreSQL. JWT auth, posts with soft delete, ratings with incremental averages, a cached timeline, health checks, and Sidekiq jobs.

Design notes and tradeoffs are in [SOLUTION.md](SOLUTION.md). Captured `EXPLAIN` output is in [docs/query-plans.md](docs/query-plans.md). Interactive docs: `/api-docs` (`swagger/v1/swagger.yaml` is committed).

## Architecture in brief

Expensive work happens on write. Rating writes update cached `ratings_count`, `ratings_sum`, and `average_rating` columns on the post inside the same transaction, so timeline reads are a single indexed query with no aggregation. The first timeline page is cached with a version key that write paths bump, plus a short TTL as the safety net. View counts increment through a Sidekiq job instead of blocking the request. Reads keep working without Redis: caching degrades to live queries, and view increments fall back to inline.

## Optional requirements completed

- **1. Extreme Concurrency Handling.** Optimistic locking on post updates (409 on stale `lock_version`), a Redis lock around rating writes, and Sidekiq jobs for rating notifications, view counts, and timeline cache warming. Connection pooling is covered in [SOLUTION.md](SOLUTION.md).
- **2. Advanced Database Optimization.** Partial and concurrent indexes, JSONB `metadata` with a GIN index and containment queries, `EXPLAIN` output in [docs/query-plans.md](docs/query-plans.md). Sharding, full-text search, and the materialized view are explained but not built.
- **5. Observability & Error Handling.** `GET /api/v1/health` reports Postgres, Redis, and Sidekiq, and the API degrades gracefully when Redis is down.

## Setup

Use the Ruby in `.ruby-version` (rbenv, rvm, asdf, or chruby). PostgreSQL must be running.

Redis is optional. To exercise the Redis-backed pieces (Sidekiq jobs, the rating lock, production-style caching), start it first: `brew services start redis`, or just `redis-server`. Without it the API still boots and serves reads: view increments fall back to inline, rating writes rely on the row lock and skip the notification job, and `/api/v1/health` reports redis and sidekiq as `ok: false`. That health output is the expected degraded state, not a setup failure.

```bash
bin/setup
bin/rails s
```

`bin/setup` installs gems, checks Postgres, prepares the database, seeds, and boots Rails.

```bash
bundle exec rspec
bundle exec rake rswag:specs:swaggerize   # after request-spec changes
bundle exec sidekiq                       # jobs (needs Redis)
```

`REDIS_URL` defaults to `redis://localhost:6379/0`.

## Seeded login

Password for every seed user is `password123`.

| username | email |
| --- | --- |
| kirby | kirby@example.com |
| jack | jack@example.com |
| eric | eric@example.com |

Kirby has a kept OBD post and a soft-deleted draft. Jack has an unrated post. Eric has a 5-star post. Ratings go through `Ratings::Upsert` so the cached averages match.

## Example requests

```bash
curl -s http://localhost:3000/api/v1/health

curl -s -X POST http://localhost:3000/api/v1/users \
  -H 'Content-Type: application/json' \
  -d '{"user":{"username":"newuser","email":"new@example.com","password":"password123"}}'

curl -s -X POST http://localhost:3000/api/v1/sessions \
  -H 'Content-Type: application/json' \
  -d '{"email":"kirby@example.com","password":"password123"}'
```

Use the `token` from that response:

```bash
TOKEN=paste-token-here

curl -s http://localhost:3000/api/v1/timeline \
  -H "Authorization: Bearer $TOKEN"

curl -s 'http://localhost:3000/api/v1/timeline?min_rating=4' \
  -H "Authorization: Bearer $TOKEN"

# -g: curl treats [] as globs otherwise, and -s hides the failed request
curl -sS -g 'http://localhost:3000/api/v1/posts?metadata[source]=obd' \
  -H "Authorization: Bearer $TOKEN"

curl -s http://localhost:3000/api/v1/posts \
  -H "Authorization: Bearer $TOKEN"

curl -s -X PUT http://localhost:3000/api/v1/posts/<post_id>/rating \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"rating":{"value":4}}'
```

PATCH a post must send `lock_version` from the last read. A stale value is `409`. `GET /posts/:id` returns `views_count` before the Sidekiq increment; the count is eventually consistent.

Handled API errors use this shape. `/api/v1/health` is a probe payload (`status` plus `checks`), not this object. Redis-down on a write that only needs Postgres is still a 200; a path that still requires Redis and was not rescued is a 503 in this same shape. An unhandled exception (a bug) uses Rails' default 500 body, which is what development shows when something escapes.

```json
{ "error": { "code": "validation_failed", "message": "Validation failed", "details": {} } }
```
