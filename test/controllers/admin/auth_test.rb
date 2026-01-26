# frozen_string_literal: true

require "test_helper"

class Admin::AuthTest < ActionDispatch::IntegrationTest
  def admin_credentials
    username = ENV.fetch("ADMIN_USERNAME", "admin")
    password = ENV.fetch("ADMIN_PASSWORD", "admin")
    ActionController::HttpAuthentication::Basic.encode_credentials(username, password)
  end

  test "admin routes require authentication" do
    get admin_specimen_assets_path
    assert_response :unauthorized
  end

  test "admin routes reject wrong credentials" do
    get admin_specimen_assets_path, headers: {
      "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("wrong", "wrong")
    }
    assert_response :unauthorized
  end

  test "admin routes accept correct credentials" do
    get admin_specimen_assets_path, headers: {
      "HTTP_AUTHORIZATION" => admin_credentials
    }
    assert_response :success
  end
end

