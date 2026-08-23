# frozen_string_literal: true

RSpec.configure do |config|
  config.before do
    allow_any_instance_of(Locks::RedisLock).to receive(:around).and_yield
  end
end
