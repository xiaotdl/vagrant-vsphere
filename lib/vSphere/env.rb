require 'vSphere/sync'
require 'vSphere/util/network'

module VagrantPlugins
  module VSphere
    class Env

      attr_accessor :connection

      def initialize(connection)
        @connect_count = 1
        @connection = connection

        @next_device_key = 1

        @network_info_cache = Hash.new { |h, k| h[k] = {} }
      end

      # Should be called under Sync.envLock.
      # Returns: new connection count.
      def connect
        unless Sync.envLock.owned?
          fail "Internal error: Expected Sync.envLock"
        end

        @connect_count += 1
      end

      # Should be called under Sync.envLock.
      # Returns: new connection count.
      def disconnect
        unless Sync.envLock.owned?
          fail "Internal error: Expected Sync.envLock"
        end

        @connect_count -= 1
      end

      # Should be called outside Sync.envLock or Sync.resourceLock.
      # Will lock Sync.resourceLock.
      #
      # When lock is false, will only check that Sync.resourceLock is
      # locked.
      def network_info(host, lock=true)
        if lock
          Sync.resourceLock.synchronize do
            Util::Network.retreive_network_info(self, @connection, host)
          end
        else
          unless Sync.resourceLock.owned?
            fail "Internal error: Expected Sync.resourceLock"
          end

          Util::Network.retreive_network_info(self, @connection, host)
        end
      end

      # Internal.  To be used by Util::retreive_network_info().
      def network_info_cache(path)
        @network_info_cache[path]
      end

      # VSphere requires uniqe device keys to be provided when new virtual
      # hardware is added.  Use this method to obtain the next key.
      #
      # Should be called outside Sync.envLock.
      # Will lock Sync.envLock.
      def next_device_key
        Sync.envLock.synchronize do
          key = @next_device_key
          @next_device_key += 1

          # VSphere will reassign the key.  Docs recommend negative values,
          # to make sure not to collide with any existing device key.
          -key
        end
      end

    end
  end
end
