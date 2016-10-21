require 'vagrant'

require 'rbvmomi'

require_relative '../config_base'
require_relative 'host_network_policy'

module VagrantPlugins
  module VSphere
    class Config < ConfigBase
      class Vswitch < ConfigBase

        config_field_simple :name
        config_field_simple :num_ports, default: 24

        config_field_forward :policy, HostNetworkPolicy

        config_field_simple :auto_delete, default: true

        ERR_PREFIX = 'vsphere.errors.config.vswitch'

        def validate_fields(errors, machine)
          super(errors, machine)

          if !@name.nil? && @name.length >= 32
            errors << I18n.t("#{ERR_PREFIX}.name_too_long",
                             name: @name,
                             exceeding: '^' * (@name.length - 31)
                            )
          end
        end

        # --- vSphere API mapping ---

        VIM = RbVmomi::VIM

        def prepare_spec
          VIM.HostVirtualSwitchSpec.tap do |spec|
            spec[:numPorts] = @num_ports

            unless @policy.nil?
              spec[:policy] = @policy.prepare_spec
            end
          end
        end

      end
    end
  end
end
            
