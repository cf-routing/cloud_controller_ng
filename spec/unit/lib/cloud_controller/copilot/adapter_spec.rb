require 'spec_helper'
require 'cloud_controller/copilot/adapter'

module VCAP::CloudController
  RSpec.describe Copilot::Adapter do
    subject(:adapter) { Copilot::Adapter }
    let(:copilot_client) do
      instance_spy(::Cloudfoundry::Copilot::Client)
    end
    let(:fake_logger) { instance_double(Steno::Logger, error: nil) }

    before do
      allow(CloudController::DependencyLocator.instance).to receive(:copilot_client).and_return(copilot_client)
      allow(Steno).to receive(:logger).and_return(fake_logger)
      TestConfig.override(copilot: { enabled: true })
    end

    describe '#create_route' do
      let(:route) { instance_double(Route, guid: 'some-route-guid', fqdn: 'some-fqdn', internal?: false, path: '') }

      it 'calls copilot_client.upsert_route' do
        adapter.create_route(route)
        expect(copilot_client).to have_received(:upsert_route).with(
          guid: 'some-route-guid',
          host: 'some-fqdn',
          path: '',
          internal: false,
        )
      end

      context 'when the route has a path' do
        let(:route) { instance_double(Route, guid: 'some-route-guid', fqdn: 'some-fqdn', internal?: false, path: '/some/path') }

        it 'includes path in upsert call' do
          adapter.create_route(route)
          expect(copilot_client).to have_received(:upsert_route).with(
            guid: 'some-route-guid',
            host: 'some-fqdn',
            path: '/some/path',
            internal: false,
          )
        end
      end

      context 'when the route is internal' do
        let(:route) { instance_double(Route, guid: 'some-route-guid', fqdn: 'some-fqdn', internal?: true, path: '/some/path') }

        it 'includes path in upsert call' do
          adapter.create_route(route)
          expect(route).to have_received(:internal?)
          expect(copilot_client).to have_received(:upsert_route).with(
            guid: 'some-route-guid',
            host: 'some-fqdn',
            path: '/some/path',
            internal: true,
          )
        end
      end

      context 'when copilot_client.upsert_route returns an error' do
        before do
          allow(copilot_client).to receive(:upsert_route).and_raise('uh oh')
        end

        it 'logs the error' do
          adapter.create_route(route)
          expect(fake_logger).to have_received(:error).with('failed communicating with copilot backend: uh oh')
        end
      end

      context 'when copilot is disabled' do
        before do
          TestConfig.override(copilot: { enabled: false })
        end

        it 'does not actually talk to copilot' do
          adapter.create_route(route)
          expect(copilot_client).not_to have_received(:upsert_route)
        end
      end
    end

    describe '#map_route' do
      let(:route) { Route.make }
      let(:app) { AppModel.make }
      let!(:process1) { ProcessModel.make(app: app) }
      let!(:process2) { ProcessModel.make(app: app) }
      let(:route_mapping) do
        RouteMappingModel.make(
                           app: app,
          route: route,
          process_type: 'web',
          weight: 5

        )
      end

      it 'calls copilot_client.map_route for each process associated with the route mapping' do
        adapter.map_route(route_mapping)
        expect(copilot_client).to have_received(:map_route).with(
          capi_process_guid: process1.guid,
          route_guid: route.guid,
          route_weight: 5
        )
        expect(copilot_client).to have_received(:map_route).with(
          capi_process_guid: process2.guid,
          route_guid: route.guid,
          route_weight: 5
        )
      end

      context 'when copilot_client.map_route returns an error' do
        before do
          allow(copilot_client).to receive(:map_route).and_raise('uh oh')
        end

        it 'logs the error' do
          adapter.map_route(route_mapping)
          expect(fake_logger).to have_received(:error).with('failed communicating with copilot backend: uh oh')
        end
      end

      context 'when copilot is disabled' do
        before do
          TestConfig.override(copilot: { enabled: false })
        end

        it 'does not actually talk to copilot' do
          adapter.map_route(route_mapping)
          expect(copilot_client).not_to have_received(:map_route)
        end
      end
    end

    describe '#unmap_route' do
      let(:route) { Route.make }
      let(:app) { AppModel.make }
      let!(:process1) { ProcessModel.make(app: app) }
      let!(:process2) { ProcessModel.make(app: app) }
      let(:route_mapping) do
        RouteMappingModel.make(
          app: app,
          route: route,
          process_type: 'web',
          weight: 5

        )
      end

      it 'calls copilot_client.unmap_route' do
        adapter.unmap_route(route_mapping)
        expect(copilot_client).to have_received(:unmap_route).with(
          capi_process_guid: process1.guid,
          route_guid: route.guid,
          route_weight: 5
        )
        expect(copilot_client).to have_received(:unmap_route).with(
          capi_process_guid: process2.guid,
          route_guid: route.guid,
          route_weight: 5
        )
      end

      context 'when copilot_client.unmap_route returns an error' do
        before do
          allow(copilot_client).to receive(:unmap_route).and_raise('uh oh')
        end

        it 'logs the error' do
          adapter.unmap_route(route_mapping)
          expect(fake_logger).to have_received(:error).with('failed communicating with copilot backend: uh oh')
        end
      end

      context 'when copilot is disabled' do
        before do
          TestConfig.override(copilot: { enabled: false })
        end

        it 'does not actually talk to copilot' do
          adapter.unmap_route(route_mapping)
          expect(copilot_client).not_to have_received(:unmap_route)
        end
      end
    end

    describe '#upsert_capi_diego_process_association' do
      let(:capi_process_guid) { 'some-capi-process-guid' }
      let(:diego_process_guid) { 'some-diego-process-guid' }
      let(:process) { instance_double(ProcessModel, guid: capi_process_guid) }

      before do
        allow(Diego::ProcessGuid).to receive(:from_process).with(process).and_return(diego_process_guid)
      end

      it 'calls copilot_client.upsert_capi_diego_process_association' do
        adapter.upsert_capi_diego_process_association(process)
        expect(copilot_client).to have_received(:upsert_capi_diego_process_association).with(
          capi_process_guid: capi_process_guid,
          diego_process_guids: [diego_process_guid]
        )
      end

      context 'when copilot_client.upsert_capi_diego_process_association returns an error' do
        before do
          allow(copilot_client).to receive(:upsert_capi_diego_process_association).and_raise('uh oh')
        end

        it 'logs the error' do
          adapter.upsert_capi_diego_process_association(process)
          expect(fake_logger).to have_received(:error).with('failed communicating with copilot backend: uh oh')
        end
      end

      context 'when copilot is disabled' do
        before do
          TestConfig.override(copilot: { enabled: false })
        end

        it 'does not actually talk to copilot' do
          adapter.upsert_capi_diego_process_association(process)
          expect(copilot_client).not_to have_received(:upsert_capi_diego_process_association)
        end
      end
    end

    describe '#delete_capi_diego_process_association' do
      let(:capi_process_guid) { 'some-capi-process-guid' }
      let(:process) { instance_double(ProcessModel, guid: capi_process_guid) }

      it 'calls copilot_client.delete_capi_diego_process_association' do
        adapter.delete_capi_diego_process_association(process)
        expect(copilot_client).to have_received(:delete_capi_diego_process_association).with(
          capi_process_guid: capi_process_guid
        )
      end

      context 'when copilot_client.delete_capi_diego_process_association returns an error' do
        before do
          allow(copilot_client).to receive(:delete_capi_diego_process_association).and_raise('uh oh')
        end

        it 'logs the error' do
          adapter.delete_capi_diego_process_association(process)
          expect(fake_logger).to have_received(:error).with('failed communicating with copilot backend: uh oh')
        end
      end

      context 'when copilot is disabled' do
        before do
          TestConfig.override(copilot: { enabled: false })
        end

        it 'does not actually talk to copilot' do
          adapter.delete_capi_diego_process_association(process)
          expect(copilot_client).not_to have_received(:delete_capi_diego_process_association)
        end
      end
    end

    describe '#bulk_sync' do
      it 'calls copilot_client.bulk_sync' do
        adapter.bulk_sync(routes: 'some-route',
                          route_mappings: 'some-route-mapping',
                          capi_diego_process_associations: 'kiwi',
                         )

        expect(copilot_client).to have_received(:bulk_sync).with(
          routes: 'some-route',
          route_mappings: 'some-route-mapping',
          capi_diego_process_associations: 'kiwi',
        )
      end

      context 'when copilot_client.bulk_sync returns an error' do
        before do
          allow(copilot_client).to receive(:bulk_sync).and_raise('uh oh')
        end

        it 'raises a CopilotUnavailable exception' do
          expect { adapter.bulk_sync(routes: 'some-route',
                                     route_mappings: 'some-route-mapping',
                                     capi_diego_process_associations: 'kiwi')
          }.to raise_error(Copilot::Adapter::CopilotUnavailable, 'uh oh')
        end
      end
    end
  end
end
