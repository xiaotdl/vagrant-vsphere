require 'rbvmomi'

require 'vSphere/util/vim_helpers'
require 'vSphere/sync'

module VagrantPlugins
  module VSphere
    module Action
      class DestroyPool
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
            tree = pool_tree(connection, compute.resourcePool)
            vmPath = provider_config.resource_pool_name.split('/')

            tree_destroy_path(tree, :pool, vmPath,
              ->(desc) do
                desc[:vm].empty? && desc[:children].empty?
              end,
              ->(path, name) do
                env[:ui].info(
                  I18n.t('vsphere.info.provision.pool.deleting',
                         path: (path + [name]).join('/'))
                )
              end
            )
          end
          
          @app.call env
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
              :pathSet => ['name', 'parent', 'vm'],
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
