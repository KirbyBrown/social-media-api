# frozen_string_literal: true

class ApplicationController < ActionController::API
  include ErrorResponses
  include Authenticatable

  # Require the documented root key. Do not wrap JSON into params[:user]. See SOLUTION.md.
  wrap_parameters false
end
