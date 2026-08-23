# Solution notes

How each requirement is implemented and why, in the same order as the challenge doc: core requirements first, then the optionals I completed (1: Extreme Concurrency Handling, 2: Advanced Database Optimization, 5: Observability & Error Handling). Measured query plans are in [docs/query-plans.md](docs/query-plans.md).

I built this with AI assistance. Places where the AI got something wrong and I corrected it are labeled **AI adjustment** so they are easy to tell apart from design decisions.

## Approach

**Decision: do expensive work on write, keep reads simple.** Rating writes maintain cached `ratings_count`, `ratings_sum`, and `average_rating` columns on the post inside the write transaction. The timeline is then a single indexed query with no aggregation. The `ratings` table stays the source of truth, so the cached columns can be rebuilt if they ever drift.

The schema is additive. Ratings, cached rating columns, `lock_version`, and JSONB metadata each arrived in their own migration. Reverting one feature does not rewrite the posts table.

## 1. User management

**Decision: JWT over Devise.** This is an API with no cookie sessions. `has_secure_password` plus the `jwt` gem covers the whole feature. Devise would bring Recoverable, Rememberable, view helpers, and Warden for a problem a few small classes solve. Shipped as `POST /api/v1/users` and `POST /api/v1/sessions`. The token is a 24-hour HS256 JWT (`Auth::Token`) signed with `secret_key_base`.

Email is normalized to lowercase (Rails `normalizes` applies to finders too, so login with mixed case works). Username uniqueness is case-sensitive on purpose: `Kirby` and `kirby` can both exist and display names stay as typed. Sessions accept email or username plus password and always return the same 401, so the response body does not reveal which field failed.

Known tradeoff, left open: unknown emails skip bcrypt and return faster than known ones. A dummy `User.new.authenticate` on the nil path would close that timing oracle. This API is not handling money, so I noted it and moved on.

**AI adjustment:** the first version of registration relied on uniqueness validations alone. Two concurrent signups with the same username pass validation and the loser raises `ActiveRecord::RecordNotUnique`, which returned a 500. I added a `rescue_from` that maps it to the same 422 shape as the validation failure. Validation for the common case, unique index for correctness, rescue for the race.

## 2. Posts

Soft delete is an explicit `scope :kept, -> { where(deleted_at: nil) }` applied at each read site. No `default_scope`; a hidden `deleted_at: nil` filter leaks into associations, jobs, and one-off lookups in ways that are hard to reason about later. Title is capped at 100 characters in both the validation and the column definition, body at 1000. Pagination is Pagy, 20 per page, with a `{ page, limit, count, pages }` envelope.

View counts increment through a Sidekiq job rather than on the request. Details, including the failure modes, are under Optional 1.

**AI adjustment:** `soft_delete` was written as `update(deleted_at: Time.current)`, which runs validations, returns `false` on failure, and the controller rendered 204 regardless. A silent failure path. It is now `touch(:deleted_at)`: setting a tombstone should not require the record to currently pass validations, and `touch` cannot quietly no-op.

## 3. Rating system

**Decision: incremental stat updates under a row lock.** Recomputing `SUM`/`COUNT` from rating rows on every write is O(ratings per post) and becomes the expensive part of a write on a hot post. Instead, inside one transaction: upsert the rating, then apply a delta. Insert adds `value` to the sum and 1 to the count; update adds `new - old` to the sum. `average_rating` is derived from the two columns in the same UPDATE. The delta runs through `update_all` so it does not bump `lock_version` or fire callbacks. A same-value resubmit writes nothing.

**AI adjustment:** the first version read the old rating value outside the transaction with no lock. Two concurrent updates of the same rating (2 to 4, and 2 to 5) would both read 2, apply +2 and +3, and leave `ratings_sum` permanently wrong. The read now happens inside the transaction under `SELECT ... FOR UPDATE` (`@user.ratings.lock.find_or_initialize_by`), so same-user writers serialize and the second one computes its delta from the first one's committed value. That row lock is the correctness layer.

