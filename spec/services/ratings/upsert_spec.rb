# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ratings::Upsert do
  let(:author) { create(:user) }
  let(:rater) { create(:user) }
  let(:post) { create(:post, user: author) }

  def upsert(user, value)
    described_class.new(user:, post:, value:).call
  end

  it "inserts a rating and increments cached stats" do
    rating = upsert(rater, 4)

    expect(rating).to be_persisted
    expect(rating.value).to eq(4)
    post.reload
    expect(post.ratings_count).to eq(1)
    expect(post.ratings_sum).to eq(4)
    expect(post.average_rating).to eq(4)
  end

  it "updates the same user's rating without changing the count" do
    upsert(rater, 4)
    rating = upsert(rater, 2)

    expect(rating.value).to eq(2)
    expect(rater.ratings.where(post:).count).to eq(1)
    post.reload
    expect(post.ratings_count).to eq(1)
    expect(post.ratings_sum).to eq(2)
    expect(post.average_rating).to eq(2)
  end

  it "averages across users from the cached columns" do
    upsert(rater, 4)
    upsert(create(:user), 5)

    post.reload
    expect(post.ratings_count).to eq(2)
    expect(post.ratings_sum).to eq(9)
    expect(post.average_rating).to eq(4.5)
  end

  it "leaves stats unchanged when the value is invalid" do
    rating = upsert(rater, 9)

    expect(rating).not_to be_persisted
    expect(rating.errors).to be_of_kind(:value, :inclusion)
    post.reload
    expect(post.ratings_count).to eq(0)
    expect(post.ratings_sum).to eq(0)
    expect(post.average_rating).to be_nil
  end

  it "is a no-op when the same user submits the same value" do
    upsert(rater, 3)
    expect { upsert(rater, 3) }.not_to change { post.reload.updated_at }
    post.reload
    expect(post.ratings_count).to eq(1)
    expect(post.ratings_sum).to eq(3)
  end

  it "locks the rating row before reading the previous value" do
    upsert(rater, 2)

    sql = []
    callback = lambda { |*, payload| sql << payload[:sql] }

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      upsert(rater, 4)
    end

    expect(sql.grep(/FOR UPDATE/i)).to be_present
  end

  it "retries an insert uniqueness race once as an update" do
    first = true
    allow_any_instance_of(Rating).to receive(:save!).and_wrap_original do |method|
      if first
        first = false
        now = Time.current
        Rating.insert_all!([ { user_id: rater.id, post_id: post.id, value: 2, created_at: now, updated_at: now } ])
        Post.where(id: post.id).update_all(ratings_count: 1, ratings_sum: 2, average_rating: 2)
        raise ActiveRecord::RecordNotUnique, "PG::UniqueViolation: index_ratings"
      end
      method.call
    end

    rating = upsert(rater, 5)

    expect(rating.value).to eq(5)
    expect(rater.ratings.where(post:).count).to eq(1)
    post.reload
    expect(post.ratings_count).to eq(1)
    expect(post.ratings_sum).to eq(5)
    expect(post.average_rating).to eq(5)
  end

  it "enqueues a notification after a successful write" do
    expect { upsert(rater, 4) }.to have_enqueued_job(Ratings::NotifyJob)
  end
end
