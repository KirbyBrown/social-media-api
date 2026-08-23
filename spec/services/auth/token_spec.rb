# frozen_string_literal: true

require "rails_helper"

RSpec.describe Auth::Token do
  let(:user) { create(:user) }

  describe ".encode / .decode" do
    it "round-trips the user id" do
      payload = described_class.decode(described_class.encode(user))
      expect(payload["sub"]).to eq(user.id)
    end

    it "returns nil for a tampered token" do
      expect(described_class.decode("not-a-token")).to be_nil
    end

    it "returns nil for an expired token" do
      token = travel_to(2.days.ago) { described_class.encode(user) }
      expect(described_class.decode(token)).to be_nil
    end
  end
end
