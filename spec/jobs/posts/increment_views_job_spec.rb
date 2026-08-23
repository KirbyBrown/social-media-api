# frozen_string_literal: true

require "rails_helper"

RSpec.describe Posts::IncrementViewsJob do
  it "increments views without bumping lock_version" do
    post = create(:post, views_count: 0)

    expect { described_class.perform_now(post.id) }.not_to change { post.reload.lock_version }
    expect(post.reload.views_count).to eq(1)
  end
end
