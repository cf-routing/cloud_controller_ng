require 'spec_helper'
require 'rspec_api_documentation/dsl'

RSpec.resource 'Buildpacks', type: %i[api legacy_api] do
  let(:admin_auth_header) { admin_headers['HTTP_AUTHORIZATION'] }
  let!(:buildpacks) { (1..3).map { |i| VCAP::CloudController::Buildpack.make(name: "name_#{i}", position: i) } }
  let(:guid) { buildpacks.first.guid }

  authenticated_request

  shared_context 'guid_parameter' do
    parameter :guid, 'The guid of the Buildpack'
  end

  describe 'Standard endpoints' do
    shared_context 'updatable_fields' do |opts|
      field :name,
            'The name of the buildpack. To be used by app buildpack field. (only alphanumeric characters)',
            required: opts[:required],
            example_values: ['Golang_buildpack']

      field :stack, 'The name of the stack to associate this buildpack with', example_values: ['cflinuxfs4']
      field :position, 'The order in which the buildpacks are checked during buildpack auto-detection.'
      field :enabled, 'Whether or not the buildpack will be used for staging', default: true
      field :locked, 'Whether or not the buildpack is locked to prevent updates', default: false
      field :filename, 'The name of the uploaded buildpack file'
    end

    standard_model_list(:buildpack, VCAP::CloudController::BuildpacksController)
    standard_model_get(:buildpack)
    standard_model_delete(:buildpack)

    post '/v2/buildpacks' do
      include_context 'updatable_fields', required: true

      example 'Creates an admin Buildpack' do
        client.post '/v2/buildpacks', fields_json(stack: 'cflinuxfs4'), headers
        expect(status).to eq 201
        standard_entity_response parsed_response, :buildpack, expected_values: { name: 'Golang_buildpack' }
      end
    end

    put '/v2/buildpacks/:guid' do
      include_context 'updatable_fields', required: false
      include_context 'guid_parameter'

      example 'Change the position of a Buildpack' do
        explanation <<-DOC
          Buildpacks are maintained in an ordered list.  If the target position is already occupied,
          the entries will be shifted down the list to make room.  If the target position is beyond
          the end of the current list, the buildpack will be positioned at the end of the list.
        DOC

        expect do
          client.put "/v2/buildpacks/#{guid}", Oj.dump({ position: 3 }), headers
          expect(status).to eq(201)
          standard_entity_response parsed_response, :buildpack, expected_values: { position: 3 }
        end.to change {
          VCAP::CloudController::Buildpack.order(:position).map { |bp| [bp.name, bp.position] }
        }.from(
          [['name_1', 1], ['name_2', 2], ['name_3', 3]]
        ).to(
          [['name_2', 1], ['name_3', 2], ['name_1', 3]]
        )
      end

      example 'Enable or disable a Buildpack' do
        expect do
          client.put "/v2/buildpacks/#{guid}", Oj.dump({ enabled: false }), headers
          expect(status).to eq 201
          standard_entity_response parsed_response, :buildpack, expected_values: { enabled: false }
        end.to change {
          VCAP::CloudController::Buildpack.find(guid:).enabled
        }.from(true).to(false)

        expect do
          client.put "/v2/buildpacks/#{guid}", Oj.dump({ enabled: true }), headers
          expect(status).to eq 201
          standard_entity_response parsed_response, :buildpack, expected_values: { enabled: true }
        end.to change {
          VCAP::CloudController::Buildpack.find(guid:).enabled
        }.from(false).to(true)
      end

      example 'Lock or unlock a Buildpack' do
        expect do
          client.put "/v2/buildpacks/#{guid}", Oj.dump({ locked: true }), headers
          expect(status).to eq 201
          standard_entity_response parsed_response, :buildpack, expected_values: { locked: true }
        end.to change {
          VCAP::CloudController::Buildpack.find(guid:).locked
        }.from(false).to(true)

        expect do
          client.put "/v2/buildpacks/#{guid}", Oj.dump({ locked: false }), headers
          expect(status).to eq 201
          standard_entity_response parsed_response, :buildpack, expected_values: { locked: false }
        end.to change {
          VCAP::CloudController::Buildpack.find(guid:).locked
        }.from(true).to(false)
      end
    end
  end

  put '/v2/buildpacks/:guid/bits' do
    include_context 'guid_parameter'

    before do
      TestConfig.override(directories: { tmpdir: File.dirname(valid_zip.path) })
    end

    let(:tmpdir) { Dir.mktmpdir }
    let(:user) { make_user }
    let(:filename) { 'file.zip' }

    after { FileUtils.rm_rf(tmpdir) }

    let(:valid_zip) do
      zip_name = File.join(tmpdir, filename)
      TestZip.create(zip_name, 1, 1024)
      File.new(zip_name)
    end

    example 'Upload the bits for an admin Buildpack' do
      explanation 'PUT not shown because it involves putting a large zip file. Right now only zipped admin buildpacks are accepted'

      no_doc do
        client.put "/v2/buildpacks/#{guid}/bits", { buildpack_name: filename, buildpack_path: valid_zip.path }, headers
      end

      expect(status).to eq(201)
      standard_entity_response parsed_response, :buildpack
    end
  end
end
