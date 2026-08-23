# Social Media API

Rails 8.1 API for the FIXD take-home. Ruby 4.0.6, PostgreSQL.

## Setup

Use the Ruby in `.ruby-version` (rbenv, rvm, asdf, or chruby all work). Then:

```bash
bin/setup
```

`bin/setup` installs gems, checks that PostgreSQL is running, prepares the database, and boots Rails. It exits with a message if Ruby or Postgres is missing.

```bash
bin/rails s
bundle exec rspec
```

Swagger UI is at `/api-docs`. `swagger/v1/swagger.yaml` is committed so a fresh clone can serve docs without an extra step. After request specs change, regenerate it:

```bash
bundle exec rake rswag:specs:swaggerize
```
