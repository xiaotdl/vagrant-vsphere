require 'vagrant'

require 'rbvmomi'

require_relative '../config_base'
require_relative 'host_network_policy'

module VagrantPlugins
  module VSphere
    class Config < ConfigBase
      class Portgroup < ConfigBase

        config_field_simple :name
        config_field_forward :policy, HostNetworkPolicy
        config_field_simple :vlan_id
        config_field_simple :vswitch

        config_field_simple :auto_delete, default: true

        ERR_PREFIX = 'vsphere.errors.config.portgroup'

        def validate_fields(errors, machine)
          super(errors, machine)

          networks = machine.config.vm.networks

          if @name.nil?
            errors << I18n.t("#{ERR_PREFIX}.requires_name")
            return
          end

          if @name.length >= 64
            errors << I18n.t("#{ERR_PREFIX}.name_too_long",
                             name: @name,
                             exceeding: '^' * (@name.length - 63)
                            )
          end

          unless networks.any? { |type, net| net[:id] == @name }
            errors << I18n.t("#{ERR_PREFIX}.requires_network",
                             name: @name)
          end

          #if @vswitch.nil?
          #  errors << I18n.t("#{ERR_PREFIX}.requires_vswitch",
          #                  name: @name)
          #end
        end

        # --- vSphere API mapping ---

        VIM = RbVmomi::VIM

        def prepare_spec
          VIM.HostPortGroupSpec.tap do |spec|
            spec[:name] = @name
            spec[:policy] = if @policy.nil?
                              VIM.HostNetworkPolicy()
                            else
                              @policy.prepare_spec
                            end
            spec[:vlanId] = @vlan_id
            spec[:vswitchName] = @vswitch
          end
        end

      end
    end
  end
end
