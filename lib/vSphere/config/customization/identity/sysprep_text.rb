require 'vagrant'

require_relative '../../../config_base'

module VagrantPlugins
  module VSphere
    class Config < ConfigBase
      class Customization < ConfigBase
        class Identity
          class SysprepText < ConfigBase

            def initialize
              fail Errors::Config,
                :'customization.identity.sysprep_text.not_supported'
            end
          end
        end
      end
    end
  end
end
