# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ratings::NotifyJob do
  it "logs the stub notification" do
    rating = Ratings::Upsert.new(user: create(:user), post: create(:post), value: 4).call
    allow(Rails.logger).to receive(:info)

    described_class.perform_now(rating.id)

    expect(Rails.logger).to have_received(:info).with(/rating notification stub rating_id=#{rating.id}/)
  end

  it "no-ops when the rating is gone" do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