**AI adjustment:** the first-insert race returned the wrong answer. `SELECT FOR UPDATE` on zero rows takes no gap lock in Postgres, so two first ratings can both attempt the insert and the loser hits the unique index. The original code surfaced that as 422 "already taken", which blames the client for a server-side race on an upsert endpoint. The service now rescues `RecordNotUnique` and retries once; the second pass finds the row, locks it, and takes the update path. The generic `RecordNotUnique` mapping remains for signup, where 422 is the right answer.

The Redis lock around the rating write (`ratings:post:{id}`) is contention relief for hot posts, not the correctness mechanism. If Redis is down or the lock stays busy past a short wait, the write proceeds and the row lock keeps the sums correct. See Optional 1 for the lock itself.

**AI adjustment:** the Redis-down path had a hole that only showed up in manual testing. The lock degraded correctly, the transaction committed, and then `NotifyJob.perform_later` raised `RedisClient::CannotConnectError`, turning a successful write into a 500. The enqueue is now best-effort: Redis down logs a warning and skips the notification, and the client gets the 200 with the persisted rating. As a backstop, a Redis connection error that escapes any controller path renders a 503 in the standard error shape instead of the default 500 body.

## 4. Activity timeline

`GET /api/v1/timeline?page=&min_rating=` runs `Post.kept.includes(:user).order(created_at: :desc)`, adding `average_rating >= min_rating` when the param is present. Unrated posts have a null average and drop out of the filtered feed, which is the intended reading of "minimum average rating". `min_rating` outside 1 to 5 is a 400. Author info rides along via the eager-loaded user; a spec pins the feed to exactly one users query.

**Decision: cache the first page, version key plus short TTL.** Page 1 is nearly all the traffic. The cache key includes a version number that write paths bump (post create, update, soft delete, and successful rating writes; view increments do not, or a hot post would thrash the feed). The 30-second TTL is the safety net for a missed invalidation, and it also caps staleness across processes when the cache store is per-process memory. Later pages always hit the database.

In production the store is Redis. Rails' `redis_cache_store` swallows connection errors by default and treats them as misses, and that is the layer I rely on: a down Redis means live reads, not exceptions. The explicit rescue in `Timeline::Feed` is a second net for the memory store and for specs that force a raise. `invalidate` no-ops when it cannot reach Redis; the next request reads live.

`Timeline::WarmJob` refills page 1 after each invalidation. A burst of writes piles up redundant warms of the same page, which is cheap at this scale. At real write volume I would make the job unique-until-executing or debounce it with a short "warm queued" key.

## 5. API design

Everything lives under `/api/v1/`. Handled API errors use `{ "error": { "code", "message", "details" } }`, with 400, 401, 404, 409, 422, 503 used where they mean what they say. Health is a probe payload, not this object. Unhandled exceptions still get Rails' default 500 body. Ownership checks scope to `current_user.posts`, so another user's post is a 404 rather than confirming the resource exists.

A Redis connection error that escapes a write path is rescued into 503 in the standard shape. Rating writes should not hit that: the lock and the notification enqueue both degrade, and the client gets 200 with the persisted rating.

Rate limiting is a no-op `RateLimitStub` middleware, which is the "at least stub the middleware" reading of the requirement. The real version is Rack::Attack or a token bucket keyed by IP and user, returning 429 in the standard error shape. The optional budget went to locking, jobs, and indexes instead. Stubbed behavior carries an in-code comment pointing at the real approach; this file covers the same ground in prose.

**AI adjustment:** a request body missing the documented root key raised `ActionController::ParameterMissing` and Rails answered with its own default 400 body, breaking the consistent error format. `ErrorResponses` now rescues it into the standard shape. While fixing it I found Rails was wrapping bare JSON into `params[:user]`, so a body with no `user` key still passed `require`. `wrap_parameters` is off; the documented root key is actually required.

