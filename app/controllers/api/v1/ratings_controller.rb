# frozen_string_literal: true

module Api
  module V1
    class RatingsController < ApplicationController
      before_action :authenticate_user!

      def update
        post = Post.kept.find(params[:post_id])
        rating = Ratings::Upsert.new(user: current_user, post: post, value: rating_params[:value]).call

        if rating.errors.any?
          render_validation_error(rating)
        else
          render json: { rating: rating.as_api_json, post: post.reload.as_api_json }
        end
      end

      private

      def rating_params
        params.require(:rating).permit(:value)
      end
    end
  end
end
