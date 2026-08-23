# frozen_string_literal: true

require "rails_helper"

RSpec.describe User do
  subject(:user) { build(:user) }

  it { is_expected.to have_secure_password }
  it { is_expected.to have_many(:ratings).dependent(:destroy) }
  it { is_expected.to validate_presence_of(:username) }
  it { is_expected.to validate_presence_of(:email) }
  it { is_expected.to validate_uniqueness_of(:username) }
  it { is_expected.to validate_uniqueness_of(:email).ignoring_case_sensitivity }
  it { is_expected.to validate_length_of(:username).is_at_least(3).is_at_most(30) }
  it { is_expected.to validate_length_of(:password).is_at_least(8) }

  it "rejects usernames with spaces or symbols" do
    user.username = "not valid!"
    expect(user).not_to be_valid
    expect(user.errors[:username]).to be_present
  end

  it "allows usernames that differ only by case" do
    create(:user, username: "Kirby")
    expect(build(:user, username: "kirby")).to be_valid
  end

  it "stores email in lowercase" do
    user.email = "Kirby@Example.com"
    user.save!
    expect(user.reload.email).to eq("kirby@example.com")
  end

  describe "#as_public_json" do
    it "omits password_digest" do
      user.save!
      expect(user.as_public_json.keys).to match_array(%w[id username email created_at updated_at])
    end
  end
end
