# frozen_string_literal: true

module Timeline
  class Feed
    TTL = 30.seconds
    VERSION_KEY = "timeline/version"

    def initialize(page: 1, min_rating: nil)
      @page = page.to_i
      @page = 1 if @page < 1
      @min_rating = min_rating
    end

    def call
      if @page == 1
        # First page only. TTL is the safety net if an invalidation is missed. See SOLUTION.md.
        Rails.cache.fetch(cache_key, expires_in: TTL) { load_page }
      else
        load_page
      end
    end

    def self.invalidate
      Rails.cache.increment(VERSION_KEY)
    end

    private

    def cache_key
      [ "timeline", Rails.cache.read(VERSION_KEY) || 0, @page, @min_rating ]
    end

    def load_page
      relation = Post.kept.includes(:user).order(created_at: :desc)
      relation = relation.where(average_rating: @min_rating..) if @min_rating

      pagy = Pagy::Offset.new(
        count: relation.except(:includes, :order).count,
        limit: Pagy::OPTIONS[:limit],
        page: @page
      )

      {
        posts: pagy.records(relation).map(&:as_api_json),
        pagination: {
          page: pagy.page,
          limit: pagy.limit,
          count: pagy.count,
          pages: pagy.pages
        }
      }
    end
  end
end
