require 'vagrant'
require 'ipaddr'

require_relative 'config/vswitch'
require_relative 'config/portgroup'
require_relative 'config/nic'
require_relative 'config/customization'

require_relative 'config_base'

module VagrantPlugins
  module VSphere
    class Config < ConfigBase

      config_field_simple :host
      config_field_simple :insecure
      config_field_simple :user
      config_field_simple :password

      config_field_simple :data_center_name

      config_field_simple :compute_resource_name

      config_field_simple :clone_from_vm
      config_field_simple :template_name
      config_field_simple :linked_clone

      config_field_simple :name
      config_field_simple :folder
      config_field_simple :customization_spec_name
      config_field_simple :resource_pool_name
      config_field_simple :data_store_name

      config_field_simple :proxy_host
      config_field_simple :proxy_port

      config_field_simple :vlan
      config_field_simple :addressType
      config_field_simple :mac

      config_field_simple :memory_mb
      config_field_simple :cpu_count
      config_field_simple :cpu_reservation
      config_field_simple :mem_reservation

      config_field_forward :customization, Customization

      config_field_hash :vswitch, Vswitch, getter_name: :vswitches

      config_field_hash :portgroup, Portgroup

      config_field_hash :nic, Nic,
        key_name: :index,
        key_checker: ->(index) do
          unless index.is_a?(Integer)
            fail Errors::Config,
              _key: :'nic.index_should_be_an_integer',
              value: index,
              type: index.class
          end

          if index <= 0
            fail Errors::Config,
              _key: :'nic.indices_start_with_one',
              index: index
          end
        end
          

      ERR_PREFIX = 'vsphere.errors.config'
      WARN_PREFIX = 'vsphere.warn.config'

      def vm_base_path
        @folder
      end

      def vm_base_path=(v)
        machine.ui.warn(I18n.t("#{WARN_PREFIX}.vm_base_path"))
        @folder = v
      end

      def validate_fields(errors, machine)
        finalize_config!(errors, machine.ui, machine.config)

        # TODO: add blank?
        errors << I18n.t("#{ERR_PREFIX}.host") if host.nil?
        errors << I18n.t("#{ERR_PREFIX}.user") if user.nil?
        errors << I18n.t("#{ERR_PREFIX}.password") if password.nil?

        # Only required if we're cloning from an actual template
        errors << I18n.t("#{ERR_PREFIX}.vm.compute_resource") \
          if compute_resource_name.nil? && !clone_from_vm

        errors << I18n.t("#{ERR_PREFIX}.vm.template") \
          if template_name.nil?

        errors << I18n.t("#{ERR_PREFIX}.vm.memory_mb",
                         value: memory_mb) \
          if !memory_mb.nil? && !/\A\d+\z/.match(memory_mb)

        errors << I18n.t("#{ERR_PREFIX}.mv.cpu_count",
                         value: cpu_count) \
          if !cpu_count.nil? && !/\A\d+\z/.match(cpu_count)

        errors << I18n.t("#{ERR_PREFIX}.mv.cpu_reservation",
                         value: cpu_reservation) \
          if !cpu_reservation.nil? && !/\A\d+\z/.match(cpu_reservation)

        errors << I18n.t("#{ERR_PREFIX}.mv.mem_reservation",
                         value: mem_reservation) \
          if !mem_reservation.nil? && !/\A\d+\z/.match(mem_reservation)

        super(errors, machine)

        networks = machine.config.vm.networks

        # vSphere requires customization object if we are going to
        # assign any IPs.  This check combines @customization, @nics
        # and networks.
        validate_customization(errors, networks)

        validate_networks(errors, networks)
      end

      def validate_networks(errors, networks)
        # Check network types
        networks.each do |type, options|
          next if type == :private_network || type == :public_network

          if type == :forwarded_port
            # Kernel configuration plugin will automatically insert a
            # forwarding port entry that we do not support.  As a special case
            # we skip it.
            next if options[:id] == "ssh" &&
              options[:guest] == 22 &&
              options[:host] == 2222

            errors << I18n.t("#{ERR_PREFIX}.network.forwarded_port",
                            type: 'forwarded_port', id: options[:id] )
          else
            errors << I18n.t("#{ERR_PREFIX}.network.unknown_type",
                             type: type, id: options[:id])
          end
        end

        ids = networks.find_all { |type, options| type != :forwarded_port }.
          map { |type, options| options[:id] }

        ids.find_all { |id| ids.rindex(id) != ids.index(id) }.
          uniq.each do |id|
          errors << I18n.t("#{ERR_PREFIX}.network.duplicate_name",
                           id: id)
        end

        # Make sure we have our own configuration for every global network
        # defined.  This way we can specify all the defaults here, and in the
        # actions assume they are already set.

        networks.each do |type, options|
          # Skip the built in port forwarding entry.
          next if type == :forwarded_port

          id = options[:id]

          unless options.key?(:auto_config) && !options[:auto_config] \
              || options.key?(:type) && options[:type] == "dhcp"
            ip = options[:ip]
            if !ip
              errors << I18n.t("#{ERR_PREFIX}.network.missing_ip",
                               type: type, id: id)
            elsif !IPAddr.new(ip).ipv4?
              errors << I18n.t("#{ERR_PREFIX}.network.not_ipv4",
                               type: type, id: id, address: ip)
            end
          end

          unless @nics.any? { |index, nic| nic.portgroup == id }
            errors << I18n.t("#{ERR_PREFIX}.network.unreferenced",
                             type: type, id: id)
          end
        end
      end

      def validate_customization(errors, networks)
        required = false
        assignments = []

        # We want to check if any of the NICs need to have an IP
        # assigned.  As IPs, for the moment, are on the networks and we
        # require every network to be mapped to a NIC we can just check
        # the networks, skipping the NICs altogether.
        #
        # But we want to output helpful error message with the NIC names,
        # so we go through NICs and networks.
        #
        # Natural extension of the current configuration is to allow
        # additional IPs to be assigned, and that would probably be done
        # through NICs.  That would require iteration through NICs as
        # well.
        @nics.each_value do |nic|
          next if nic.portgroup.nil?

          required ||= networks.any? do |type, network|
            next false \
              if type == :forwarded_port || network[:id] != nic.portgroup ||
                (!network[:auto_config].nil? && !network[:auto_config])

            assignments <<
              "Nic #{nic.index}, network '#{network[:id]}': #{network[:ip]}"

            break true
          end

          break if required
        end

        return unless required

        # We just need a customization object.
        return unless @customization.nil?

        errors << I18n.t("#{ERR_PREFIX}.requires_customization",
                         nics_and_network_names:
                           "\n    " + assignments.join("\n    "))
      end

      # XXX finalize!() does not have access to the global config.  Otherwise
      # we could have created default value for all the networks here.
      # So we call finalize_config!() from validate() instead.
      # It seems to make sense to also be able to generate errors similarly
      # to validate.
      # TODO Suggest a patch for vagrant to fix that.

      # TODO Combine this with finalize! as soon as finalize! will be provided
      # with the config object.
      def finalize_config!(errors, ui, config)
        if @password.nil?
          @password = ui.ask('vSphere Password (will be hidden): ',
                             echo: false)
        end

        # Backward compatibility

        unless @vlan.nil?
          nic_config = @nics.fetch(1) do |index|
            @nics[index] = Nic.new.tap {|nc|
              nc.index = index }
          end

          unless nic_config[:portgroup].nil?
            errors << I18n.t("#{ERR_PREFIX}.nic.global_vlan_clash",
                             vlan: @vlan,
                             nic_portgroup: nic_config[:portgroup])
          else
            ui.warn(I18n.t("#{WARN_PREFIX}.vlan"))
            nic_config[:portgroup] = @vlan
          end
        end

        unless @addressType.nil?
          nic_config = @nics.fetch(1) do |index|
            @nics[index] = Nic.new.tap {|nc|
              nc.index = index
            }
          end

          unless nic_config[:mac_addressType].nil?
            errors << I18n.t("#{ERR_PREFIX}.nic.global_addressType_clash",
                             addressType: @addressType,
                             nic_mac_addressType: nic_config[:mac_addressType])
          else
            ui.warn(I18n.t("#{WARN_PREFIX}.addressType"))
            nic_config[:mac_addressType] = @addressType
          end
        end

        unless @mac.nil?
          nic_config = @nics.fetch(1) do |index|
            @nics[index] = Nic.new.tap {|nc|
              nc.index = index }
          end

          unless nic_config[:mac].nil?
            errors << I18n.t("#{ERR_PREFIX}.nic.global_mac_clash",
                             mac: @mac,
                             nic_mac: nic_config[:mac])
          else
            ui.warn(I18n.t("#{WARN_PREFIX}.mac"))
            nic_config[:mac] = @mac
          end
        end

      end

    end
  end
end
