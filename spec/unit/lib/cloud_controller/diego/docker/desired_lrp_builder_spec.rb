require 'spec_helper'

module VCAP::CloudController
  module Diego
    module Docker
      RSpec.describe DesiredLrpBuilder do
        subject(:builder) { DesiredLrpBuilder.new(config, opts) }
        let(:opts) do
          {
            ports: ports,
            docker_image: 'user/repo:tag',
            execution_metadata: execution_metadata,
            start_command: 'dd if=/dev/random of=/dev/null',
          }
        end
        let(:config) do
          Config.new({
            diego: {
              lifecycle_bundles: {
                docker: 'http://docker.example.com/path/to/lifecycle.tgz'
              },
              temporary_oci_buildpack_mode: temporary_oci_buildpack_mode,
            }
          })
        end
        let(:ports) { [] }
        let(:execution_metadata) { '{}' }
        let(:temporary_oci_buildpack_mode) { '' }

        describe '#root_fs' do
          it 'uses the DockerURIConverter' do
            converter = instance_double(DockerURIConverter, convert: 'foobar')
            allow(DockerURIConverter).to receive(:new).and_return(converter)

            expect(builder.root_fs).to eq('foobar')
            expect(converter).to have_received(:convert).with('user/repo:tag')
          end
        end

        describe '#cached_dependencies' do
          before do
            allow(LifecycleBundleUriGenerator).to receive(:uri).and_return('foo://bar.baz')
          end

          it 'returns an array of CachedDependency objects' do
            expect(builder.cached_dependencies).to eq([
              ::Diego::Bbs::Models::CachedDependency.new(
                from: 'foo://bar.baz',
                to: '/tmp/lifecycle',
                cache_key: 'docker-lifecycle',
              )
            ])
            expect(LifecycleBundleUriGenerator).to have_received(:uri).with('http://docker.example.com/path/to/lifecycle.tgz')
          end

          context 'when temporary_oci_buildpack_mode is set to oci-phase-1' do
            let(:temporary_oci_buildpack_mode) { 'oci-phase-1' }

            it 'returns nil' do
              expect(builder.cached_dependencies).to be_nil
            end
          end
        end

        describe '#image_layers' do
          before do
            allow(LifecycleBundleUriGenerator).to receive(:uri).and_return('foo://bar.baz')
          end

          it 'returns nil' do
            expect(builder.image_layers).to be_nil
          end

          context 'when temporary_oci_buildpack_mode is set to oci-phase-1' do
            let(:temporary_oci_buildpack_mode) { 'oci-phase-1' }

            it 'creates a image layer for each cached dependency' do
              expect(builder.image_layers).to include(
                ::Diego::Bbs::Models::ImageLayer.new(
                  name: 'docker-lifecycle',
                  url: 'foo://bar.baz',
                  destination_path: '/tmp/lifecycle',
                  layer_type: ::Diego::Bbs::Models::ImageLayer::Type::SHARED,
                  media_type: ::Diego::Bbs::Models::ImageLayer::MediaType::TGZ,
                )
              )
            end
          end
        end

        describe '#setup' do
          it 'returns nil' do
            expect(builder.setup).to be_nil
          end
        end

        describe '#global_environment_variables' do
          it 'returns an empty list' do
            expect(builder.global_environment_variables).to be_empty
          end
        end

        describe '#ports' do
          context 'when ports is an empty array' do
            let(:ports) { [] }
            let(:execution_metadata) {
              {
                ports: [
                  { 'port' => '1', 'protocol' => 'udp' },
                  { 'port' => '2', 'protocol' => 'udp' },
                  { 'port' => '3', 'protocol' => 'tcp' },
                  { 'port' => '4', 'protocol' => 'tcp' },
                ]
              }.to_json
            }

            it 'sets PORT to the first TCP port entry from execution_metadata' do
              expect(builder.ports).to eq([3, 4])
            end

            context 'when the ports array does not contain any TCP entries' do
              let(:execution_metadata) {
                { ports: [{ 'port' => '1', 'protocol' => 'udp' }] }.to_json
              }

              it 'raises an error' do
                expect {
                  builder.ports
                }.to raise_error(CloudController::Errors::ApiError, /No tcp ports found in image metadata/)
              end
            end

            context 'when the execution_metadata has an empty array of ports' do
              let(:execution_metadata) {
                { ports: [] }.to_json
              }

              it 'returns an array containing only the default' do
                expect(builder.ports).to eq([DEFAULT_APP_PORT])
              end
            end

            context 'when the execution_metadata does not contain ports' do
              let(:execution_metadata) {
                {}.to_json
              }

              it 'returns an array containing only the default' do
                expect(builder.ports).to eq([DEFAULT_APP_PORT])
              end
            end
          end
        end

        describe '#action_user' do
          it 'returns "root"' do
            expect(builder.action_user).to eq('root')
          end

          context 'when the execution metadata has a specified user' do
            let(:execution_metadata) { { user: 'foobar' }.to_json }

            it 'uses the user from the execution metadata' do
              expect(builder.action_user).to eq('foobar')
            end
          end
        end

        describe '#start_command' do
          it 'returns the passed in start command' do
            expect(builder.start_command).to eq('dd if=/dev/random of=/dev/null')
          end
        end

        describe '#port_environment_variables' do
          let(:ports) { [11, 22, 33] }

          it 'returns the array of environment variables' do
            expect(builder.port_environment_variables).to match_array([
              ::Diego::Bbs::Models::EnvironmentVariable.new(name: 'PORT', value: '11'),
            ])
          end
        end

        describe '#platform_options' do
          context 'when the app has a credhub url' do
            let(:expected_credhub_url) do
              "{\"credhub-uri\":\"#{TestConfig.config_instance.get(:credhub_api, :internal_url)}\"}"
            end

            before do
              TestConfig.override(credhub_api: { internal_url: 'http:credhub.capi.land:8844' })
            end

            context 'when the interpolation of service bindings is enabled' do
              before do
                TestConfig.override(credential_references: { interpolate_service_bindings: true })
              end

              it 'includes the credhub uri as part of the VCAP_PLATFORM_OPTIONS variable' do
                expect(builder.platform_options).to match_array([
                  ::Diego::Bbs::Models::EnvironmentVariable.new(name: 'VCAP_PLATFORM_OPTIONS', value: expected_credhub_url)
                ])
              end
            end

            context 'when the interpolation of service bindings is disabled' do
              before do
                TestConfig.override(credential_references: { interpolate_service_bindings: false })
              end

              it 'does not include the VCAP_PLATFORM_OPTIONS' do
                expect(builder.platform_options).to eq([])
              end
            end
          end

          context 'when the app does not have a credhub url' do
            before do
              TestConfig.override(credhub_api: nil)
            end

            it 'does not include the VCAP_PLATFORM_OPTIONS' do
              expect(builder.platform_options).to eq([])
            end
          end
        end
      end
    end
  end
end
