require 'rbvmomi'

require 'vSphere/util/vim_helpers'
require 'vSphere/sync'

module VagrantPlugins
  module VSphere
    module Action
      class ConstructFolder
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
            folderTree = folder_tree(connection, dc.vmFolder)

            vmPath = provider_config.folder.split('/')

            treePos = folderTree
            fullPath = []
            parentFolder = dc.vmFolder
            missingPath = vmPath.drop_while do |name|
              if treePos.key?(name)
                child = treePos[name]
                treePos = child[:children]
                parentFolder = child[:folder]
                fullPath << name
                true
              else
                false
              end
            end

            missingPath.each do |name|
              fullPath << name
              env[:ui].info(
                I18n.t('vsphere.info.provision.folder.creating',
                       path: fullPath.join('/'))
              )

              parentFolder = parentFolder.CreateFolder(
                name: name,
              )
            end
          end

          @app.call(env)
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
              :pathSet => ['name', 'parent'],
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
