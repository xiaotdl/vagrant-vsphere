require 'vagrant'

require 'rbvmomi'

require_relative '../config_base'
require_relative 'host_network_security_policy'

module VagrantPlugins
  module VSphere
    class Config < ConfigBase
      class HostNetworkPolicy < ConfigBase

        config_field_forward :security, HostNetworkSecurityPolicy

        # --- vSphere API mapping ---

        VIM = RbVmomi::VIM

        def prepare_spec
          VIM.HostNetworkPolicy(
            security: @security.prepare_spec
          )
        end

      end
    end
  end
end
