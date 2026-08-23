# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rating do
  subject(:rating) { build(:rating) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:post) }
  it { is_expected.to validate_presence_of(:value) }
  it { is_expected.to validate_inclusion_of(:value).in_range(1..5) }
  it { is_expected.to validate_uniqueness_of(:user_id).scoped_to(:post_id) }
end
