require 'rbvmomi'

require 'vSphere/util/vim_helpers'
require 'vSphere/sync'

module VagrantPlugins
  module VSphere
    module Action
      class ConstructPool
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

          Sync.resourceLock.synchronize do
            poolTree = pool_tree(connection, compute.resourcePool)

            vmPath = provider_config.resource_pool_name.split('/')

            treePos = poolTree
            fullPath = []
            parentPool = compute.resourcePool
            missingPath = vmPath.drop_while do |name|
              if treePos.key?(name)
                child = treePos[name]
                treePos = child[:children]
                parentPool = child[:pool]
                fullPath << name
                true
              else
                false
              end
            end

            missingPath.each do |name|
              spec = prepare_pool_spec

              fullPath << name
              env[:ui].info(
                I18n.t('vsphere.info.provision.pool.creating',
                       path: fullPath.join('/'))
              )
              parentPool = parentPool.CreateResourcePool(
                name: name,
                spec: spec,
              )
            end
          end

          @app.call(env)
        end

        def prepare_pool_spec
          VIM.ResourceConfigSpec(
            cpuAllocation: VIM.ResourceAllocationInfo(
              expandableReservation: true,
              limit: -1,
              reservation: 0,
              shares: VIM.SharesInfo(
                level: :normal,
                shares: 0
              ),
            ),
            memoryAllocation: VIM.ResourceAllocationInfo(
              expandableReservation: true,
              limit: -1,
              reservation: 0,
              shares: VIM.SharesInfo(
                level: :normal,
                shares: 0
              ),
            ),
          )
        end

        def pool_tree(connection, root)
          filterSpec = VIM.PropertyFilterSpec(
            :objectSet => [{
                :obj => root,
                :skip => true,
                :selectSet => [
                  VIM.TraversalSpec(
                    :name => "tsRP",
                    :type => 'ResourcePool',
                    :path => 'resourcePool',
                    :skip => false,
                    :selectSet => [
                      VIM.SelectionSpec(:name => "tsRP")
                    ]
                  )
                ]
            }],
            :propSet => [{
              :type => 'ResourcePool',
              :pathSet => ['name', 'parent'],
            }]
          )

          pc = connection.propertyCollector
          result = pc.RetrieveProperties(:specSet => [filterSpec])

          list_to_tree(result, :pool)
        end

      end
    end
  end
end
