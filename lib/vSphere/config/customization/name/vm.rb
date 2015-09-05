require 'vagrant'

require 'rbvmomi'

require_relative '../../../config_base'

module VagrantPlugins
  module VSphere
    class Config < ConfigBase
      class Customization < ConfigBase
        class Name
          class Vm < ConfigBase

            def type_name
              ":vm"
            end

            # --- vSphere API mapping ---

            VIM = RbVmomi::VIM

            def prepare_spec
              VIM.CustomizationVirtualMachineName
            end
          end
        end
      end
    end
  end
end
