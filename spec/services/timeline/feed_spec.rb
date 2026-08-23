# frozen_string_literal: true

require "rails_helper"

RSpec.describe Timeline::Feed do
  def titles(page: 1, min_rating: nil)
    described_class.new(page:, min_rating:).call[:posts].map { |post| post["title"] }
  end

  it "returns kept posts newest first with author and rating stats" do
    author = create(:user, username: "kirby")
    create(:post, user: author, title: "Older", created_at: 2.days.ago)
    create(:post, user: author, title: "Newer", created_at: 1.hour.ago, average_rating: 4.5, ratings_count: 2)

    payload = described_class.new.call

    expect(payload[:posts].map { |post| post["title"] }).to eq(%w[Newer Older])
    expect(payload[:posts].first.fetch("user")).to include("username" => "kirby")
    expect(payload[:posts].first.fetch("ratings_count")).to eq(2)
    expect(payload[:posts].first.fetch("average_rating").to_d).to eq(4.5)
    expect(payload[:pagination]).to include(page: 1, count: 2)
  end

  it "omits soft-deleted posts" do
    create(:post, title: "Visible")
    create(:post, :deleted, title: "Gone")

    expect(titles).to eq([ "Visible" ])
  end

  it "filters on the cached average_rating" do
    create(:post, title: "Low", average_rating: 2)
    create(:post, title: "High", average_rating: 4.5)
    create(:post, title: "Unrated")

    expect(titles(min_rating: 4)).to eq([ "High" ])
  end

  it "eager loads authors in one users query" do
    create_list(:post, 3)
    sql = []
    callback = lambda { |*, payload| sql << payload[:sql] }

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      described_class.new.call
    end

    expect(sql.grep(/FROM "users"/i).size).to eq(1)
  end

  it "caches the first page and skips the cache on later pages" do
    create_list(:post, 21)

    allow(Post).to receive(:kept).and_call_original
    described_class.new(page: 1).call
    described_class.new(page: 1).call
    expect(Post).to have_received(:kept).once

    described_class.new(page: 2).call
    described_class.new(page: 2).call
    expect(Post).to have_received(:kept).exactly(3).times
  end

  it "serves a new first page after invalidate" do
    create(:post, title: "Before")
    expect(titles).to eq([ "Before" ])

    create(:post, title: "After")
    expect(titles).to eq([ "Before" ])

    described_class.invalidate
    expect(titles).to eq(%w[After Before])
  end
end
