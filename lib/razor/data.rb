# -*- encoding: utf-8 -*-
# The persistence layer of Razor; these classes are the primary interface
# to the Database. Usually, these would be called 'models', but Razor uses
# the term to mean something else.
#
# This is also used as a plugin, to allow us to add behaviour across all our
# models uniformly.
module Razor::Data
  module ClassMethods
    def friendly_name
      name.split('::').last.scan(/[A-Z][^A-Z]*/).join(' ').downcase
    end

    # Import data from a command as a new object in the database; this has
    # some semantics tied specifically to our desired behaviour around
    # idempotent operations:
    #
    # * if there is no match in the database, create a new object
    # * if there is a match in the database, then:
    #   - if it is exactly identical (eg: same fields present, and same
    #     values) then return the obect
    #   - else raise a conflict error
    #
    # Specifically, if you submit a command, it matches all supplied fields,
    # but you include an additional optional field on either side, the result
    # is failure.
    #
    # This implements the generic logic for retries.  It should only need to
    # be overridden when the child is going to augment the behaviour, and
    # augmentation should happen *after* the super method is invoked, eg:
    #
    #    def self.import(data, command)
    #      super.tap do |instance|
    #        instance.publish('do_something', command)
    #      end
    #    end
    def import(data, command = nil)
      command.nil? or command.is_a?(Razor::Data::Command) or
        raise _('internal error: got %{type} where Razor::Data::Command expected') %
          {type: command.class}

      create(data)
    end
  end

  module InstanceMethods
    extend Forwardable
    def_delegators 'self.class', 'friendly_name'
  end
end

# Configure global model plugins; these require a database connection, so
# much be established now that we have one.
#
# Infer, and extract, database constraints into the Ruby layer.  This makes
# `valid?` and `errors` on model objects work much more nicely -- by reading
# the database constraints and implementing them in Ruby automatically,
# rather than by lifting all validation into the application.
Sequel::Model.plugin :constraint_validations
Sequel::Model.plugin :auto_validations

# Add a `publish` method to all Sequel::Model objects, allowing them to be
# sent messages through the TorqueBox message queue system.
Sequel::Model.plugin Razor::Messaging::Sequel::Plugin

# Add additional helper methods to all our models
Sequel::Model.plugin Razor::Data

require_relative 'data/task'
require_relative 'data/repo'
require_relative 'data/policy'
require_relative 'data/tag'
require_relative 'data/node_log_entry'
require_relative 'data/node'
require_relative 'data/broker'
require_relative 'data/command'
