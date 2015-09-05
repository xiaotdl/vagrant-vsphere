require 'i18n'
require 'netaddr'

require 'rbvmomi'

require 'vSphere/util/vim_helpers'
require 'vSphere/util/machine_helpers'
require 'vSphere/util/network'
require 'vSphere/sync'

module VagrantPlugins
  module VSphere
    module Action
      class Clone
        VIM = RbVmomi::VIM

        include Util::VimHelpers
        include Util::MachineHelpers

        def initialize(app, _env)
          @app = app
        end

        def call(env)
          machine = env[:machine]
          config = machine.config
          provider_config = machine.provider_config

          vsphere_env = env[:vsphere]

          connection = vsphere_env.connection
          dc = get_datacenter(connection, machine)

          name = vm_name(machine, provider_config, env[:root_path])

          template = dc.find_vm(provider_config.template_name)
          if template.nil?
            fail Errors::VSphereError,
              _key: :'provision.vm.missing_template',
              name: provider_config.template_name
          end

          folder = get_vm_folder(provider_config, dc, template)

          datastore = get_datastore(dc, machine)
          if provider_config.linked_clone && datastore.is_a?(VIM::StoragePod)
            fail Errors::VSphereError, :'provision.vm.linked_clone_with_sdrs'
          end

          # Storage DRS does not support vSphere linked clones.
          # http://www.vmware.com/files/pdf/techpaper/vsphere-storage-drs-interoperability.pdf

          if provider_config.linked_clone
            tweak_template_for_linked_cloning(template)
          end

          spec = prepare_clone_spec(vsphere_env, config, provider_config,
                                    connection, dc, datastore, template)

          if !provider_config.clone_from_vm && datastore.is_a?(VIM::StoragePod)

            storage_mgr = connection.serviceContent.storageResourceManager
            # TODO: May want to add option on type?
            storage_spec = VIM.StoragePlacementSpec(
              type: 'clone',
              cloneName: name,
              folder: folder,
              podSelectionSpec: VIM.StorageDrsPodSelectionSpec(
                storagePod: datastore
              ),
              vm: template,
              cloneSpec: spec
            )

            env[:ui].info(
              I18n.t('vsphere.requesting_sdrs_recommendation',
                     datastore: datastore.name,
                     template: template.pretty_path,
                     folder: folder.pretty_path,
                     name: name)
            )

            result = storage_mgr.RecommendDatastores(storageSpec: storage_spec)

            recommendation = result.recommendations[0]
            key = recommendation.key
            unless key
              fail Errors::VSphereError, :missing_datastore_recommendation
            end

            env[:ui].info(
              I18n.t('vsphere.creating_cloned_vm_sdrs',
                     target: recommendation.target.name,
                     reason: recommendation.reasonText)
            )

            apply_sr_result = \
              storage_mgr.ApplyStorageDrsRecommendation_Task(key: [key]).wait_for_completion
            new_vm = apply_sr_result.vm

          else

            if provider_config.clone_from_vm
              env[:ui].info(
                I18n.t('vsphere.creating_cloned_vm.from_vm',
                       source: template.pretty_path,
                       folder: folder.pretty_path,
                       name: name)
              )
            else
              env[:ui].info(
                I18n.t('vsphere.creating_cloned_vm.from_template',
                       template: template.pretty_path,
                       folder: folder.pretty_path,
                       name: name)
              )
            end

            new_vm = template.CloneVM_Task(
              folder: folder,
              name: name,
              spec: spec
            ).wait_for_completion
          end

          # TODO: handle interrupted status in the environment, should the vm be destroyed?

          machine.id = new_vm.config.uuid

          # wait for SSH to be available
          wait_for_ssh env

          env[:ui].info I18n.t('vsphere.vm_clone_success')

          @app.call env
        end

        private

        def tweak_template_for_linked_cloning(template)
          # The API for linked clones is quite strange. We can't create a
          # linked clone straight from any VM. The disks of the VM for which we
          # can create a linked clone need to be read-only and thus VC demands
          # that the VM we are cloning from uses delta-disks. Only then it will
          # allow us to share the base disk.
          #
          # Thus, this code first create a delta disk on top of the base disk for
          # the to-be-cloned VM, if delta disks aren't used already.
          disks = template.config.hardware.device.grep(VIM::VirtualDisk)
          disks.select { |disk| disk.backing.parent.nil? }.each do |disk|
            spec = {
              deviceChange: [
                {
                  operation: :remove,
                  device: disk
                },
                {
                  operation: :add,
                  fileOperation: :create,
                  device: disk.dup.tap do |new_disk|
                            new_disk.backing = new_disk.backing.dup
                            new_disk.backing.fileName = "[#{disk.backing.datastore.name}]"
                            new_disk.backing.parent = disk.backing
                          end
                }
              ]
            }
            template.ReconfigVM_Task(spec: spec).wait_for_completion
          end
        end

        def prepare_relocation_spec(config, provider_config, dc, datastore)
          if provider_config.linked_clone
            spec = VIM.VirtualMachineRelocateSpec(
              diskMoveType: :moveChildMostDiskBacking
            )
          else
            spec = VIM.VirtualMachineRelocateSpec

            unless datastore.nil? || datastore.is_a?(VIM::StoragePod)
              spec[:datastore] = datastore
            end
          end

          unless provider_config.clone_from_vm
            spec[:pool] = get_resource_pool(dc, provider_config)
          end

          spec
        end

        def vm_name(machine, config, root_path)
          return config.name unless config.name.nil?

          prefix = "#{root_path.basename}_#{machine.name}"
          prefix.gsub!(/[^-a-z0-9_\.]/i, '')
          # milliseconds + random number suffix to allow for simultaneous
          # `vagrant up` of the same box in different dirs
          prefix + "_#{(Time.now.to_f * 1000.0).to_i}_#{rand(100_000)}"
        end

        def get_vm_folder(provider_config, dc, template)
          path = provider_config.folder
          if path.nil?
            template.parent
          else
            folder = dc.vmFolder.traverse(path, VIM::Folder, true)
            if folder.nil?
              fail Errors::VSphereError,
                _key: :'provision.vm.invalid_base_path', path: path
            end

            folder
          end
        end

        def prepare_clone_spec(vsphere_env, config, provider_config,
                               connection, dc, datastore, template)
          network_info = get_network_info(vsphere_env, provider_config, dc)

          location = prepare_relocation_spec(config, provider_config,
                                             dc, datastore)

          spec = VIM.VirtualMachineCloneSpec(
            location: location,
            powerOn: true,
            template: false,
            config: VIM.VirtualMachineConfigSpec
          )

          deviceChange = prepare_device_change(network_info, vsphere_env,
                                               provider_config, template)
          spec[:config][:deviceChange] = deviceChange if deviceChange.length

          if provider_config.customization_spec_name
            cust_spec = \
              find_customization_spec(connection,
                                      provider_config.customization_spec_name)
            add_ips_to_cusomization_spec(cust_spec, config)
            spec[:customization] = cust_spec
          else
            cust_spec = prepare_customization_spec(config, provider_config)
            spec[:customization] = cust_spec if cust_spec
          end

          if !provider_config.memory_mb.nil?
            spec[:config][:memoryMB] = Integer(provider_config.memory_mb)
          end

          if !provider_config.cpu_count.nil?
            spec[:config][:numCPUs] = Integer(provider_config.cpu_count)
          end

          if !provider_config.cpu_reservation.nil?
            spec[:config][:cpuAllocation] = VIM.ResourceAllocationInfo(
              reservation: provider_config.cpu_reservation
            )
          end

          if !provider_config.mem_reservation.nil?
            spec[:config][:memoryAllocation] = VIM.ResourceAllocationInfo(
              reservation: provider_config.mem_reservation
            )
          end

          spec
        end

        def get_network_info(vsphere_env, provider_config, dc)
          compute = get_compute_resource(dc, provider_config)

          # We support only one host configuration at the moment.
          if (compute.host.length == 0)
            fail Errors::VSphereError, 'provision.compute.empty'
          elsif (compute.host.length > 1)
            fail Errors::VSphereError, 'provision.compute.cluster'
          end

          host = compute.host[0]

          vsphere_env.network_info(host)
        end

        def find_customization_spec(connection, name)
          manager = connection.serviceContent.customizationSpecManager
          if manager.nil?
            fail Errors::VSphereError,
              :'provision.vm.null_configuration_spec_manager'
          end

          spec_item = manager.GetCustomizationSpec(name: name)
          if spec_item.nil?
            fail Errors::VSphereError,
              _key: :'provision.vm.configuration_spec',
              name: name
          end

          # Return the actual CustomizationSpec object.
          spec_item.spec
        end

        def add_ips_to_cusomization_spec(spec, config)
          networks = config.vm.networks

          # Find all the configured networks.
          networks = \
            networks.find_all { |type, _opt| type != 'forwarded_port' }
          return if networks.nil?

          nicSettings = spec.nicSettingMap

          if networks.length > nicSettingMap.length
            fail Errors::VSphereError,
              _key: :'provision.vm.customization_spec.network_count',
              spec_nic_count: nicSettingMap.length,
              network_count: networks.length
          end

          # Assign the network IP to the NIC.
          networks.each_with_index do |(type, options), idx|
            next if options.key?(:auto_config) && !options[:auto_config]
            nicSettings[idx].adapter.ip.ipAddress = options[:ip]
          end
        end

        # For now this is only the NICs.
        def prepare_device_change(network_info, vsphere_env,
                                  provider_config, template)
          vm_nics = \
            template.config.hardware.device.grep(VIM::VirtualEthernetCard)

          # NICs have :index values starting with 1, not 0.  So we
          # subtract 1 to get to the 0-based indexing logic.
          config_nics = \
            Hash[ provider_config.nics.map { |index, n| [index - 1, n] } ]

          deviceChange = []

          vm_nics.map.with_index { |vm_nic, index|
            edit_network_card(network_info, vm_nic, config_nics[index])
          }.compact.each do |edit_spec|
            deviceChange << edit_spec
          end

          # If there are more nics configured than there are actual nics
          # add the missing ones.

          max_index = provider_config.nics.keys.max
          add_last_index = max_index.nil? ? 0 : max_index - 1

          (vm_nics.length .. add_last_index).map { |index|
            add_network_card(network_info, vsphere_env, config_nics[index])
          }.compact.each do |add_spec|
            deviceChange << add_spec
          end

          deviceChange
        end

        def edit_network_card(network_info, nic, config)
          # Check if this nic needs any configuration changes
          prepared_backing = nil
          begin
            return nil if config.nil?

            prepared_backing = \
              prepare_network_card_backing_info(network_info,
                                                config.portgroup)

            backing = nic[:backing]
            break if backing.nil?
            break if !network_card_backing_info_eq(backing,
                                                   prepared_backing)

            prepared_backing = nil

            connectable = nic[:connectable]
            break if !config.startConnected.nil? &&
                config.startConnected != connectable[:startConnected]
            break if !config.allowGuestControl.nil? &&
                config.allowGuestControl != connectable[:allowGuestControl]

            break if !config.mac_addressType.nil? &&
              config.mac_addressType != nic[:addressType]
            break if !config.mac.nil? &&
              config.mac != nic[:macAddress]

            # This nic does not require any changes
            return nil
          end while false

          new_nic = nic.class.new(
            key: nic[:key],
          )

          spec = VIM.VirtualDeviceConfigSpec(
            operation: :edit,
            device: new_nic
          )

          unless prepared_backing.nil?
            new_nic[:backing] = prepared_backing
          end

          unless config.startConnected.nil? && config.allowGuestControl.nil?
            new_nic[:connectable] = \
              nic[:connectable].dup.tap do |connInfo|

                connInfo[:allowGuestControl] = config.allowGuestControl \
                  unless config.allowGuestControl.nil?

                unless config.startConnected.nil?
                  connInfo[:startConnected] = config.startConnected
                  connInfo[:connected] = config.startConnected
                end
              end
          end

          unless config.mac_addressType.nil?
            new_nic[:addressType] = config.mac_addressType
          end
          unless config.mac.nil?
            new_nic[:macAddress] = config.mac
          end

          spec
        end

        def add_network_card(network_info, vsphere_env, config)
          return nil if config.nil?

          # Use unique device key when adding.
          key = vsphere_env.next_device_key

          spec = VIM.VirtualDeviceConfigSpec(
            operation: :add,
            device: VIM.VirtualVmxnet3(
              key: key,
              backing: \
                prepare_network_card_backing_info(network_info,
                                                  config.portgroup)
            )
          )

          unless config.startConnected.nil? && config.allowGuestControl.nil?
            spec[:device][:connectable] = \
              VIM.VirtualDeviceConnectInfo.tap do |connectable|

                unless config.startConnected.nil?
                    connectable[:allowGuestControl] = config.allowGuestControl
                end

                unless config.startConnected.nil?
                    connectable[:startConnected] = config.startConnected
                end
              end
          end

          unless config.mac_addressType.nil?
            spec[:device][:addressType] = config.mac_addressType
          end
          unless config.mac.nil?
            spec[:device][:macAddress] = config.mac
          end

          spec
        end

        def prepare_network_card_backing_info(network_info, portgroup_name)
          portgroup = \
            network_info[:portgroup].find do |pg|
              if pg.is_a?(VIM::DistributedVirtualPortgroup)
                pg.config.name == portgroup_name
              else
                pg.spec.name == portgroup_name
              end
          end

          if portgroup.nil?
            fail(Errors::VSphereError,
                 _key: :'provision.vm.missing_network',
                 name: portgroup_name)
          end

          if portgroup.is_a?(VIM::DistributedVirtualPortgroup)
            VIM.VirtualEthernetCardDistributedVirtualPortBackingInfo(
              port: VIM.DistributedVirtualSwitchPortConnection(
                switchUuid: portgroup.config.distributedVirtualSwitch.uuid,
                portgroupKey: portgroup.key
              )
            )
          else
            VIM.VirtualEthernetCardNetworkBackingInfo(
              deviceName: portgroup.spec.name
            )
          end
        end

        def network_card_backing_info_eq(a, b)
          return false if a.class != b.class

          if a.is_a?(VIM::VirtualDeviceBackingInfo)
            return false if a[:deviceName] != b[:deviceName]
          elsif a.is_a?(VIM::VirtualEthernetCardDistributedVirtualPortBackingInfo)
            aPort = a.port
            bPort = b.port
            return false if aPort[:switchUuid] != bPort[:switchUuid]
            return false if aPort[:portgroupKey] != bPort[:portgroupKey]
          end

          return true
        end

        def prepare_customization_spec(config, provider_config)
          return nil if provider_config.get_customization.nil?

          networks = config.vm.networks

          nicSettingMap = []

          provider_config.nics.each_value do |nic|
            portgroup = nic.portgroup
            network = networks.find { |type, options|
              type != :forwarded_port && options[:id] == portgroup }

            options = network[1]

            if (options[:auto_config].nil? || options[:auto_config]) \
                && (options[:type].nil? || options[:type] != "dhcp")

              address = NetAddr::CIDR.create(options[:ip])

              nicSettingMap << VIM.CustomizationAdapterMapping(
                adapter: {
                  ip: VIM.CustomizationFixedIp(
                    ipAddress: address.ip,
                  ),
                  subnetMask: address.wildcard_mask,
                }
              )
            else
              nicSettingMap << VIM.CustomizationAdapterMapping(
                adapter: {
                  ip: VIM.CustomizationDhcpIpGenerator
                }
              )
            end
          end

          provider_config.get_customization.prepare_spec(nicSettingMap)
        end

      end
    end
  end
end
