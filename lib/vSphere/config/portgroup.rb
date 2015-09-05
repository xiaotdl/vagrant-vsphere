require 'vagrant'

require_relative '../config_base'

module VagrantPlugins
  module VSphere
    class Config < ConfigBase
      class Portgroup < ConfigBase

        config_field_simple :name
        config_field_simple :vswitch
        config_field_simple :vlan_id

        config_field_simple :auto_delete, default: true

        ERR_PREFIX = 'vsphere.errors.config.portgroup'

        def validate_fields(errors, machine)
          super(errors, machine)

          networks = machine.config.vm.networks

          if @name.nil?
            errors << I18n.t("#{ERR_PREFIX}.requires_name")
            return
          end

          if @name.length >= 32
            errors << I18n.t("#{ERR_PREFIX}.name_too_long",
                             name: @name,
                             exceeding: '^' * (@name.length - 31)
                            )
          end

          unless networks.any? { |type, net| net[:id] == @name }
            errors << I18n.t("#{ERR_PREFIX}.requires_network",
                             name: @name)
          end

          if @vswitch.nil?
            errors << I18n.t("#{ERR_PREFIX}.requires_vswitch",
                            name: @name)
          end
        end

      end
    end
  end
end
