require 'rbvmomi'

require 'vSphere/util/vim_helpers'
require 'vSphere/sync'

module VagrantPlugins
  module VSphere
    module Action
      class DestroyFolder
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

          Sync.resourceLock.synchronize do
            tree = folder_tree(connection, dc.vmFolder)
            vmPath = provider_config.folder.split('/')

            tree_destroy_path(tree, :folder, vmPath,
              ->(desc) do
                desc[:childEntity].empty? && desc[:children].empty?
              end,
              ->(path, name) do
                env[:ui].info(
                  I18n.t('vsphere.info.provision.folder.deleting',
                         path: (path + [name]).join('/'))
                )
              end,
              ->(desc, removedName, removedDesc) do
                desc[:childEntity].delete(removedDesc[:folder])
              end
            )
          end
          
          @app.call env
        end

        def folder_tree(connection, root)
          filterSpec = VIM.PropertyFilterSpec(
            :objectSet => [{
                :obj => root,
                :skip => true,
                :selectSet => [
                  VIM.TraversalSpec(
                    :name => "tsFolder",
                    :type => 'Folder',
                    :path => 'childEntity',
                    :skip => false,
                    :selectSet => [
                      VIM.SelectionSpec(:name => "tsFolder")
                    ]
                  )
                ]
            }],
            :propSet => [{
              :type => 'Folder',
              :pathSet => ['name', 'parent', 'childEntity'],
            }]
          )

          pc = connection.propertyCollector
          result = pc.RetrieveProperties(:specSet => [filterSpec])

          list_to_tree(result, :folder)
        end

      end
    end
  end
end
