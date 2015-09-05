begin
  require 'vagrant'
rescue LoadError
  raise 'The Vagrant vSphere plugin must be run within Vagrant.'
end

# This is a sanity check to make sure no one is attempting to install
# this into an early Vagrant version.
if Vagrant::VERSION < '1.5'
  fail 'The Vagrant vSphere plugin is only compatible with Vagrant 1.5+'
end

module VagrantPlugins
  module VSphere
    class Plugin < Vagrant.plugin('2')
      name 'vsphere'
      description 'Allows Vagrant to manage machines with VMWare vSphere'

      config(:vsphere, :provider) do
        # Config may throw errors and we need localization to show them.
        setup_i18n

        require_relative 'config'
        Config
      end

      provider(:vsphere, parallel: true) do
        # TODO: add logging

        # Return the provider
        require_relative 'provider'
        Provider
      end

      provider_capability('vsphere', 'public_address') do
        require_relative 'cap/public_address'
        Cap::PublicAddress
      end

      def self.setup_i18n
        I18n.load_path << File.expand_path('locales/en.yml', VSphere.source_root)
        I18n.reload!
      end

      LOG4R_PREFIX = "vagrant::providers::vcenter"

      # TODO This should be part of Vagrant, I think.
      def self.logger_for(klass)
        path = klass.name.split('::')

        if path.length && path[0] == 'VagrantPlugins'
          path.shift
          if path.length && path[0] == 'VSphere'
            path.shift
          end
        end

        path.map! do |c|
          c.gsub!(/([A-Z\d]+)([A-Z][a-z])/,'\1_\2')
          c.gsub!(/([a-z\d])([A-Z])/,'\1_\2')
          c.tr!("-", "_")
          c.downcase
        end

        Log4r::Logger.new("#{Plugin::LOG4R_PREFIX}::${path.join('::')")
      end
    end
  end
end
