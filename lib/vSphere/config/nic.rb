require 'vagrant'

require_relative '../config_base'

module VagrantPlugins
  module VSphere
    class Config < ConfigBase
      class Nic < ConfigBase

        config_field_simple :index
        config_field_simple :portgroup

        config_field_simple :auto_config, default: true

        config_field_simple :allowGuestControl
        config_field_simple :startConnected
        config_field_simple :mac_addressType
        config_field_simple :mac

        ERR_PREFIX = 'vsphere.errors.config.nic'

        def validate_fields(errors, machine)
          super(errors, machine)

          networks = machine.config.vm.networks

          if @index.nil?
            errors << I18n.t("#{ERR_PREFIX}.requires_index")
          end

          if @portgroup.nil?
            errors << I18n.t("#{ERR_PREFIX}.requires_portgroup")
          else
            unless networks.any? { |type, net| net[:id] == @portgroup }
              errors << I18n.t("#{ERR_PREFIX}.requires_network",
                               index: @index,
                               network_id: @portgroup)
            end
          end

          if !@mac.nil? && @mac_addressType.nil?
            @mac_addressType = 'manual'
          end

          unless @mac_addressType.nil?
            unless %w(manual generated assigned).include?(@mac_addressType.downcase)
              errors << I18n.t("#{ERR_PREFIX}.invalid_mac_addressType",
                               value: @mac_addressType.downcase)
            end

            # vSphere expects capitilized value.
            @mac_addressType.capitalize!
          end
        end

      end
    end
  end
end
