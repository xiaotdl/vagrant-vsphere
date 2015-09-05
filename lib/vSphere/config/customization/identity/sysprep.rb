require 'vagrant'

require_relative '../../../config_base'

module VagrantPlugins
  module VSphere
    class Config < ConfigBase
      class Customization < ConfigBase
        class Identity
          class Sysprep < ConfigBase

            def initialize
              fail Errors::Config,
                :'customization.identity.sysprep.not_supported'
            end
          end
        end
      end
    end
  end
end
