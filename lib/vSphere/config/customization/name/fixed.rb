require 'vagrant'

require 'rbvmomi'

require_relative '../../../config_base'

module VagrantPlugins
  module VSphere
    class Config < ConfigBase
      class Customization < ConfigBase
        class Name
          class Fixed < ConfigBase

            config_field_simple :name

            def type_name
              ":fixed"
            end

            ERR_PREFIX = 'vsphere.errors.config.customization.name.fixed'

            def validate_fields(errors, machine)
              super(errors, machine)

              if @name.nil?
                errors << I18n.t("#{ERR_PREFIX}.requires_name")
              end
            end

            # --- vSphere API mapping ---

            VIM = RbVmomi::VIM

            def prepare_spec
              VIM.CustomizationFixedName(name: @name)
            end
          end
        end
      end
    end
  end
end
