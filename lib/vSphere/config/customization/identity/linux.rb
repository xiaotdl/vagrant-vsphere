require 'vagrant'

require 'rbvmomi'

require_relative '../../../config_base'
require_relative '../name.rb'

module VagrantPlugins
  module VSphere
    class Config < ConfigBase
      class Customization < ConfigBase
        class Identity
          class Linux < ConfigBase

            ERR_SUFFIX = 'config.customization.identity.linux'
            ERR_PREFIX = "vsphere.errors.#{ERR_SUFFIX}"

            config_field_simple :domain
            config_field_typed :hostName, Name.new(ERR_SUFFIX, 'hostName')

            def type_name
              ":linux"
            end

            def validate_fields(errors, machine)
              super(errors, machine)

              if @domain.nil?
                errors << I18n.t("#{ERR_PREFIX}.requires_domain")
              end

              if @hostName.nil?
                errors << I18n.t("#{ERR_PREFIX}.requires_hostName")
              end
            end

            # --- vSphere API mapping ---

            VIM = RbVmomi::VIM

            def prepare_spec
              VIM.CustomizationLinuxPrep(
                domain: @domain,
                hostName: @hostName.prepare_spec
              )
            end

          end
        end
      end
    end
  end
end
