# frozen_string_literal: true

module Api
  module V1
    class PostsController < ApplicationController
      include Pagy::Method

      before_action :authenticate_user!

      def index
        pagy, posts = pagy(:offset, Post.kept.includes(:user).order(created_at: :desc))
        render json: { posts: posts.map(&:as_api_json), pagination: pagination_payload(pagy) }
      end

      def show
        post = Post.kept.find(params[:id])
        # increment_counter skips lock_version and callbacks. See SOLUTION.md.
        Post.increment_counter(:views_count, post.id)
        render json: { post: post.reload.as_api_json }
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
        if post.update(post_params)
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

      def post_params
        params.require(:post).permit(:title, :body)
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
