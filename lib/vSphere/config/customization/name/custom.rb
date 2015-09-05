require 'vagrant'

require 'rbvmomi'

require_relative '../../../config_base'

module VagrantPlugins
  module VSphere
    class Config < ConfigBase
      class Customization < ConfigBase
        class Name
          class Custom < ConfigBase

            config_field_simple :argument

            def type_name
              ":custom"
            end

            # --- vSphere API mapping ---

            VIM = RbVmomi::VIM

            def prepare_spec
              VIM.CustomizationCustomName(argument: @argument)
            end
          end
        end
      end
    end
  end
end
