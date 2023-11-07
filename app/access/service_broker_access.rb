module VCAP::CloudController
  class ServiceBrokerAccess < BaseAccess
    def read?(object)
      return @ok_read if instance_variable_defined?(:@ok_read)

      @ok_read = (admin_user? || admin_read_only_user? || global_auditor? || object_is_visible_to_user?(object, context.user))
    end

    def read_for_update?(_object, _params=nil)
      admin_user?
    end

    def can_remove_related_object?(object, params=nil)
      read_for_update?(object, params)
    end

    def read_related_object_for_update?(object, params=nil)
      read_for_update?(object, params)
    end

    def index?(_object_class, _params=nil)
      admin_user? || admin_read_only_user? || has_read_scope? || global_auditor?
    end

    # These methods should be called first to determine if the user's token has the appropriate scope for the operation

    def read_with_token?(_)
      admin_user? || admin_read_only_user? || has_read_scope? || global_auditor?
    end

    def create_with_token?(_)
      admin_user? || has_write_scope?
    end

    def read_for_update_with_token?(_)
      admin_user? || has_write_scope?
    end

    def can_remove_related_object_with_token?(*)
      read_for_update_with_token?(*)
    end

    def read_related_object_for_update_with_token?(*)
      read_for_update_with_token?(*)
    end

    def update_with_token?(_)
      admin_user? || has_write_scope?
    end

    def delete_with_token?(_)
      admin_user? || has_write_scope?
    end

    def index_with_token?(_)
      admin_user? || admin_read_only_user? || has_read_scope? || global_auditor?
    end

    def create?(service_broker, _=nil)
      return true if admin_user?

      FeatureFlag.raise_unless_enabled!(:space_scoped_private_broker_creation)

      return if service_broker.nil?

      ServiceBrokerAccess.validate_object_access(context, service_broker)
    end

    def update?(service_broker, _=nil)
      return true if admin_user?

      return ServiceBrokerAccess.validate_object_access(context, service_broker) unless service_broker.nil?

      false
    end

    def delete?(service_broker, _=nil)
      return true if admin_user?

      return ServiceBrokerAccess.validate_object_access(context, service_broker) unless service_broker.nil?

      false
    end

    def self.validate_object_access(context, service_broker)
      if service_broker.space_scoped?
        service_broker.space.has_developer?(context.user)
      else
        false
      end
    end
  end
end
