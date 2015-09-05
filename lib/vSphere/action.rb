require 'vagrant'
require 'vagrant/action/builder'

module VagrantPlugins
  module VSphere
    module Action
      include Vagrant::Action::Builtin

      # Completely free resources of the underlying virtual machine.
      def self.action_destroy
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use ConnectVSphere
          b.use Call, IsCreated do |env, b2|
            unless env[:result]
              b2.use MessageNotCreated
              next
            end

            b2.use Call, IsRunning do |env2, b3|
              if env2[:result]
                if env2[:force_confirm_destroy]
                  b3.use PowerOff
                  next
                end

                b3.use Call, GracefulHalt, :poweroff, :running do |env3, b4|
                  b4.use PowerOff unless env3[:result]
                end
              end
            end

            b2.use Destroy

            b2.use PrepareNFSValidIds
            b2.use SyncedFolderCleanup
          end

          b.use DestroyNetwork
          b.use DestroyPool
          b.use DestroyFolder
        end
      end

      # vSphere specific
      def self.action_get_ssh_info
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use ConnectVSphere
          b.use GetSshInfo
          b.use DisconnectVSphere
        end
      end

      # vSphere specific
      def self.action_get_state
        Vagrant::Action::Builder.new.tap do |b|
          b.use HandleBox
          b.use ConfigValidate
          b.use ConnectVSphere
          b.use GetState
          b.use DisconnectVSphere
        end
      end

      # Halt the virtual machine, gracefully or by force.
      def self.action_halt
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use ConnectVSphere
          b.use Call, IsCreated do |env, b2|
            unless env[:result]
              b2.use MessageNotCreated
              next
            end

            b2.use Call, IsRunning do |env2, b3|
              unless env2[:result]
                b3.use MessageNotRunning
                next
              end

              b3.use Call, GracefulHalt, :poweroff, :running do |env3, b4|
                b4.use PowerOff unless env3[:result]
              end
            end
          end
          b.use DisconnectVSphere
        end
      end

      def self.action_provision
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use ConnectVSphere
          b.use Call, IsCreated do |env, b2|
            unless env[:result]
              b2.use MessageNotCreated
              next
            end

            b2.use Call, IsRunning do |env2, b3|
              unless env2[:result]
                b3.use MessageNotRunning
                next
              end

              b3.use Provision
            end
          end

          b.use DisconnectVSphere
        end
      end

      # Reloading the machine, which brings it down, sucks in new
      # configuration, and brings the machine back up with the new
      # configuration.
      def self.action_reload
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConnectVSphere
          b.use Call, IsCreated do |env, b2|
            unless env[:result]
              b2.use MessageNotCreated
              next
            end
            b2.use action_halt
            b2.use action_start
          end
          b.use DisconnectVSphere
        end
      end

      # Exec into an SSH shell.
      def self.action_ssh
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use Call, IsCreated do |env, b2|
            unless env[:result]
              b2.use MessageNotCreated
              next
            end

            b2.use Call, IsRunning do |env2, b3|
              unless env2[:result]
                b3.use MessageNotRunning
                next
              end

              b3.use SSHExec
            end
          end
        end
      end

      # Run a single SSH command.
      def self.action_ssh_run
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use Call, IsCreated do |env, b2|
            unless env[:result]
              b2.use MessageNotCreated
              next
            end

            b2.use Call, IsRunning do |env2, b3|
              unless env2[:result]
                b3.use MessageNotRunning
                next
              end

              b3.use SSHRun
            end
          end
        end
      end

      # Start a VM, assuming it is already imported and exists.
      # A precondition of this action is that the VM exists.
      def self.action_start
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use ConnectVSphere
          b.use Call, IsRunning do |env, b2|
            # If the VM is running, then our work here is done, exit
            if env[:result]
              unless env[:expect_running]
                b2.use MessageAlreadyRunning
              end
              next
            end

            b2.use PowerOn unless env[:result]
          end
          b.use Provision

          b.use PrepareNFSValidIds
          b.use SyncedFolderCleanup
          b.use SyncedFolders
          b.use PrepareNFSSettings
          b.use SetHostname

          b.use DisconnectVSphere
        end
      end

      # Sync folders to a running machine without a reboot.
      def self.action_sync_folders
        Vagrant::Action::Builder.new.tap do |b|
          b.use PrepareNFSValidIds
          b.use SyncedFolders
          b.use PrepareNFSSettings
        end
      end

      def self.action_up
        Vagrant::Action::Builder.new.tap do |b|
          b.use HandleBox
          b.use ConfigValidate
          b.use ConnectVSphere
          b.use Call, IsCreated do |env, b2|
            if env[:result]
              b2.use MessageAlreadyCreated
              next
            end

            b2.use PrepareNFSValidIds
            b2.use ConstructPool
            b2.use ConstructFolder
            b2.use ConstructNetwork
            b2.use Clone
          end
          b.use EnvSet, expect_running: true
          b.use action_start

          b.use DisconnectVSphere
        end
      end

      # autoload
      action_root = Pathname.new(File.expand_path('../action', __FILE__))
      autoload :Clone, action_root.join('clone')
      autoload :DisconnectVSphere, action_root.join('disconnect_vsphere')
      autoload :ConnectVSphere, action_root.join('connect_vsphere')
      autoload :ConstructFolder, action_root.join('construct_folder')
      autoload :ConstructNetwork, action_root.join('construct_network')
      autoload :ConstructPool, action_root.join('construct_pool')
      autoload :Destroy, action_root.join('destroy')
      autoload :DestroyPool, action_root.join('destroy_pool')
      autoload :DestroyNetwork, action_root.join('destroy_network')
      autoload :DestroyFolder, action_root.join('destroy_folder')
      autoload :GetSshInfo, action_root.join('get_ssh_info')
      autoload :GetState, action_root.join('get_state')
      autoload :IsCreated, action_root.join('is_created')
      autoload :IsRunning, action_root.join('is_running')
      autoload :MessageAlreadyCreated, action_root.join('message_already_created')
      autoload :MessageAlreadyRunning, action_root.join('message_already_running')
      autoload :MessageNotCreated, action_root.join('message_not_created')
      autoload :MessageNotRunning, action_root.join('message_not_running')
      autoload :PowerOff, action_root.join('power_off')
      autoload :PowerOn, action_root.join('power_on')
      autoload :PrepareNFSValidIds, action_root.join('prepare_nfs_valid_ids')
      autoload :PrepareNFSSettings, action_root.join('prepare_nfs_settings')
    end
  end
end
