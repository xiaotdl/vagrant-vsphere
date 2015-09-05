require 'rbvmomi'

require 'vSphere/util/vim_helpers'

module VagrantPlugins
  module VSphere
    module Action
      class PrepareNFSValidIds
        VIM = RbVmomi::VIM

        include Util::VimHelpers

        def initialize(app, env)
          @app = app
          @logger = Plugin.logger_for(self.class)
        end

        def call(env)
          machine = env[:machine]

          connection = env[:vsphere].connection
          dc = get_datacenter(connection, machine)

          # We assume that all virtual machines that exist in our current
          # DataCenter are still valid NFS export targets.  Everything else
          # will be deleted.
          #
          # This will fail if a user switches between several different
          # dataceters.  But Vagrant does not have support to handle cases
          # like that.  TODO Teach Vagrant to use composite IDs for the
          # export specifications and allow :nfs_valid_ids to hold objects
          # that would indicate that only particular subsets of that ID tree
          # need to be trimmed.
          env[:nfs_valid_ids] = \
            retrieve_all_datacenter_vm_ids(connection, dc)

          @app.call(env)
        end

        def retrieve_all_datacenter_vm_ids(connection, dc)
          propertyCollector = connection.propertyCollector

          filterSpec = VIM.PropertyFilterSpec(
            :objectSet => [{
              :obj => dc,
              :skip => true,
              :selectSet => [
                VIM.TraversalSpec(
                  :type => 'Datacenter',
                  :path => 'datastore',
                  :skip => true,
                  :selectSet => [
                    VIM.TraversalSpec(
                      :type => 'Datastore',
                      :path => 'vm',
                      :skip => false,
                    )
                  ]
                )
              ]
            }],
            :propSet => [{
              :pathSet => %w(config.uuid),
              :type => 'VirtualMachine'
            }]
          )

          result = propertyCollector.RetrievePropertiesEx(
            :specSet => [filterSpec],
            :options => { }
          )

          return [] unless result

          ids = []
          result.objects.map do |objectContent|
            objectContent.propSet.each do |p|
              case p.name
              when 'config.uuid'
                ids << p.val
              else
                fail "Internal error: Unexpected property returned: #{p.name}"
              end
            end
          end

          ids
        end

      end
    end
  end
end
