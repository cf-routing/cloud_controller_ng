require 'vcap/rest_api'
require 'vcap/request'
require 'presenters/error_presenter'
require 'sinatra/reloader'
require 'securerandom'
require 'steno'

module Sinatra
  module VCAP
    module Helpers
      def in_test_mode?
        ENV.fetch('CC_TEST', nil)
      end
    end

    # Called when the caller registers the sinatra extension.  Sets up
    # the standard sinatra environment for vcap.
    def self.registered(app)
      app.helpers VCAP::Helpers

      app.not_found do
        # sinatra wants to drive us through the not_found block for *every*
        # 404, with no way of disabling it. We want the logic in this block
        # for access to non-existent urls, but not for 404s that we return
        # from our logic. This is a check to see if we already did a 404 below.
        # We don't really have a class to attach a member variable to, so we have to
        # use the env to flag this.
        unless request.env['vcap_exception_body_set']
          error = ::CloudController::Errors::NotFound.new_from_details('NotFound')
          presenter = ErrorPresenter.new(error, in_test_mode?)

          body Oj.dump(presenter.to_hash, mode: :compat)
        end
      end

      app.error do
        error = request.env['sinatra.error']
        presenter = ErrorPresenter.new(error, in_test_mode?)

        status(presenter.response_code)

        if presenter.client_error?
          logger.info(presenter.log_message)
        else
          logger.error(presenter.log_message)
        end

        request.env['vcap_exception_body_set'] = true

        payload = Oj.dump(presenter.to_hash, mode: :compat)
        body payload.concat("\n")
      end
    end

    # A user of the VCAP sinatra extension must call vcap_configure
    # in order to setup error handling correctly.  Unfortunately,
    # we are not able to do this from inside self.registered as sinatra
    # doesn't honor the settings we make there.
    #
    # @option opts [String] :logger_name Name of the Steno logger to use.
    # Defaults to vcap.rest_api
    #
    # @option opts [String] :reload_path If specified and the app is running in
    # :development mode, sinatra will reload all files under the provided path
    # whenever they change.
    def vcap_configure(opts={})
      # we can't just do this in registered sinatra seems to reset
      # our configuration after register
      configure do
        set(:show_exceptions, false)
        set(:raise_errors, false)
        set(:dump_errors, false)
      end

      configure :development do
        register Sinatra::Reloader
        if opts[:reload_path]
          Dir["#{opts[:reload_path]}/**/*.rb"].each do |file|
            also_reload file
          end
        end
      end

      before do
        logger_name = opts[:logger_name] || 'vcap.api'
        env['rack.logger'] = Steno.logger(logger_name)

        ::VCAP::CloudController::Diagnostics.new.request_received(request)
      end

      after do
        headers['Content-Type'] = 'application/json;charset=utf-8'
        ::VCAP::CloudController::Diagnostics.new.request_complete
        nil
      end
    end
  end
end
