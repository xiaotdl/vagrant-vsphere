require "vagrant/action/builtin/mixin_synced_folders"

require 'vSphere/util/vim_helpers'

require 'socket'

module VagrantPlugins
  module VSphere
    module Action
      class PrepareNFSSettings
        include Vagrant::Action::Builtin::MixinSyncedFolders

        include Util::VimHelpers

        def initialize(app, env)
          @app = app
          @logger = Plugin.logger_for(self.class)
        end

        def call(env)
          opts = {
            cached: !!env[:synced_folders_cached],
            config: env[:synced_folders_config],
            disable_usable_check: !!env[:test],
          }
          folders = synced_folders(env[:machine], **opts)

          if folders.key?(:nfs)
            @logger.info("Using NFS, preparing NFS settings by reading host IP")
            add_ips_to_env!(env)
          end

          @app.call(env)
        end

        def add_ips_to_env!(env)
          # This is not 100% bulletproof, but seens to be a good first
          # approximation.
          host_ip = Socket.ip_address_list.find { |ai|
            ai.ipv4? && !ai.ipv4_loopback?
          }.ip_address

          @logger.debug("Setting host_ip to #{host_ip}")

          env[:nfs_host_ip] = host_ip

          connection = env[:vsphere].connection
          address = get_machine_ip(connection, env[:machine])
          unless address.nil?
            @logger.debug("Setting nfs_machine_ip to #{address}")
            env[:nfs_machine_ip] = address 
          else
            @logger.debug("nfs_machine_ip left unset")
          end

          @app.call env
        end

        private

        def get_machine_ip(connection, machine)
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

          vm.guest.ipAddress
        end

      end
    end
  end
end
