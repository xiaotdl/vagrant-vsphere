require 'thread'

module VagrantPlugins
  module VSphere
    module Sync
      # As actions might be executed in parallel, they may require
      # synchronization.  This module holds all the shared synchronization
      # objects.

      # Lock for env[:vsphere] manipulation.  Most actions use
      # env[:vsphere] after connect_vsphere action.  They may get the
      # :connection property without synchronization then.
      @@envLock = Mutex.new
      def self.envLock
        @@envLock
      end

      # Whenever shared resources needs to be manipulated, such as folders,
      # pools, vswitches, portgroups this lock should be held.  Generally
      # those resource operations are quite fast, so it seems OK from the
      # performance standpoint to serialize them.
      @@resourceLock = Mutex.new
      def self.resourceLock
        @@resourceLock
      end

    end
  end
end
