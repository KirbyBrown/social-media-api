# frozen_string_literal: true

require "rails_helper"

RSpec.describe Post do
  subject(:post) { build(:post) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to have_many(:ratings).dependent(:destroy) }
  it { is_expected.to validate_presence_of(:title) }
  it { is_expected.to validate_presence_of(:body) }
  it { is_expected.to validate_length_of(:title).is_at_most(100) }
  it { is_expected.to validate_length_of(:body).is_at_most(1000) }

  it "indexes kept posts by created_at desc for the timeline" do
    index = ActiveRecord::Base.connection.indexes(:posts).find { |entry| entry.columns == [ "created_at" ] }

    expect(index.where).to eq("(deleted_at IS NULL)")
    expect(index.orders).to eq(:desc)
  end

  describe ".kept" do
    it "excludes soft-deleted posts" do
      kept = create(:post)
      create(:post, :deleted)

      expect(described_class.kept).to contain_exactly(kept)
    end
  end

  describe "#soft_delete" do
    it "sets deleted_at without destroying the row" do
      post.save!
      post.soft_delete
      expect(post.reload.deleted_at).to be_present
      expect(described_class.exists?(post.id)).to be(true)
    end

    it "still works when the record is currently invalid" do
      post.save!
      post.title = ""
      expect(post).not_to be_valid
      post.soft_delete
      expect(post.reload.deleted_at).to be_present
    end
  end
end
