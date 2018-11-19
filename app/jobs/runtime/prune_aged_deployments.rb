require 'repositories/app_usage_event_repository'

module VCAP::CloudController
  module Jobs
    module Runtime
      class AppUsageEventsCleanup < VCAP::CloudController::Jobs::CCJob
        attr_accessor :cutoff_age_in_days

        def initialize(cutoff_age_in_days)
          @cutoff_age_in_days = cutoff_age_in_days
        end

        def perform
          logger = Steno.logger('cc.background')
          logger.info('Cleaning up old AppUsageEvent rows')

          repository = Repositories::AppUsageEventRepository.new
          deleted_count = repository.delete_events_older_than(cutoff_age_in_days)

          logger.info("Cleaned up #{deleted_count} AppUsageEvent rows")

          q1 = DeploymentModel.sort(:created_at).limit(DeploymentModel.count - limit).ignore(state:DeploymentModel::DEPLOYING_STATE)

          q2 = DeploymentModel.ignore(state:DeploymentModel::DEPLOYING_STATE).sort(:created_at).limit(DeploymentModel.count - limit)

          q1.delete_all
          q2.delete_all
        end

        def job_name_in_configuration
          :app_usage_events_cleanup
        end

        def max_attempts
          1
        end
      end
    end
  end
end
