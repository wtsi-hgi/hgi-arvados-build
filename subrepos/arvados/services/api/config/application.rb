# Copyright (C) The Arvados Authors. All rights reserved.
#
# SPDX-License-Identifier: AGPL-3.0

require File.expand_path('../boot', __FILE__)

require 'rails/all'
require 'digest'

module Kernel
  def suppress_warnings
    verbose_orig = $VERBOSE
    begin
      $VERBOSE = nil
      yield
    ensure
      $VERBOSE = verbose_orig
    end
  end
end

if defined?(Bundler)
  suppress_warnings do
    # If you precompile assets before deploying to production, use this line
    Bundler.require(*Rails.groups(:assets => %w(development test)))
    # If you want your assets lazily compiled in production, use this line
    # Bundler.require(:default, :assets, Rails.env)
  end
end

module Server
  class Application < Rails::Application
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    # Custom directories with classes and modules you want to be autoloadable.
    # config.autoload_paths += %W(#{config.root}/extras)

    # Only load the plugins named here, in the order given (default is alphabetical).
    # :all can be used as a placeholder for all plugins not explicitly named.
    # config.plugins = [ :exception_notification, :ssl_requirement, :all ]

    # Activate observers that should always be running.
    # config.active_record.observers = :cacher, :garbage_collector, :forum_observer
    config.active_record.schema_format = :sql

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    # config.i18n.default_locale = :de

    # Configure sensitive parameters which will be filtered from the log file.
    config.filter_parameters += [:password]

    # Load entire application at startup.
    config.eager_load = true

    config.active_record.raise_in_transactional_callbacks = true

    config.active_support.test_order = :sorted

    config.action_dispatch.perform_deep_munge = false

    I18n.enforce_available_locales = false

    # Before using the filesystem backend for Rails.cache, check
    # whether we own the relevant directory. If we don't, using it is
    # likely to either fail or (if we're root) pollute it and cause
    # other processes to fail later.
    default_cache_path = Rails.root.join('tmp', 'cache')
    if not File.owned?(default_cache_path)
      if File.exist?(default_cache_path)
        why = "owner (uid=#{File::Stat.new(default_cache_path).uid}) " +
          "is not me (uid=#{Process.euid})"
      else
        why = "does not exist"
      end
      STDERR.puts("Defaulting to memory cache, " +
                  "because #{default_cache_path} #{why}")
      config.cache_store = :memory_store
    else
      require Rails.root.join('lib/safer_file_store')
      config.cache_store = ::SaferFileStore.new(default_cache_path)
    end
  end
end
