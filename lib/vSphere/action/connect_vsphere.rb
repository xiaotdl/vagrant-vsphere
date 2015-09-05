require 'rbvmomi'

require 'vSphere/env'
require 'vSphere/sync'

module VagrantPlugins
  module VSphere
    module Action
      class ConnectVSphere
        VIM = RbVmomi::VIM

        def initialize(app, _env)
          @app = app
        end

        def call(env)
          config = env[:machine].provider_config

          Sync.envLock.synchronize do
            if env[:vsphere].nil?
              env[:vsphere] = Env.new(
                VIM.connect(host: config.host,
                            user: config.user,
                            password: config.password,
                            insecure: config.insecure,
                            proxyHost: config.proxy_host,
                            proxyPort: config.proxy_port)
              )
            else
              env[:vsphere].connect
            end
          end

          @app.call env
        end
      end
    end
  end
end