**AI adjustment:** the stub middleware was generated in `app/middleware/` and loaded with a manual `require` from an initializer. Every `app/*` directory is on Zeitwerk's autoload paths, and requiring files out from under Zeitwerk is the exact anti-pattern the Rails autoloading guide warns about. It now lives in `lib/middleware/`, which is excluded via `autoload_lib(ignore:)`, and the require is legitimate.

## 6. Testing and documentation

Specs land in the same commit as the behavior they lock: request specs for every endpoint, model and service specs for validations, soft delete, cached averages, and lock conflicts. API documentation is rswag, so the request specs and the OpenAPI file cannot drift apart. `swagger/v1/swagger.yaml` is committed so a fresh clone serves `/api-docs` without a generation step; regenerate with `bundle exec rake rswag:specs:swaggerize`. SimpleCov does not start when rspec runs with `--dry-run`: swaggerize executes no code, and printing a near-zero coverage number for it would only mislead.

`bin/setup` checks the Ruby version, checks that Postgres is answering, prepares and seeds the database, and fails with a message naming the missing dependency. Seeds are idempotent and route ratings through `Ratings::Upsert` so the cached averages are computed by the real write path, not hand-set.

**AI adjustment:** the generated SimpleCov config called a `skip` method that does not exist in SimpleCov's API. The first test run crashed on it. `SimpleCov.start "rails"` alone is correct; the Rails profile already filters spec, config, and db paths.

**AI adjustment:** the rswag gems were initially grouped under development and test while the routes mounted `Rswag::Ui::Engine` unconditionally. Production boot would raise `NameError`. `rswag-api` and `rswag-ui` moved to the default group; `rswag-specs` stays in development and test.

## 7. Performance

The hot query is the timeline: `WHERE deleted_at IS NULL ORDER BY created_at DESC LIMIT 20`. It is served by a partial index, `ON posts (created_at DESC) WHERE deleted_at IS NULL`, which is smaller than a composite starting with `deleted_at` and matches the `kept` scope exactly.

**AI adjustment:** the first version of the timeline shipped without that index, leaving the query to sort the full kept set on every cache miss. The requirement names 1M+ rows as the target; I added the partial index in the timeline slice rather than deferring it to the optional round.

Rating stat updates are point UPDATEs by primary key. Everything a read needs is on the posts row, so no query aggregates the ratings table at read time. Captured plans for the timeline, the metadata filter, and the rating write path are in [docs/query-plans.md](docs/query-plans.md), including notes on what the plans should look like at volume versus what a tiny local table shows.

## Optional 1: Extreme Concurrency Handling

**Optimistic locking.** `lock_version` on posts, added in its own migration. PATCH requires the client to send the `lock_version` it read; a stale value is a 409 with code `conflict`. Requiring the field is the point: without it, a fresh read-modify-write can never conflict and the lock checks nothing.

**AI adjustment:** view counts originally went through `increment_counter`, which looked like the right API. Once `lock_version` exists, Rails' optimistic locking module merges a `lock_version` bump into counter updates, so background view increments would collide with real edits. Views (and rating deltas) use raw `update_all`, which touches exactly the named columns. Only title and body edits go through the Active Record object and the lock.

**Redis lock.** `Locks::RedisLock` is SET NX EX with a random token and a Lua compare-and-delete release, a few short acquisition attempts, then proceed without the lock. It degrades open by design: the rating row lock is what keeps the numbers correct, so a dead Redis or a busy lock must not block writes. A spec covers the Redis-down path.

**Sidekiq jobs.** The three tasks named in the prompt: `Ratings::NotifyJob` (a logged stub; the real version is a mailer or push provider with the job as the retry boundary), `Posts::IncrementViewsJob`, and `Timeline::WarmJob`. `GET /posts/:id` returns the pre-increment count and the OpenAPI description says the count is eventually consistent. If enqueueing fails because Redis is down, view increments run inline so the count is not dropped, and rating notifications are skipped (the rating already committed).

