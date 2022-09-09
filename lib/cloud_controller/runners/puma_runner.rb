require 'puma'
require 'puma/configuration'

module VCAP::CloudController
  class PumaRunner
    def initialize(config, app, logger, periodic_updater, request_logs)
      @logger = logger
      @periodic_updater = periodic_updater
      @request_logs = request_logs
      puma_config = Puma::Configuration.new do |conf|
        # this is actually called everytime a worker is started
        # https://github.com/puma/puma/blob/5f3f489ee867317c47724d0fc5b1d906f1b23de6/lib/puma/dsl.rb#L607
        # we probably want to come up witha  different way to do this.  Perhaps a singleton?
        conf.after_worker_fork {
          Thread.new do
            EM.run do
              @periodic_updater.setup_updates
            end
          end
        }
      end
      events = Puma::Events.new($stdout, $stderr)
      events.on_stopped do
        stop!
      end

      @puma_launcher = Puma::Launcher.new(puma_config, events: events)
    end

    def start!
      @puma_launcher.run
    rescue => e
      @logger.error "Encountered error: #{e}\n#{e.backtrace.join("\n")}"
      raise e
    end

    def stop!
      @logger.info('Stopping EventMachine')
      EM.stop
      @request_logs.log_incomplete_requests if @request_logs
    end
  end
end
