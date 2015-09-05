require_relative '../../config_base'

require_relative 'identity/linux'
require_relative 'identity/sysprep'
require_relative 'identity/sysprep_text'

require_relative '../../errors'

module VagrantPlugins
  module VSphere
    class Config < ConfigBase
      class Customization < ConfigBase
        class Identity

          # This class is a factory for all the Identity::* classes.

          @@identity_classes = {
            'linux' => Identity::Linux,
            'sysprep' => Identity::Sysprep,
            'sysprep_text' => Identity::SysprepText,
          }

          def class_by_name(name)
            name = name.to_s
            klass = @@identity_classes[name]

            if klass.nil?
              fail Errors::Config,
                _key: :'customization.identity.invalid_type',
                type: name
            end

            klass
          end

          def set_class_mismatch(val, name)
            fail Errors::Config,
              _key: :'customization.identity.merge_error',
              first_type: val.type_name,
              second_type: name
          end

          def check_merge(this_val, other_val)
            return if this_val.class == other_val.class

            fail Errors::Config,
              _key: :'customization.identity.merge_error',
              first_type: this_val.type_name,
              second_type: other_val.type_name
          end

        end
      end
    end
  end
end
