# frozen_string_literal: true

module Api
  module V1
    class PostsController < ApplicationController
      include Pagy::Method

      before_action :authenticate_user!

      def index
        pagy, posts = pagy(:offset, posts_scope)
        render json: { posts: posts.map(&:as_api_json), pagination: pagination_payload(pagy) }
      end

      def show
        post = Post.kept.find(params[:id])
        enqueue_view_increment(post.id)
        render json: { post: post.as_api_json }
      end

      def create
        post = current_user.posts.new(post_params)
        if post.save
          Timeline::Feed.invalidate
          render json: { post: post.as_api_json }, status: :created
        else
          render_validation_error(post)
        end
      end

      def update
        post = current_user.posts.kept.find(params[:id])
        if post.update(post_update_params)
          Timeline::Feed.invalidate
          render json: { post: post.as_api_json }
        else
          render_validation_error(post)
        end
      end

      def destroy
        post = current_user.posts.kept.find(params[:id])
        post.soft_delete
        Timeline::Feed.invalidate
        head :no_content
      end

      private

      def posts_scope
        relation = Post.kept.includes(:user).order(created_at: :desc)
        relation = relation.with_metadata(metadata_filter) if metadata_filter
        relation
      end

      def metadata_filter
        raw = params[:metadata]
        return unless raw.is_a?(ActionController::Parameters)

        raw.permit!.to_h.presence
      end

      def post_params
        params.require(:post).permit(:title, :body, metadata: {})
      end

      def post_update_params
        params.require(:post).permit(:title, :body, :lock_version, metadata: {}).tap do |permitted|
          permitted.require(:lock_version)
        end
      end

      def enqueue_view_increment(post_id)
        Posts::IncrementViewsJob.perform_later(post_id)
      rescue Redis::BaseError, RedisClient::Error
        Post.where(id: post_id).update_all("views_count = views_count + 1")
      end

      def pagination_payload(pagy)
        {
          page: pagy.page,
          limit: pagy.limit,
          count: pagy.count,
          pages: pagy.pages
        }
      end
    end
  end
end
