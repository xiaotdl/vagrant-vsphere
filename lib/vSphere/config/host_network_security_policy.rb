require 'vagrant'

require 'rbvmomi'

require_relative '../config_base'

module VagrantPlugins
  module VSphere
    class Config < ConfigBase
      class HostNetworkSecurityPolicy < ConfigBase

        config_field_simple :allow_promiscuous
        config_field_simple :forged_transmits
        config_field_simple :mac_changes

        # --- vSphere API mapping ---

        VIM = RbVmomi::VIM

        def prepare_spec
          VIM.HostNetworkSecurityPolicy.tap do |policy|
            unless @allow_promiscuous.nil?
              policy[:allowPromiscuous] = !!@allow_promiscuous
            end
            unless @forged_transmits.nil?
              policy[:forgedTransmits] = !!@forged_transmits
            end
            unless @mac_changes.nil?
              policy[:macChanges] = !!@mac_changes
            end
          end
        end

      end
    end
  end
end
