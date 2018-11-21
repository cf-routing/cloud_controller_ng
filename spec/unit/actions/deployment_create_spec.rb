require 'spec_helper'
require 'actions/deployment_create'

module VCAP::CloudController
  RSpec.describe DeploymentCreate do
    let(:app) { VCAP::CloudController::AppModel.make }
    let!(:web_process) { VCAP::CloudController::ProcessModel.make(app: app, instances: 3) }
    let(:original_droplet) { VCAP::CloudController::DropletModel.make(app: app, process_types: { 'web' => 'asdf' }) }
    let(:next_droplet) { VCAP::CloudController::DropletModel.make(app: app, process_types: { 'web' => '1234' }) }
    let!(:route1) { VCAP::CloudController::Route.make(space: app.space) }
    let!(:route_mapping1) { VCAP::CloudController::RouteMappingModel.make(app: app, route: route1, process_type: web_process.type) }
    let!(:route2) { VCAP::CloudController::Route.make(space: app.space) }
    let!(:route_mapping2) { VCAP::CloudController::RouteMappingModel.make(app: app, route: route2, process_type: web_process.type) }
    let(:user_audit_info) { UserAuditInfo.new(user_guid: '123', user_email: 'connor@example.com', user_name: 'braa') }

    before do
      app.update(droplet: original_droplet)
    end

    describe '#create' do
      context 'when a new droplet is provided' do
        it 'creates a deployment with the provided droplet' do
          deployment = nil

          expect {
            deployment = DeploymentCreate.create(app: app, droplet: next_droplet, user_audit_info: user_audit_info)
          }.to change { DeploymentModel.count }.by(1)

          expect(deployment.state).to eq(DeploymentModel::DEPLOYING_STATE)
          expect(deployment.app_guid).to eq(app.guid)
          expect(deployment.droplet_guid).to eq(next_droplet.guid)
          expect(deployment.previous_droplet).to eq(original_droplet)
          expect(deployment.original_web_process_instance_count).to eq(3)
        end

        it 'sets the current droplet of the app to be the provided droplet' do
          DeploymentCreate.create(app: app, droplet: next_droplet, user_audit_info: user_audit_info)

          expect(app.droplet).to eq(next_droplet)
        end

        it 'creates a revision and sets it on the process and stores its guid and version on the deployment' do
          deployment = nil
          expect {
            deployment = DeploymentCreate.create(app: app, droplet: next_droplet, user_audit_info: user_audit_info)
          }.to change { RevisionModel.count }.by(1)
          expect(deployment.revision_guid).to eq(RevisionModel.last.guid)
          expect(deployment.revision_version).to eq(RevisionModel.last.version)
          expect(deployment.deploying_web_process.revision).to eq(RevisionModel.last)
        end

        it 'creates a process of web-deployment-guid type with the same characteristics as the existing web process' do
          deployment = DeploymentCreate.create(app: app, droplet: app.droplet, user_audit_info: user_audit_info)

          deploying_web_process = app.processes.select { |p| p.type == "web-deployment-#{deployment.guid}" }.first
          expect(deploying_web_process.state).to eq ProcessModel::STARTED
          expect(deploying_web_process.command).to eq(web_process.command)
          expect(deploying_web_process.memory).to eq(web_process.memory)
          expect(deploying_web_process.file_descriptors).to eq(web_process.file_descriptors)
          expect(deploying_web_process.disk_quota).to eq(web_process.disk_quota)
          expect(deploying_web_process.metadata).to eq(web_process.metadata)
          expect(deploying_web_process.detected_buildpack).to eq(web_process.detected_buildpack)
          expect(deploying_web_process.health_check_timeout).to eq(web_process.health_check_timeout)
          expect(deploying_web_process.health_check_type).to eq(web_process.health_check_type)
          expect(deploying_web_process.health_check_http_endpoint).to eq(web_process.health_check_http_endpoint)
          expect(deploying_web_process.health_check_invocation_timeout).to eq(web_process.health_check_invocation_timeout)
          expect(deploying_web_process.enable_ssh).to eq(web_process.enable_ssh)
          expect(deploying_web_process.ports).to eq(web_process.ports)
        end

        context 'when there are multiple web processes' do
          let!(:web_process) do
            VCAP::CloudController::ProcessModel.make(
              app: app,
              command: 'old command!',
              instances: 3,
              type: VCAP::CloudController::ProcessTypes::WEB,
              created_at: Time.now - 24.hours
            )
          end
          let!(:newer_web_process) do
            VCAP::CloudController::ProcessModel.make(
              app: app,
              command: 'new command!',
              instances: 4,
              type: VCAP::CloudController::ProcessTypes::WEB,
              created_at: Time.now - 23.hours
            )
          end

          it 'creates a process of web-deployment-guid type with the same characteristics as the oldest web process' do
            deployment = DeploymentCreate.create(app: app, droplet: app.droplet, user_audit_info: user_audit_info)

            deploying_web_process = app.processes.select { |p| p.type == "web-deployment-#{deployment.guid}" }.first
            expect(deploying_web_process.state).to eq ProcessModel::STARTED
            expect(deploying_web_process.command).to eq(web_process.command)
            expect(deploying_web_process.memory).to eq(web_process.memory)
            expect(deploying_web_process.file_descriptors).to eq(web_process.file_descriptors)
            expect(deploying_web_process.disk_quota).to eq(web_process.disk_quota)
            expect(deploying_web_process.metadata).to eq(web_process.metadata)
            expect(deploying_web_process.detected_buildpack).to eq(web_process.detected_buildpack)
            expect(deploying_web_process.health_check_timeout).to eq(web_process.health_check_timeout)
            expect(deploying_web_process.health_check_type).to eq(web_process.health_check_type)
            expect(deploying_web_process.health_check_http_endpoint).to eq(web_process.health_check_http_endpoint)
            expect(deploying_web_process.health_check_invocation_timeout).to eq(web_process.health_check_invocation_timeout)
            expect(deploying_web_process.enable_ssh).to eq(web_process.enable_ssh)
            expect(deploying_web_process.ports).to eq(web_process.ports)
          end
        end

        it 'saves the webish process on the deployment' do
          deployment = DeploymentCreate.create(app: app, droplet: app.droplet, user_audit_info: user_audit_info)

          deploying_web_process = app.processes.select { |p| p.type == "web-deployment-#{deployment.guid}" }.first
          expect(deployment.deploying_web_process_guid).to eq(deploying_web_process.guid)
        end

        it 'creates route mappings for each route mapped to the existing web process' do
          deployment = DeploymentCreate.create(app: app, droplet: app.droplet, user_audit_info: user_audit_info)
          deploying_web_process = app.processes.select { |p| p.type == "web-deployment-#{deployment.guid}" }.first

          expect(deploying_web_process.routes).to contain_exactly(route1, route2)
        end

        it 'records an audit event for the deployment' do
          deployment = DeploymentCreate.create(app: app, droplet: next_droplet, user_audit_info: user_audit_info)

          event = Event.last
          expect(event.type).to eq('audit.app.deployment.create')
          expect(event.actor).to eq('123')
          expect(event.actor_type).to eq('user')
          expect(event.actor_name).to eq('connor@example.com')
          expect(event.actor_username).to eq('braa')
          expect(event.actee).to eq(app.guid)
          expect(event.actee_type).to eq('app')
          expect(event.actee_name).to eq(app.name)
          expect(event.timestamp).to be
          expect(event.space_guid).to eq(app.space_guid)
          expect(event.organization_guid).to eq(app.space.organization.guid)
          expect(event.metadata).to eq({
                                           'droplet_guid' => next_droplet.guid,
                                           'deployment_guid' => deployment.guid,
                                       })
        end

        it 'creates a DeploymentProcessModel to save historical information about the deploying processes' do
          deployment = DeploymentCreate.create(app: app, droplet: next_droplet, user_audit_info: user_audit_info)

          expect(
            deployment.historical_related_processes.map(&:deployment_guid)
          ).to contain_exactly(deployment.guid)

          expect(
            deployment.historical_related_processes.map(&:process_guid)
          ).to contain_exactly(deployment.deploying_web_process.guid)

          expect(
            deployment.historical_related_processes.map(&:process_type)
          ).to contain_exactly(deployment.deploying_web_process.type)
        end

        context 'when the app does not have a droplet set' do
          let(:app_without_current_droplet) { VCAP::CloudController::AppModel.make }
          let(:next_droplet) { VCAP::CloudController::DropletModel.make(app: app_without_current_droplet, process_types: { 'web' => 'asdf' }) }

          it 'sets the droplet on the deployment' do
            deployment = DeploymentCreate.create(app: app_without_current_droplet, droplet: next_droplet, user_audit_info: user_audit_info)

            expect(deployment.app).to eq(app_without_current_droplet)
            expect(deployment.droplet).to eq(next_droplet)
          end

          it 'has a nil previous droplet' do
            deployment = DeploymentCreate.create(app: app_without_current_droplet, droplet: next_droplet, user_audit_info: user_audit_info)

            expect(deployment.previous_droplet).to eq(nil)
          end

          it 'records an audit event for the deployment' do
            deployment = DeploymentCreate.create(app: app_without_current_droplet, droplet: next_droplet, user_audit_info: user_audit_info)

            event = Event.last
            expect(event.type).to eq('audit.app.deployment.create')
            expect(event.actor).to eq('123')
            expect(event.actor_type).to eq('user')
            expect(event.actor_name).to eq('connor@example.com')
            expect(event.actor_username).to eq('braa')
            expect(event.actee).to eq(app_without_current_droplet.guid)
            expect(event.actee_type).to eq('app')
            expect(event.actee_name).to eq(app_without_current_droplet.name)
            expect(event.timestamp).to be
            expect(event.space_guid).to eq(app_without_current_droplet.space_guid)
            expect(event.organization_guid).to eq(app_without_current_droplet.space.organization.guid)
            expect(event.metadata).to eq({
                                             'droplet_guid' => next_droplet.guid,
                                             'deployment_guid' => deployment.guid,
                                         })
          end
        end

        context 'when the current droplet assignment fails' do
          let(:unaffiliated_droplet) { VCAP::CloudController::DropletModel.make }

          it 'raises a AppAssignDroplet error' do
            expect {
              DeploymentCreate.create(app: app, droplet: unaffiliated_droplet, user_audit_info: user_audit_info)
            }.to raise_error DeploymentCreate::SetCurrentDropletError, /Ensure the droplet exists and belongs to this app/
          end
        end

        context 'when there is an existing deployment' do
          let(:originally_desired_instance_count) { 10 }
          let!(:existing_deployment) do
            DeploymentModel.make(
              app: app,
              state: DeploymentModel::DEPLOYING_STATE,
              droplet: nil,
              previous_droplet: original_droplet,
              original_web_process_instance_count: originally_desired_instance_count,
            )
          end

          before do
            web_process.update(instances: 5)
            web_process.save
          end

          it 'creates a new deployment with the instance count from the existing deployment' do
            deployment = nil

            expect {
              deployment = DeploymentCreate.create(app: app, droplet: next_droplet, user_audit_info: user_audit_info)
            }.to change { DeploymentModel.count }.by(1)

            expect(deployment.state).to eq(DeploymentModel::DEPLOYING_STATE)
            expect(deployment.app_guid).to eq(app.guid)
            expect(deployment.droplet_guid).to eq(next_droplet.guid)
            expect(deployment.previous_droplet).to eq(original_droplet)
            expect(deployment.original_web_process_instance_count).to eq(originally_desired_instance_count)
          end

          it 'sets the existing deployment to DEPLOYED' do
            DeploymentCreate.create(app: app, droplet: next_droplet, user_audit_info: user_audit_info)

            expect(existing_deployment.reload.state).to eq(DeploymentModel::DEPLOYED_STATE)
          end
        end
      end

      context 'when a nil droplet is provided' do
        it 'raises a SetCurrentDropletError' do
          expect {
            DeploymentCreate.create(app: app, droplet: nil, user_audit_info: user_audit_info)
          }.to raise_error DeploymentCreate::SetCurrentDropletError, /Ensure the droplet exists and belongs to this app/
        end
      end
    end
  end
end
