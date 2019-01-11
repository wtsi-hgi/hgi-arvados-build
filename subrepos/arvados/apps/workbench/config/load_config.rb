# Copyright (C) The Arvados Authors. All rights reserved.
#
# SPDX-License-Identifier: AGPL-3.0

# This file must be loaded _after_ secret_token.rb if secret_token is
# defined there instead of in config/application.yml.

$application_config = {}

%w(application.default application).each do |cfgfile|
  path = "#{::Rails.root.to_s}/config/#{cfgfile}.yml"
  if File.exists? path
    yaml = ERB.new(IO.read path).result(binding)
    confs = YAML.load(yaml, deserialize_symbols: true)
    $application_config.merge!(confs['common'] || {})
    $application_config.merge!(confs[::Rails.env.to_s] || {})
  end
end

ArvadosWorkbench::Application.configure do
  nils = []
  $application_config.each do |k, v|
    # "foo.bar: baz" --> { config.foo.bar = baz }
    cfg = config
    ks = k.split '.'
    k = ks.pop
    ks.each do |kk|
      cfg = cfg.send(kk)
    end
    if v.nil? and cfg.respond_to?(k) and !cfg.send(k).nil?
      # Config is nil in *.yml, but has been set already in
      # environments/*.rb (or has a Rails default). Don't overwrite
      # the default/upstream config with nil.
      #
      # After config files have been migrated, this mechanism should
      # be removed.
      Rails.logger.warn <<EOS
DEPRECATED: Inheriting config.#{ks.join '.'} from Rails config.
            Please move this config into config/application.yml.
EOS
    elsif v.nil?
      # Config variables are not allowed to be nil. Make a "naughty"
      # list, and present it below.
      nils << k
    else
      cfg.send "#{k}=", v
    end
  end
  if !nils.empty? and not ::Rails.groups.include?('assets')
    raise <<EOS
#{::Rails.groups.include?('assets')}
Refusing to start in #{::Rails.env.to_s} mode with missing configuration.

The following configuration settings must be specified in
config/application.yml:
* #{nils.join "\n* "}

EOS
  end
  # Refuse to start if keep-web isn't configured
  if not (config.keep_web_url or config.keep_web_download_url) and not ::Rails.groups.include?('assets')
    raise <<EOS
Refusing to start in #{::Rails.env.to_s} mode with missing configuration.

Keep-web service must be configured in config/application.yml:
* keep_web_url
* keep_web_download_url

EOS
  end
end
