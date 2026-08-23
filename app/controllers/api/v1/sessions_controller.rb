# frozen_string_literal: true

module Api
  module V1
    class SessionsController < ApplicationController
      def create
        user = find_user
        # Unknown emails skip bcrypt and return faster than known ones. A dummy
        # User.new.authenticate(params[:password]) on the nil path would close
        # that timing gap; left as a known tradeoff. See SOLUTION.md.
        if user&.authenticate(params[:password])
          render json: { user: user.as_public_json, token: Auth::Token.encode(user) }, status: :ok
        else
          render_error(code: "unauthorized", message: "Invalid credentials", status: :unauthorized)
        end
      end

      private

      def find_user
        if params[:email].present?
          User.find_by(email: params[:email])
        elsif params[:username].present?
          User.find_by(username: params[:username])
        end
      end
    end
  end
end
