require 'rbvmomi'

require 'vSphere/util/vim_helpers'
require 'vSphere/sync'

module VagrantPlugins
  module VSphere
    module Action
      class ConstructNetwork
        VIM = RbVmomi::VIM

        include Util::VimHelpers

        def initialize(app, _env)
          @app = app
        end

        def call(env)
          machine = env[:machine]
          provider_config = machine.provider_config

          vsphere_env = env[:vsphere]

          connection = vsphere_env.connection
          dc = get_datacenter(connection, machine)

          compute = get_compute_resource(dc, provider_config)

          # Support only one host configuration at the moment.
          if (compute.host.length == 0)
            fail Errors::VSphereError, 'provision.compute.empty'
          elsif (compute.host.length > 1)
            fail Errors::VSphereError, 'provision.compute.cluster'
          end

          host = compute.host[0]

          Sync.resourceLock.synchronize do
            network_info = vsphere_env.network_info(host, false)

            # Prepare all the host network modifications and execute then in one
            # operation.
            hostNetworkConfig = VIM.HostNetworkConfig()

            # We only update our state if we actually executed the
            # configuration request.  Alternative would be to clone current
            # network info, modify the env version directly, and restore
            # the clone if something goes wrong.
            added_vswitches = []
            added_portgroups = []

            prepare_vswitch_config(env, hostNetworkConfig, added_vswitches,
                                   network_info, provider_config)
            prepare_portgroup_config(env, hostNetworkConfig, added_portgroups,
                                     network_info, provider_config)

            unless hostNetworkConfig.props.empty?
              res = host.configManager.networkSystem.UpdateNetworkConfig(
                :config => hostNetworkConfig,
                :changeMode => :modify
              )

              network_info[:vswitch].concat(added_vswitches)
              network_info[:portgroup].concat(added_portgroups)
            end
          end

          @app.call(env)
        end

        def prepare_vswitch_config(env, hostNetworkConfig, added_vswitches,
                                   network_info, provider_config)
          provider_config.vswitches.each_value do |vswitch|
            name = vswitch.name

            existing = \
              network_info[:vswitch].detect { |s| s.name == name && s }

            # Only create the vSwitch if needed.
            next if existing

            env[:ui].info(
              I18n.t('vsphere.info.provision.vswitch.creating', name: name)
            )

            hostNetworkConfig[:vswitch] ||= []

            hostNetworkConfig[:vswitch] << VIM.HostVirtualSwitchConfig(
              :changeOperation => :add,
              :name => name,
              :spec => vswitch.prepare_spec
            )

            # We only store the properties we are going to use.
            added_vswitches << VIM.HostVirtualSwitch(
              name: name
            )
          end
        end

        def prepare_portgroup_config(env, hostNetworkConfig, added_portgroups,
                                     network_info, provider_config)
          provider_config.portgroups.each_value do |portgroup|
            name = portgroup.name
            vswitch = portgroup.vswitch

            existing = \
              network_info[:portgroup].detect { |pg|
                pg.spec.name == name && pg }

            if existing
              check_existing_portgroup(portgroup, existing)
              next
            end

            env[:ui].info(
              I18n.t('vsphere.info.provision.portgroup.creating',
                     name: name,
                     vswitch: vswitch)
            )

            hostNetworkConfig[:portgroup] ||= []

            spec = portgroup.prepare_spec
            hostNetworkConfig[:portgroup] << VIM.HostPortGroupConfig(
              :changeOperation => :add,
              :spec => spec
            )

            # We only store the properties we are going to use.
            added_portgroups << VIM.HostPortGroup(
              spec: spec
            )
          end
        end

        def check_existing_portgroup(portgroup, existing)
          vswitch = portgroup.vswitch
          if existing.spec.vswitchName != vswitch
            fail Errors::VSphereError,
              _key: :'provision.portgroup.invalid_vswitch',
              name: portgroup.name,
              connected_vswitch: existing.spec.vswitchName,
              expected_vswitch: vswitch
          end

          vlanId = portgroup.vlan_id
          if !vlanId.nil? && existing.spec.vlanId != vlanId
            fail Errors::VSphereError,
              _key: :'provision.portgroup.invalid_vlanId',
              name: portgroup.name,
              existing_vlanId: existing.spec.vlanId,
              expected_vlanId: vlanId
          end
        end

      end
    end
  end
end
