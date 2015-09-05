require 'rbvmomi'

require 'vSphere/sync'

module VagrantPlugins
  module VSphere
    module Util
      module Network

        VIM = RbVmomi::VIM

        # We assume that during one "operation", such as virtual machine
        # creation or destruction, we are the only one who is actively
        # manipulating objects referenced in our config.  This allows us to
        # fetch the network configuration of an individual host only once
        # and then use our cached version.  We record our own modifications
        # in separate datastructures, and use "combined" view.
        #
        # Must be called under Sync.resourceLock.
        def self.retreive_network_info(vsphere_env, connection, host)
          unless Sync.resourceLock.owned?
            fail "Internal error: Sync.resourceLock is not owned by" \
              + " the current thread while calling retreive_network_info()"
          end

          path = host.path.map { |obj, name| name }.join("/")

          network_info = vsphere_env.network_info_cache(path)
          return network_info unless network_info.empty?

          propertyCollector = connection.propertyCollector

          # TODO Retreive distrubuted port groups, to allow distributed
          # port group to be selected when cloning.  See
          # Action::Clone.prepare_network_card_backing_info.

          filterSpec = VIM.PropertyFilterSpec(
            :objectSet => [{
              :obj => host,
              :skip => true,
              :selectSet => [
                VIM.TraversalSpec(
                  :type => 'HostSystem',
                  :path => 'configManager.networkSystem',
                  :skip => false,
                )
              ]
            }],
            :propSet => [{
              :type => 'HostNetworkSystem',
              :pathSet => %w(networkInfo.vswitch networkInfo.portgroup),
            }]
          )

          result = propertyCollector.RetrievePropertiesEx(
            :specSet => [filterSpec],
            :options => { }
          )

          # network_info will store both objects we received from the
          # vSphere and objects we create ourselves to record creation
          # operations we initiated.
          network_info[:vswitch] = []
          network_info[:portgroup] = []

          return network_info unless result

          result.objects.each do |objectContent|
            objectContent.propSet.each do |p|
              case p.name
              when 'networkInfo.vswitch'
                network_info[:vswitch].concat(p.val)
              when 'networkInfo.portgroup'
                network_info[:portgroup].concat(p.val)
              else
                fail "Internal error: Unexpected property returned: #{p.name}"
              end
            end
          end

          network_info
        end

      end
    end
  end
end
