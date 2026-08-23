# frozen_string_literal: true

require "rails_helper"

RSpec.describe Timeline::WarmJob do
  it "populates the first page cache" do
    create(:post, title: "Warm")

    described_class.perform_now

    allow(Post).to receive(:kept).and_call_original
    Timeline::Feed.new.call
    expect(Post).not_to have_received(:kept)
  end
end