View increments are at-least-once. A worker that dies after the UPDATE but before the ack will double-count on retry. Exact counts need a per-view event row; approximate is the right tradeoff for a view counter.

**AI adjustment:** retries were first configured as `retry_on StandardError, attempts: 5`, with a comment claiming failures then land in Sidekiq's dead set. That is not what happens: when `retry_on` exhausts its attempts it re-raises, and Sidekiq applies its own default of 25 retries over about three weeks before anything goes to the dead set. Two stacked retry layers, and "fails loudly" quietly becomes "fails eventually". I removed `retry_on` and set `sidekiq_options retry: 5`, one layer, matching Sidekiq's own recommendation for ActiveJob. After five failures the job is dead and visible. `discard_on ActiveJob::DeserializationError` stays; a deleted record is not worth retrying.

**Connection pooling.** The pool sizes from `RAILS_MAX_THREADS` and must cover Puma threads in web processes and Sidekiq concurrency in workers, per process. Undersized pools show up as `ActiveRecord::ConnectionTimeoutError` under load. At real scale the answer is PgBouncer in transaction mode in front of Postgres, not a hand-rolled pooler. The same note sits next to `pool` in `database.yml`.

## Optional 2: Advanced Database Optimization

**Concurrent index builds.** The indexes added after tables had data use `algorithm: :concurrently` with `disable_ddl_transaction!`, the shape that keeps a live table readable during the build. Operational note: a failed `CREATE INDEX CONCURRENTLY` leaves an INVALID index that serves no reads but still costs writes; the fix is `DROP INDEX` and rebuild, and rerunning the migration will not clean it up.

**The min-rating index and what it can and cannot do.** `ON posts (average_rating, created_at DESC) WHERE deleted_at IS NULL` serves the filtered timeline when the rating filter is selective. It cannot produce rows in `created_at` order: the range predicate is on the leading column, so matching entries are ordered by `(average_rating, created_at)`, and Postgres must collect and top-N sort them. Bitmap scan plus sort is the realistic good plan, and it is cheap exactly when the filter is selective. When most posts pass the cut, walking the `created_at` partial and filtering wins instead.

**AI adjustment:** the first draft of the query-plans doc claimed the goal at scale was "an Index Scan on the min-rating index, not a Filter". Wrong, for the ordering reason above. [docs/query-plans.md](docs/query-plans.md) now tells the corrected story.

**JSONB metadata.** `posts.metadata` (default `{}`) stands in for scan-payload data. Create and update accept a metadata object, and `GET /api/v1/posts?metadata[source]=obd` filters with jsonb containment (`@>`). The GIN index uses `jsonb_path_ops`: smaller and faster than the default opclass, at the cost of not serving key-existence operators, which nothing queries. Query-string values are strings, so `?metadata[count]=2` will not match a stored JSON number; the OpenAPI description says so, and numeric filters belong in JSON bodies.

**Explained, not built:**

- *Sharding.* The natural shard key is `user_id`, which keeps a user's posts and ratings together for writes. The timeline is then a cross-shard read, and that is the hard part: fan-out on read, a timeline service, or a denormalized feed table. I would not shard at this scale. One Postgres primary, read replicas, and the write-time projections above are the right next step.
- *Full-text search.* A generated `tsvector` column on posts with a GIN index, queried through `websearch_to_tsquery`.
- *Materialized view for the timeline.* The write-time rating columns already keep the read query simple. A matview wins when many readers need a heavy join you do not want to pay per write; refresh staleness and locking are the costs. Not the right fit as this timeline's primary read path.

## Optional 5: Observability & Error Handling

