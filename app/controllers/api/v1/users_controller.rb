# frozen_string_literal: true

module Api
  module V1
    class UsersController < ApplicationController
      def create
        user = User.new(user_params)
        if user.save
          render json: { user: user.as_public_json, token: Auth::Token.encode(user) }, status: :created
        else
          render_validation_error(user)
        end
      end

      private

      def user_params
        params.require(:user).permit(:username, :email, :password)
      end
    end
  end
end
