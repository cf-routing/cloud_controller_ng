require 'spec_helper'

module VCAP::CloudController
  module Jobs::Runtime
    RSpec.describe  PruneAgedDeployments, job_context: :worker do
      subject(:job) { PruneAgedDeployments.new }

      it { is_expected.to be_a_valid_job }

      it 'knows its job name' do
        expect(job.job_name_in_configuration).to equal(:aged_deployments_cleanup)
      end

      describe '#perform' do
        let(:app) { AppModel.make }
        let(:process) { ProcessModel.make(app: app, type: 'web')}
        let(:safe_states) { [ DeploymentModel::DEPLOYED_STATE,  DeploymentModel::CANCELING_STATE,  DeploymentModel::CANCELED_STATE] }
        before do
          TestConfig.override({ max_retained_deployments_per_app: 15 })
        end

        it 'deletes all the aged deletable deployments' do
          total = 50
          DeploymentModel.clear
          (1..50).each do |i|
            DeploymentModel.make(id: i, state: safe_states[i % 3], app: app, created_at: Time.now - total + i)
          end
          job.perform
          expect(DeploymentModel.count).to be(15)
          expect(DeploymentModel.first.id).to be(36)
          expect(DeploymentModel.last.id).to be(50)
        end

        it 'does not delete aged in-flight deployments' do
          total = 50
        end
          (1..20).each do |i|
            DeploymentModel.make(id: i, state: DeploymentModel::DEPLOYED_STATE, app: app, created_at: Time.now - total + i)
          end
          (21..40).each do |i|
            DeploymentModel.make(id: i, state: DeploymentModel::DEPLOYING_STATE, app: app, created_at: Time.now - total + i)
          end
          (41..50).each do |i|
            DeploymentModel.make(id: i, state: DeploymentModel::DEPLOYED_STATE, app: app, created_at: Time.now - total + i)
          end
          job.perform
          expect(DeploymentModel.count).to be(15)
          expect(DeploymentModel.first.id).to be(16)
          expect(DeploymentModel.first.id).to be(21)
          expect(DeploymentModel.last.id).to be(50)
        end

    end
  end
end
