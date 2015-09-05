require 'vagrant'

require 'rbvmomi'

require_relative '../config_base'
require_relative 'customization/identity'

module VagrantPlugins
  module VSphere
    class Config < ConfigBase
      class Customization < ConfigBase

        config_field_typed :identity, Identity.new

        ERR_PREFIX = 'vsphere.errors.config.customization'

        def validate_fields(errors, machine)
          super(errors, machine)

          if @identity.nil?
            errors << I18n.t("#{ERR_PREFIX}.requires_identity")
          end
        end

        # --- vSphere API mapping ---

        VIM = RbVmomi::VIM

        def prepare_spec(nicSettingMap)
           VIM.CustomizationSpec(
            globalIPSettings: VIM.CustomizationGlobalIPSettings,
            identity: @identity.prepare_spec,
            nicSettingMap: nicSettingMap,
          )
        end

      end
    end
  end
end
