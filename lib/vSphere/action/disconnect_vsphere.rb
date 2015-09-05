require 'rbvmomi'

require 'vSphere/sync'

module VagrantPlugins
  module VSphere
    module Action
      class DisconnectVSphere
        def initialize(app, _env)
          @app = app
        end

        def call(env)
          Sync.envLock.synchronize do
            subEnv = env[:vsphere]

            if subEnv.disconnect == 0
              subEnv.connection.close
              env.delete(:vsphere)
            end
          end

          @app.call env
        end
      end
    end
  end
end