`GET /api/v1/health` is unauthenticated and reports Postgres, Redis, and Sidekiq. Postgres failing is a 503; Redis or Sidekiq failing is a 200 with `ok: false` for that check, because the API genuinely serves reads without them. The payload is a probe shape (`status` plus per-subsystem `checks`), not the client error shape.

Rescues are narrow: connection-level errors from ActiveRecord, PG, Redis, and RedisClient. Anything else propagates. Swallowing a `NoMethodError` into a healthy-looking 200 would hide a bug, which is the opposite of failing loudly. A spec asserts unexpected errors raise.

**AI adjustment:** the checks originally returned raw `e.message` to the caller. Postgres and Redis connection errors embed hosts, ports, and URLs, and this endpoint is public, so that was advertising internal topology. The public payload now carries the exception class name only; the full message goes to the log, where the operator who needs it is already looking.

Cost control: the Redis ping uses 200ms timeouts, the Sidekiq probe is skipped when the Redis ping already failed (it would only re-time-out against the same host), and the whole result is cached for 3 seconds. An unauthenticated endpoint that fans out to three dependencies should not be an amplification vector, and a cached 503 also avoids hammering Postgres during the exact outage the probe is reporting. Postgres uses `ActiveRecord::Base.with_connection`, which releases the checkout immediately; bare `connection` has been soft-deprecated since Rails 7.2.

`workers` in the Sidekiq check is a count, not a fail condition. Zero workers with a reachable Redis means jobs queue but do not run; the box still serves reads, and the count makes the situation visible.

## Challenges

The three problems that took real thought are written up in their sections: making the incremental rating stats safe under concurrency (section 3, two adjustments), untangling the stacked ActiveJob and Sidekiq retry layers (Optional 1), and getting the min-rating index story right (Optional 2). Each one started with plausible-looking AI output that was wrong in a way that only shows up under load or in production.

## With more time

- Replace `RateLimitStub` with Rack::Attack or a token bucket keyed by IP and user, returning 429 in the standard error shape.
- Cursor pagination for the timeline. Offset pagination runs a `COUNT(*)` over kept posts on every uncached load, and at 1M rows that count is the expensive half of the query. A `created_at, id` cursor drops the count and the deep-offset scans.
- Close the login timing oracle with a dummy bcrypt comparison on the unknown-user path.
- Dedupe timeline cache warms (unique-until-executing or a debounce key).
- Bulk-generate a few hundred thousand posts and re-capture the query plans at volume. The committed plans come from a small table and say so; plans captured at volume would carry more weight. No load benchmarks were run.
- Idempotency keys on POST endpoints.
- Containerize for deploy: app, Sidekiq, Postgres, Redis.

## Not built, on purpose

- **Docker for local setup.** The prompt calls containerization a plus, and a half-working compose file is worse than none. `bin/setup` against local Postgres is the supported path; containerization is listed above as a deploy concern.
- **GraphQL.** The prompt requires versioned REST, so this app is REST only. Mixing both API styles in one small codebase buys the maintenance cost of each.
- **Devise.** Covered in section 1.
- **Sharding, sagas, bloom-filter ranking, recommendation engines.** Out of proportion for the problem. Sharding got a written approach above because the prompt asks for one.
- No Action Mailer, Hotwire, JavaScript, Jbuilder, or Minitest in the app skeleton.

## Gems

Few and well-known: `jwt` and `bcrypt` for auth, `pagy` for pagination, `sidekiq` and `redis`, `rswag` for spec-generated API docs, `rspec-rails`, `factory_bot_rails`, `shoulda-matchers`, `simplecov`. The auth flow, error format, rating math, and the Redis lock are written in the app; the gems cover commodity parts.

One oddity: `ostruct` is bundled explicitly. Ruby 4 removed it from the default gems and rswag-ui requires it at boot. Vendoring a monkey-patch into rswag to avoid OpenStruct in a docs path is not a trade worth making. App code that needs a value object uses `Data` (see `Health::Check::Result`).
