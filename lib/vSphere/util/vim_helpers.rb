require 'rbvmomi'

module VagrantPlugins
  module VSphere
    module Util
      module VimHelpers
        def get_datacenter(connection, machine)
          name = machine.provider_config.data_center_name
          dc = connection.serviceInstance.find_datacenter(name)

          if dc.nil?
            fail Errors::VSphereError,
              _key: :missing_datacenter, name: name
          end

          dc
        end

        def get_vm_by_uuid(connection, machine)
          get_datacenter(connection, machine).vmFolder.findByUuid(machine.id)
        end

        def get_resource_pool(datacenter, provider_config)
          compute_resource = get_compute_resource(datacenter, provider_config)

          path = provider_config.resource_pool_name
          if path.is_a? String
            path = path.split('/').reject(&:empty?)
          elsif path.is_a? Enumerable
            # Use as is
          else
            fail Errors::VSphereError,
              _key: :'config.resource_pool.invalid_name_type',
              type: path.class
          end

          pathSoFar = []
          rp = compute_resource.resourcePool
          path.each do |name|
            pathSoFar << name
            rp = rp.find(name)

            if rp.nil?
              fail Errors::VSphereError,
                _key: :'config.resource_pool.missing',
                path: pathSoFar.join('/')
            end
          end

          rp
        end

        def get_compute_resource(datacenter, provider_config)
          name = provider_config.compute_resource_name
          cr = find_clustercompute_or_compute_resource(datacenter, name)

          if cr.nil?
            fail Errors::VSphereError,
              _key: :missing_compute_resource,
              name: name
          end

          cr
        end

        def find_clustercompute_or_compute_resource(datacenter, path)
          if path.is_a? String
            es = path.split('/').reject(&:empty?)
          elsif path.is_a? Enumerable
            es = path
          else
            fail 'Internal error: find_clustercompute_or_compute_resource:' +
              "unexpected path class #{path.class}"
          end

          return datacenter.hostFolder if es.empty?

          final = es.pop

          p = es.inject(datacenter.hostFolder) do |f, e|
            f.find(e, RbVmomi::VIM::Folder) || return
          end

          begin
            if (x = p.find(final, RbVmomi::VIM::ComputeResource))
              x
            elsif (x = p.find(final, RbVmomi::VIM::ClusterComputeResource))
              x
            end
          rescue Exception
            # When looking for the ClusterComputeResource there seems to be
            # some parser error in RbVmomi Folder.find, try this instead
            x = p.childEntity.find { |x2| x2.name == final }
            if x.is_a?(RbVmomi::VIM::ClusterComputeResource) ||
                x.is_a?(RbVmomi::VIM::ComputeResource)
              x
            else
              fail 'Internal error: find_clustercompute_or_compute_resource:' +
                'ex unknown type: ' + x.to_json
            end
          end
        end

        def get_datastore(datacenter, machine)
          name = machine.provider_config.data_store_name
          return if name.nil? || name.empty?

          # find_datastore uses folder datastore that only lists Datastore and
          # not StoragePod, if not found also try datastoreFolder which
          # contains StoragePod(s)
          datacenter.find_datastore(name) || \
            datacenter.datastoreFolder.traverse(name) || \
            fail(Errors::VSphereError, _key: :missing_datastore, name: name)
        end

        # This is a helper that converst a list of objects into a tree.
        # Every object is represented as a hash with a :parent key pointing
        # to the parent VIM object, :name holding liternal name and objKey
        # holding the actual VIM object instance.
        def list_to_tree(l, objKey)
          objKey = objKey.to_sym

          descriptors = Hash[
            l.map do |r|
              desc = {
                objKey => r.obj,
                children: []
              }
              r.propSet.each do |p|
                desc[p.name.to_sym] = p.val
              end
              [r.obj, desc]
            end
          ]

          descriptors.each_value do |desc|
            parent = desc[:parent]
            if descriptors.key?(parent)
              descriptors[parent][:children] << desc
            end
          end

          roots = descriptors.each_value.reject {|desc|
            descriptors.key?(desc[:parent]) }

          # This lambda will generate a single "level" of the result tree.
          # Given a list of descriptions on one level it turns that into a
          # hash with the :name property used as the key and all the other
          # properties stored in the value hash.
          # :parent keys are filtered out - do not need them any more.
          mapLevel = lambda do |descriptors|
            Hash[
              descriptors.map do |desc|
                [desc[:name], 
                  Hash[
                    desc.keys.reject {|k| k == :name || k == :parent } \
                        .map do |k|
                      if k == :children
                        [k, mapLevel.call(desc[:children])]
                      else
                        [k, desc[k]]
                      end
                    end
                  ]
                ]
              end
            ]
          end

          mapLevel.call(roots)
        end

        def tree_destroy_path(tree, objKey, path, should_delete, message,
                              on_delete = nil)
          treePos = tree
          deletePath = []
          path.each do |name|
            break unless treePos.key?(name)

            child = treePos[name]
            deletePath << [name, child]
            treePos = child[:children]
          end
          path = deletePath.map {|name, _child| name }
          deletePath.reverse!

          lastRemoved = nil
          path.pop
          deletePath.each do |name, desc|
            unless lastRemoved.nil?
              desc[:children].delete(lastRemoved[0])
              on_delete.call(desc, *lastRemoved) unless on_delete.nil?
            end

            break unless should_delete.call(desc)

            message.call(path, name)
            lastRemoved = [name, desc]
            path.pop
            desc[objKey].Destroy_Task.wait_for_completion
          end
        end

      end
    end
  end
end
