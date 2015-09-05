require 'vagrant'

require_relative '../../config_base'

require_relative 'name/custom'
require_relative 'name/fixed'
require_relative 'name/prefix'
require_relative 'name/vm'

module VagrantPlugins
  module VSphere
    class Config < ConfigBase
      class Customization < ConfigBase
        class Name

          # This class is a factory for all the Identity::* classes.

          @@name_classes = {
            'custom' => Name::Custom,
            'fixed' => Name::Fixed,
            'prefix' => Name::Prefix,
            # Special cased in class_by_name()
            # 'unknown' => Name::Unknown,
            'vm' => Name::Vm,
          }

          def initialize(err_suffix, prop_name)
            @err_suffix = err_suffix
            @prop_name = prop_name
          end

          def class_by_name(name)
            name = name.to_s

            # Error reporting here is a bit more user friendly then if
            # done from inside Name::Unknown where we do not know the
            # name of the property holding the instance.
            if name == 'unknown'
              fail Errors::Config,
                _key: :'customization.name.type_unknown',
                prop_name: @prop_name,
                type: name
            end

            klass = @@name_classes[name]

            if klass.nil?
              fail Errors::Config,
                _key: :'customization.name.invalid_type',
                prop_name: @prop_name,
                type: name
            end

            klass
          end

          def set_class_mismatch(val, name)
            fail Errors::Config,
              _key: :"#{@err_suffix}.#{@prop_name}.merge_error",
              first_type: val.type_name,
              second_type: name
          end

          def check_merge(this_val, other_val)
            return if this_val.class == other_val.class

            fail Errors::Config,
              _key: :"#{@err_suffix}.#{@prop_name}.merge_error",
              first_type: this_val.type_name,
              second_type: other_val.type_name
          end

        end
      end
    end
  end
end
