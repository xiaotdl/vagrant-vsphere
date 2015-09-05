require 'rbvmomi'

require 'vSphere/util/vim_helpers'
require 'vSphere/sync'

module VagrantPlugins
  module VSphere
    module Action
      class DestroyNetwork
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
            # I was not able to easily map port groups to VMs, in order to
            # check if a port group is used.  On the other hand it is very
            # easy with networks.
            #
            # Initially I thought I can check if a port group is used by
            # checking its "port" array.  Generally ports are automatically
            # created when a port group is used to connect a VM.  But it
            # turns out that sometimes they are not.  Not sure why that
            # happens.
            #
            # Unfortunately it is also true the other way around: an empty
            # port group may have ports visible in the "port" array.

            portgroups, networks = retreive_portgroups(connection, host)
            destroy_portgroups(env, host, portgroups, networks,
                               provider_config)

            vswitches = retreive_vswitches(connection, host)
            destroy_vswitches(env, host, vswitches, provider_config)
          end
          
          @app.call env
        end

        private

        def destroy_portgroups(env, host, portgroups, networks,
                               provider_config)
          toDelete = Hash[
            provider_config.portgroups.select do |name, portgroup|
              portgroup.auto_delete &&
                networks.key?(name) &&
                networks[name][:empty]
            end.map do |name, _portgroup|
              [name, 1]
            end
          ]

          hostNetworkConfig = VIM.HostNetworkConfig(
            portgroup: []
          )

          portgroups.each do |portgroup|
            name = portgroup.spec.name

            next unless toDelete.key?(name)

            # XXX Port groups not connected to any VM may still have active
            # ports.  So in order to reliably delete port groups we
            # created, we can not rely on portgroup.port.empty?.  Assume
            # that our network checking is reliable enough.

            env[:ui].info(
              I18n.t('vsphere.info.provision.portgroup.deleting',
                     name: name,
                     vswitch: portgroup.spec.vswitchName)
            )
            hostNetworkConfig.portgroup << VIM.HostPortGroupConfig(
              changeOperation: 'remove',
              spec: portgroup.spec
            )
          end

          unless hostNetworkConfig.portgroup.empty?
            host.configManager.networkSystem.UpdateNetworkConfig(
              :config => hostNetworkConfig,
              :changeMode => :modify
            )
          end
        end

        def destroy_vswitches(env, host, vswitches, provider_config)
          toDelete = Hash[
            provider_config.vswitches.reject do |name, vswitch|
              !vswitch.auto_delete
            end.map do |name, _vswitch|
              [name, 1]
            end
          ]

          hostNetworkConfig = VIM.HostNetworkConfig(
            vswitch: []
          )

          vswitches.each do |vswitch|
            name = vswitch.name

            next unless toDelete.key?(name)

            # Do not touch vswitches that have anything connected to them.
            next unless vswitch.portgroup.empty? && vswitch.pnic.empty?

            env[:ui].info(
              I18n.t('vsphere.info.provision.vswitch.deleting', name: name)
            )
            hostNetworkConfig.vswitch << VIM.HostVirtualSwitchConfig(
              changeOperation: 'remove',
              name: name
            )
          end

          unless hostNetworkConfig.vswitch.empty?
            host.configManager.networkSystem.UpdateNetworkConfig(
              :config => hostNetworkConfig,
              :changeMode => :modify
            )
          end
        end

        def retreive_vswitches(connection, host)
          filterSpec = VIM.PropertyFilterSpec(
            :objectSet => [{
              :obj => host,
              :skip => false,
            }],
            :propSet => [{
              :pathSet => %w(config.network.vswitch),
              :type => 'HostSystem'
            }]
          )

          pc = connection.propertyCollector
          result = pc.RetrieveProperties(:specSet => [filterSpec])

          vswitches = []

          return [] unless result

          result.each do |hostInfo|
            hostInfo.propSet.each do |p|
              case p.name
              when 'config.network.vswitch'
                vswitches.concat(p.val)
              else
                fail "Internal error: Unexpected property returned: #{p.name}"
              end
            end
          end

          vswitches
        end

        def retreive_portgroups(connection, host)
          filterSpec = VIM.PropertyFilterSpec(
            :objectSet => [{
              :obj => host,
              :skip => false,
              :selectSet => [
                VIM.TraversalSpec(
                  :type => 'HostSystem',
                  :path => 'network',
                  :skip => false,
                )
              ]
            }],
            :propSet => [{
              :type => 'HostSystem',
              :pathSet => %w(config.network.portgroup),
            }, {
              :type => 'Network',
              :pathSet => %w(name vm),
            }]
          )

          pc = connection.propertyCollector
          results = pc.RetrieveProperties(:specSet => [filterSpec])

          portgroups = []
          networks = {}

          return [portgroups, networks] unless results

          results.each do |result|
            case result.obj
            when VIM::HostSystem
              result.propSet.each do |p|
                case p.name
                when 'config.network.portgroup'
                  portgroups.concat(p.val)
                else
                  fail "Internal error: Unexpected property returned for" \
                    + "VIM::HostSystem: #{p.name}"
                end
              end
            when VIM::Network
              name = nil
              empty = false
              result.propSet.each do |p|
                case p.name
                when 'name'
                  name = p.val
                when 'vm'
                  empty = p.val.empty?
                else
                  fail "Internal error: Unexpected property returned for" \
                    + "VIM::Network: #{p.name}"
                end
              end

              fail "Internal error: Missing 'name' property" if name.nil?

              networks[name] = { empty: empty }
            else
              fail "Internal error: Unexpected result object class:" \
                + " #{result.obj.class}"
            end
          end

          [portgroups, networks]
        end

      end
    end
  end
end
