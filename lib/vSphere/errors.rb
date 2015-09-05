require 'vagrant'

module VagrantPlugins
  module VSphere
    module Errors
      class VSphereError < Vagrant::Errors::VagrantError
        error_namespace('vsphere.errors')
      end

      class Config < VSphereError
        error_namespace('vsphere.errors.config')
      end
    end
  end
end
