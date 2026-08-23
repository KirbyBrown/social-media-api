source "https://rubygems.org"

gem "rails", "~> 8.1.3"
gem "pg", "~> 1.5"
gem "puma", ">= 6.0"
gem "bcrypt", "~> 3.1.7"
gem "jwt"
gem "bootsnap", require: false
gem "ostruct"
gem "rswag-api"
gem "rswag-ui"
gem "tzinfo-data", platforms: %i[ windows jruby ]

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  gem "rspec-rails"
  gem "rswag-specs"
  gem "factory_bot_rails"
end

group :test do
  gem "simplecov", require: false
  gem "shoulda-matchers"
end
