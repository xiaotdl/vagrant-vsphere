require 'vagrant'

module VagrantPlugins
  module VSphere
    # Common base class functionality for all the config classes.
    #
    # TODO This should be pushed into Vagrant itself.  Into
    # Vagrant::Plugin::V2::Config.
    class ConfigBase < Vagrant.plugin("2", :config)

      # --- Class level methods ---
      #
      # The following are helpers used to define configuration object
      # fields.

      # Adds a simple field into a config class.
      # Field is set to UNSET_VALUE, has read/write accessors, and
      # defaults the specified value if not set explicitly.
      def self.config_field_simple(id, default: nil)
        ConfigBase._init_fields(self) if @_config_fields.nil?

        field_sym = ('@' + id.to_s).to_sym

        @_config_fields << SimpleField.new(field_sym, default)

        attr_accessor id
      end

      # Adds a forwarded field into a config class.
      # Field is set to UNSET_VALUE, has a get_* read accessor and a
      # forwarding method.
      def self.config_field_forward(id, klass,
                                    getter_name: ('get_' + id.to_s).to_sym,
                                    field_sym: ('@' + id.to_s).to_sym
                                   )
        ConfigBase._init_fields(self) if @_config_fields.nil?

        unless klass < ConfigBase
          fail "Internal error: config_field_forward() requires klass to" +
            " derive from ConfigBase.  Got: #{klass}"
        end

        @_config_fields << ForwardingField.new(field_sym)

        define_method(id) do |**options, &block|
          val = self.instance_variable_get(field_sym)
          if val == UNSET_VALUE
            val = klass.new
            self.instance_variable_set(field_sym, val)
          end

          val.set_options(options)
          block.call(val) unless block.nil?
        end

        define_method(getter_name) do
          self.instance_variable_get(field_sym)
        end
      end

      # Adds a multi-type forwarded field into a config class.
      # Field is set to UNSET_VALUE, has a get_* read accessor and a
      # forwarding method.
      # Specific type id is expected as the setter first argument.
      # factory has to implement the following methods:
      #   class_by_name(name) - converts type name to a specific class.
      #   set_class_mismatch(val, name) - throws an exception when val
      #     is not of a class derived from the name class.
      #   check_merge(this_val, other_val) - checks if this_val can be
      #     merged with other_val and throws an error if they can not be.
      def self.config_field_typed(id,
                                  factory,
                                  getter_name: ('get_' + id.to_s).to_sym,
                                  field_sym: ('@' + id.to_s).to_sym
                                 )
        ConfigBase._init_fields(self) if @_config_fields.nil?

        @_config_fields << TypedField.new(field_sym, factory)

        define_method(id) do |name, **options, &block|
          klass = factory.class_by_name(name)
          val = self.instance_variable_get(field_sym)
          if val == UNSET_VALUE
            val = klass.new
            self.instance_variable_set(field_sym, val)
          elsif !val.is_a?(klass)
            factory.set_class_mismatch(val, name)
          end

          val.set_options(options)
          block.call(val) unless block.nil?
        end

        define_method(getter_name) do
          self.instance_variable_get(field_sym)
        end
      end

      # Adds an array field into a config class.
      # Field holds an array of ConfigBase objects.  Index of the target
      # object is the first argument to the setter.  Getter returns the
      # array itself.
      # Initial value of the field is an empty array.
      # Any indices with UNSET_VALUE are set to nil in finalize!.
      # Merge happened on a per index level, forwarding into the contained
      # objects.
      def self.config_field_array(id, klass,
                                  getter_name: (id.to_s + 's').to_sym,
                                  index_name: :index,
                                  index_checker: nil,
                                  field_sym: ('@' + getter_name.to_s).to_sym
                                 )
        ConfigBase._init_fields(self) if @_config_fields.nil?

        unless klass < ConfigBase
          fail "Internal error: config_field_array() requires klass to" +
            " derive from ConfigBase.  Got: #{klass}"
        end

        @_config_fields << ArrayField.new(field_sym)

        define_method(id) do |index, **options, &block|
          index_checker.call(index) unless index_checker.nil?

          arr = self.instance_variable_get(field_sym)
          val = arr.fetch(index) do |index|
            arr[index] = klass.new.tap do |val|
              val.send("#{index_name}=", index)
            end
          end

          val.set_options(options)
          block.call(val) unless block.nil?
        end

        define_method(getter_name) do
          self.instance_variable_get(id)
        end
      end

      # Adds a hash field into a config class.
      # Field holds a hash of ConfigBase objects.  Key of the target object
      # is the first argument to the setter.  Getter returns the hash
      # itself.
      # Initial value of the field is an empty hash.
      # Any keys with UNSET_VALUE are set to nil in finalize!.
      # Merge happened on a per key level, forwarding into the contained
      # objects.
      def self.config_field_hash(id, klass,
                                 getter_name: (id.to_s + 's').to_sym,
                                 key_name: :name,
                                 key_checker: nil,
                                 field_sym: ('@' + getter_name.to_s).to_sym
                                )
        ConfigBase._init_fields(self) if @_config_fields.nil?

        unless klass < ConfigBase
          fail "Internal error: config_field_hash() requires klass to" +
            " derive from ConfigBase.  Got: #{klass}"
        end

        @_config_fields << HashField.new(field_sym)

        define_method(id) do |key, **options, &block|
          key_checker.call(key) unless key_checker.nil?

          hash = self.instance_variable_get(field_sym)
          val = hash.fetch(key) do |key|
            hash[key] = klass.new.tap do |val|
              val.send("#{key_name}=", key)
            end
          end

          val.set_options(options)
          block.call(val) unless block.nil?
        end

        define_method(getter_name) do
          self.instance_variable_get(field_sym)
        end
      end

      def self.get_config_fields
        ConfigBase._init_fields(self) if @_config_fields.nil?

        return @_config_fields
      end

      # --- Instance methods ---

      def initialize
        self.class.get_config_fields.each do |f|
          f.init(self)
        end
      end

      # Default implementation for the Root configuration objects.
      # Any validation rules should be defined in validate_fields() that
      # will be automatically called on all the # nested configuration
      # objects.
      # This method is only called for the plugin top level configuration
      # object.
      def validate(machine)
        errors = _detected_errors

        validate_fields(errors, machine)

        { 'vSphere Provider' => errors }
      end

      # Default implementation.  Any custom validation rules should be
      # provided by overwriting this method.  Do not forget to call
      # super(errors, machine).
      def validate_fields(errors, machine)
        errors.concat(_detected_errors)

        self.class.get_config_fields.each do |f|
          f.validate(self, errors, machine)
        end
      end

      # Implements merging for all the fields.  Unlike Vagrant default
      # implementation, this will only merge fields explicitly defined
      # using one of the config_field_*() class methods.
      # Does not call the Vagrant merging implementation, but does merge
      # @__invalid_methods.
      #
      # Any custom merging rules should be added in an overwrite.  Do not
      # forget to do "result = super(other)" if you are overwriting this
      # method.
      def merge(other)
        # We want to use our own merge mechanism, so we are not calling
        # super here.  That means we would have to also merge
        # @__invalid_methods.

        result = self.class.new

        self.class.get_config_fields.each do |f|
          f.merge(result, self, other)
        end

        # Persist through the set of invalid methods
        this_invalid  = @__invalid_methods || Set.new
        other_invalid = other.instance_variable_get(:"@__invalid_methods") || Set.new
        result.instance_variable_set(:"@__invalid_methods", this_invalid + other_invalid)

        result
      end

      def finalize!
        self.class.get_config_fields.each do |f|
          f.finalize!(self)
        end

        # This will "seal" config objects, making them throw full scaled
        # errors on invalid property access instead of "user facing"
        # errors.
        @__finalized = true
      end

      private

      def self._init_fields(klass)
        baseFields = (klass.ancestors - [klass]).select do |c|
          c.respond_to? :config_fields_get
        end.map do |c|
          c.config_field_get
        end.flatten

        klass.instance_variable_set(:@_config_fields, baseFields)
      end

      class Field
        attr_accessor :id

        def initialize(id)
          @id = id
        end

        # This constant is used by all the derived classes
        UNSET_VALUE = ConfigBase::UNSET_VALUE

        # def init(this)

        # def merge(result, this, other)

        # def validate(this, errors, machine)

        # def finalize!(this)
      end

      class SimpleField < Field
        attr_accessor :default

        def initialize(id, default)
          super(id)
          @default = default
        end

        def init(this)
          this.instance_variable_set(@id, UNSET_VALUE)
        end

        def merge(result, this, other)
          this_val = this.instance_variable_get(@id)
          other_val = other.instance_variable_get(@id)
          if other_val == UNSET_VALUE
            result.instance_variable_set(@id, this_val)
          else
            result.instance_variable_set(@id, other_val)
          end
        end

        def validate(this, errors, machine)
        end

        def finalize!(this)
          val = this.instance_variable_get(@id)
          if val == UNSET_VALUE
            this.instance_variable_set(@id, @default)
          end
        end

      end

      class ForwardingField < Field
        def init(this)
          this.instance_variable_set(@id, UNSET_VALUE)
        end

        def merge(result, this, other)
          this_val = this.instance_variable_get(@id)
          other_val = other.instance_variable_get(@id)
          if this_val == UNSET_VALUE
            result.instance_variable_set(@id, other_val)
          elsif other_val == UNSET_VALUE
            result.instance_variable_set(@id, this_val)
          else
            val = this_val.merge(other_val)
            result.instance_variable_set(@id, val)
          end
        end

        def validate(this, errors, machine)
          val = this.instance_variable_get(@id)
          unless val.nil?
            val.validate_fields(errors, machine)
          end
        end

        def finalize!(this)
          val = this.instance_variable_get(@id)
          if val == UNSET_VALUE
            this.instance_variable_set(@id, nil)
          else
            val.finalize!
          end
        end

      end

      class TypedField < ForwardingField
        attr_accessor :factory

        def initialize(id, factory)
          super(id)

          @factory = factory
        end

        def merge(result, this, other)
          this_val = this.instance_variable_get(@id)
          other_val = other.instance_variable_get(@id)
          if this_val == UNSET_VALUE
            result.instance_variable_set(@id, other_val)
          elsif other_val == UNSET_VALUE
            result.instance_variable_set(@id, this_val)
          else
            @factory.check_merge(this_val, other_val)
            val = this_val.merge(other_val)
            result.instance_variable_set(@id, val)
          end
        end
      end

      class ArrayField < Field
        def init(this)
          this.instance_variable_set(@id, [])
        end

        def merge(result, this, other)
          this_arr = this.instance_variable_get(@id)
          other_arr = other.instance_variable_get(@id)
          combined = []
          (0 .. [this_arr.length, other_arr.length].max - 1).each do |i|
            this_val = i < this_arr.length ? this_arr[i] : UNSET_VALUE
            other_val = i < other_arr.length ? other_arr[i] : UNSET_VALUE
            if this_val == UNSET_VALUE
              combined << other_val
            elsif other_val == UNSET_VALUE
              combined << this_val
            else
              combined << this_val.merge(other_val)
            end
          end
          result.instance_variable_set(@id, combined)
        end

        def validate(this, errors, machine)
          arr = this.instance_variable_get(@id)
          arr.reject {|v| v.nil? }.each do |v|
            v.validate_fields(errors, machine)
          end
        end

        def finalize!(this)
          arr = this.instance_variable_get(@id)
          arr.map! do |val|
            if val == UNSET_VALUE || val.nil?
              nil
            else
              val.finalize!
              val
            end
          end
        end

      end

      class HashField < Field
        def init(this)
          this.instance_variable_set(@id, {})
        end

        def merge(result, this, other)
          this_hash = this.instance_variable_get(@id)
          other_hash = other.instance_variable_get(@id)
          combined = \
            this_hash.merge(other_hash) do |key, this_val, other_val|
            if this_val == UNSET_VALUE
              other_val
            elsif other_val == UNSET_VALUE
              this_val
            else
              this_val.merge(other_val)
            end
          end

          result.instance_variable_set(@id, combined)
        end

        def validate(this, errors, machine)
          hash = this.instance_variable_get(@id)
          hash.each_value.reject {|v| v.nil? } \
                         .each do |val|
            val.validate_fields(errors, machine)
          end
        end

        def finalize!(this)
          hash = this.instance_variable_get(@id)

          hash.delete_if { |key, val| val == UNSET_VALUE }
          hash.each_value.reject {|v| v.nil? } \
                         .each do |val|
            val.finalize!
          end
        end

      end

    end
  end
end
