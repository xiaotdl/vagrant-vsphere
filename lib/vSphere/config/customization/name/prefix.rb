require 'vagrant'

require 'rbvmomi'

require_relative '../../../config_base'

module VagrantPlugins
  module VSphere
    class Config < ConfigBase
      class Customization < ConfigBase
        class Name
          class Prefix < ConfigBase

            config_field_simple :base

            def type_name
              ":prefix"
            end

            ERR_PREFIX = 'vsphere.errors.config.customization.name.prefix'

            def validate_fields(errors, machine)
              super(errors, machine)

              if @base.nil?
                errors << I18n.t("#{ERR_PREFIX}.requires_base")
              end
            end

            # --- vSphere API mapping ---

            VIM = RbVmomi::VIM

            def prepare_spec
              VIM.CustomizationPrefixName(base: @base)
            end
          end
        end
      end
    end
  end
end
