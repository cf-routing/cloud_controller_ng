require 'spec_helper'

RSpec.describe 'migration to streamline changes to annotation_key_prefix', isolation: :truncation do
  let(:filename) { '20230822153000_streamline_annotation_key_prefix.rb' }
  let(:tmp_down_migrations_dir) { Dir.mktmpdir }
  let(:tmp_up_migrations_dir) { Dir.mktmpdir }
  let(:db) { Sequel::Model.db }
  let(:isolation_segment) { VCAP::CloudController::IsolationSegmentModel }
  let(:annotation) { VCAP::CloudController::IsolationSegmentAnnotationModel }
  let(:label) { VCAP::CloudController::IsolationSegmentLabelModel }

  before(:each) do
    Sequel.extension :migration
    # Find all migrations
    migration_files = Dir.glob("#{DBMigrator::SEQUEL_MIGRATIONS}/*.rb")
    # Calculate the index of our migration file we`d  like to test
    migration_index = migration_files.find_index { |file| file.end_with?(filename) }
    # Make a file list of the migration file we like to test plus all migrations after the one we want to test
    migration_files_after_test = migration_files[migration_index...]
    # Copy them to a temp directory
    FileUtils.cp(migration_files_after_test, tmp_down_migrations_dir)
    FileUtils.cp(File.join(DBMigrator::SEQUEL_MIGRATIONS, filename), tmp_up_migrations_dir)
    # Revert the given migration and everything newer so we are at the database version exactly before our migration we want to test.
    Sequel::Migrator.run(db, tmp_down_migrations_dir, target: 0, allow_missing_migration_files: true)
  end

  after do
    FileUtils.rm_rf(tmp_up_migrations_dir)
    FileUtils.rm_rf(tmp_down_migrations_dir)
  end

  describe 'annotation tables' do
    it 'converts all legacy key_prefixes to annotations with prefixes in the key_prefix column' do
      i1 = isolation_segment.create(name: 'bommel')
      a1 = annotation.create(resource_guid: i1.guid, key_name: 'mylegacyprefix/mykey', value: 'some_value')
      new_prefix, new_key_name = VCAP::CloudController::MetadataHelpers.extract_prefix(a1[:key].to_s)
      expect { Sequel::Migrator.run(db, tmp_up_migrations_dir, allow_missing_migration_files: true) }.not_to raise_error
      b1 = db[:isolation_segment_annotations].first(resource_guid: i1.guid)
      expect(b1[:guid]).to eq a1[:guid]
      expect(b1[:created_at]).to eq a1[:created_at]
      expect(b1[:updated_at]).to_not eq a1[:updated_at]
      expect(b1[:resource_guid]).to eq a1[:resource_guid]
      expect(b1[:key_prefix]).to_not eq a1[:key_prefix]
      expect(b1[:key]).to_not eq a1[:key]
      expect(b1[:key_prefix]).to eq new_prefix
      expect(b1[:key]).to eq new_key_name
    end

    it 'doesnt touch any values that have no legacy key_prefix in its key field' do
      i1 = isolation_segment.create(name: 'bommel')
      a1 = annotation.create(resource_guid: i1.guid, key_prefix: 'myprefix', key: 'mykey', value: 'some_value')
      a2 = annotation.create(resource_guid: i1.guid, key: 'mykey2', value: 'some_value2')
      b1 = db[:isolation_segment_annotations].first(key: a1[:key])
      b2 = db[:isolation_segment_annotations].first(key: a2[:key])
      expect { Sequel::Migrator.run(db, tmp_up_migrations_dir, allow_missing_migration_files: true) }.not_to raise_error
      c1 = db[:isolation_segment_annotations].first(key: a1[:key])
      c2 = db[:isolation_segment_annotations].first(key: a2[:key])
      expect(b1.values).to eq(c1.values)
      expect(b2.values).to eq(c2.values)
    end
  end
end
