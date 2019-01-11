# Copyright (C) The Arvados Authors. All rights reserved.
#
# SPDX-License-Identifier: AGPL-3.0

ENV["RAILS_ENV"] = "test"
unless ENV["NO_COVERAGE_TEST"]
  begin
    verbose_orig = $VERBOSE
    begin
      $VERBOSE = nil
      require 'simplecov'
      require 'simplecov-rcov'
    ensure
      $VERBOSE = verbose_orig
    end
    class SimpleCov::Formatter::MergedFormatter
      def format(result)
        SimpleCov::Formatter::HTMLFormatter.new.format(result)
        SimpleCov::Formatter::RcovFormatter.new.format(result)
      end
    end
    SimpleCov.formatter = SimpleCov::Formatter::MergedFormatter
    SimpleCov.start do
      add_filter '/test/'
      add_filter 'initializers/secret_token'
      add_filter 'initializers/omniauth'
    end
  rescue Exception => e
    $stderr.puts "SimpleCov unavailable (#{e}). Proceeding without."
  end
end

require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'
require 'mocha'
require 'mocha/mini_test'

module ArvadosTestSupport
  def json_response
    Oj.strict_load response.body
  end

  def api_token(api_client_auth_name)
    api_client_authorizations(api_client_auth_name).api_token
  end

  def auth(api_client_auth_name)
    {'HTTP_AUTHORIZATION' => "OAuth2 #{api_token(api_client_auth_name)}"}
  end

  def show_errors model
    return lambda { model.errors.full_messages.inspect }
  end
end

class ActiveSupport::TestCase
  include FactoryGirl::Syntax::Methods
  fixtures :all

  include ArvadosTestSupport
  include CurrentApiClient

  teardown do
    Thread.current[:api_client_ip_address] = nil
    Thread.current[:api_client_authorization] = nil
    Thread.current[:api_client_uuid] = nil
    Thread.current[:api_client] = nil
    Thread.current[:user] = nil
    restore_configuration
  end

  def assert_equal(expect, *args)
    if expect.nil?
      assert_nil(*args)
    else
      super
    end
  end

  def assert_not_allowed
    # Provide a block that calls a Rails boolean "true or false" success value,
    # like model.save or model.destroy.  This method will test that it either
    # returns false, or raises a Permission Denied exception.
    begin
      refute(yield)
    rescue ArvadosModel::PermissionDeniedError
    end
  end

  def add_permission_link from_who, to_what, perm_type
    act_as_system_user do
      Link.create!(tail_uuid: from_who.uuid,
                   head_uuid: to_what.uuid,
                   link_class: 'permission',
                   name: perm_type)
    end
  end

  def restore_configuration
    # Restore configuration settings changed during tests
    $application_config.each do |k,v|
      if k.match(/^[^.]*$/)
        Rails.configuration.send (k + '='), v
      end
    end
  end

  def set_user_from_auth(auth_name)
    client_auth = api_client_authorizations(auth_name)
    Thread.current[:api_client_authorization] = client_auth
    Thread.current[:api_client] = client_auth.api_client
    Thread.current[:user] = client_auth.user
  end

  def expect_json
    self.request.headers["Accept"] = "text/json"
  end

  def authorize_with api_client_auth_name
    authorize_with_token api_client_authorizations(api_client_auth_name).api_token
  end

  def authorize_with_token token
    t = token
    t = t.api_token if t.respond_to? :api_token
    ArvadosApiToken.new.call("rack.input" => "",
                             "HTTP_AUTHORIZATION" => "OAuth2 #{t}")
  end

  def salt_token(fixture:, remote:)
    auth = api_client_authorizations(fixture)
    uuid = auth.uuid
    token = auth.api_token
    hmac = OpenSSL::HMAC.hexdigest('sha1', token, remote)
    return "v2/#{uuid}/#{hmac}"
  end

  def self.skip_slow_tests?
    !(ENV['RAILS_TEST_SHORT'] || '').empty?
  end

  def self.skip(*args, &block)
  end

  def self.slow_test(name, &block)
    define_method(name, block) unless skip_slow_tests?
  end
end

class ActionController::TestCase
  setup do
    @test_counter = 0
  end

  def check_counter action
    @test_counter += 1
    if @test_counter == 2
      assert_equal 1, 2, "Multiple actions in functional test"
    end
  end

  [:get, :post, :put, :patch, :delete].each do |method|
    define_method method do |action, *args|
      check_counter action
      super action, *args
    end
  end

  def self.suite
    s = super
    def s.run(*args)
      @test_case.startup()
      begin
        super
      ensure
        @test_case.shutdown()
      end
    end
    s
  end
  def self.startup; end
  def self.shutdown; end
end

class ActionDispatch::IntegrationTest
  teardown do
    Thread.current[:api_client_ip_address] = nil
    Thread.current[:api_client_authorization] = nil
    Thread.current[:api_client_uuid] = nil
    Thread.current[:api_client] = nil
    Thread.current[:user] = nil
  end
end

# Ensure permissions are computed from the test fixtures.
User.invalidate_permissions_cache
