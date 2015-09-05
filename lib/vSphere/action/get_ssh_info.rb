require 'vSphere/util/vim_helpers'

module VagrantPlugins
  module VSphere
    module Action
      class GetSshInfo
        include Util::VimHelpers

        def initialize(app, _env)
          @app = app
          @logger = Plugin.logger_for(self.class)
        end

        def call(env)
          connection = env[:vsphere].connection

          env[:machine_ssh_info] = \
                  get_ssh_info(connection, env[:machine], env)

          @app.call env
        end

        private

        def get_ssh_info(connection, machine, env)
          if machine.id.nil?
            @logger.debug('Machine has no ID')
            return nil 
          end

          vm = get_vm_by_uuid connection, machine

          if vm.nil?
            @logger.debug('Failed to find the VM by its id: ' + machine.id.to_s)
            return nil 
          end

          if vm.guest.ipAddress.nil? || vm.guest.ipAddress.empty?
            @logger.debug('VM has no IP address specified in the' +
                          ' ipAddress field')
            return nil
          end

          address = vm.guest.ipAddress

          @logger.debug("Setting nfs_machine_ip to #{address}")
          env[:nfs_machine_ip] = address

          {
            host: address,
            port: 22
          }
        end
      end
    end
  end
end
