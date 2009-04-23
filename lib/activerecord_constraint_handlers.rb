
# Copyright (c) 2009 Perry Smith

# This file is part of activerecord_constraints.

# activerecord_constraints is free software: you can redistribute it
# and/or modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.

# activerecord_constraints is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with activerecord_constraints.  If not, see
# <http://www.gnu.org/licenses/>.

module ActiveRecord
  module ConnectionAdapters
    # Constraint Handlers is a module to catch and handle the
    # exceptions produced by failed constraints.  The current
    # implementation ties only to the create_or_update path which is
    # after validations are done.  This allows the database to have
    # constraints but preserve the API and semantics of Model.save and
    # Model.save!
    #
    # The three hooks made available is a hook when the connection is
    # first created.  At that point, the database adapter specific
    # module is loaded into the base.  It does not work to rummage
    # around in the database during this hook.  This hook is done via
    # ConstraintConnectionHook.
    #
    # The second hook is done by the adapter specific constrait
    # handler.  The call to create_or_update is captured.  If an
    # exception is thrown, then the adapter specific
    # handle_create_or_update_exception is called.
    #
    # The third hook is also in the create_or_update.  Before the cal
    # to create_or_update_witout_constraints is done, the class
    # specific pre_fetch method is called.  Again, this method is
    # included into the class of the model at the time the connection
    # is created.
    #
    module ConstraintHandlers

      # A PostgreSQL specific implementation.
      module Postgresql
    
        NOT_NULL_REGEXP = Regexp.new("PGError: +ERROR: +null value in column \"([^\"]*)\" violates not-null constraint")
        UNIQUE_REGEXP = Regexp.new("PGError: +ERROR: +duplicate key violates unique constraint \"([^\"]+)\"")
        FOREIGN_REGEXP = Regexp.new("PGError: +ERROR: +insert or update on table \"([^\"]+)\" violates " +
                                "foreign key constraint \"([^\"]+)\"")
        #
        # We need class methods and class instance variables to hold
        # the data.  We want them in the class so that the work is
        # done only once for the life of the application.  In the
        # PostgreSQL case, we leverage off of ActiveRecord::Base by
        # creating three nested models so they are hidden
        # syntactically that use the model as their base class so that
        # they use the same connection as the model itself.  This
        # allows other models to use other connections and the data is
        # kept separate.
        module ClassMethods
          @pg_class = nil
          @pg_constraints = nil
          @pg_constraint_hash = nil
          @pg_attributes = nil
          @pg_attribute_hash = nil
          
          # Create the constant for the PgClass nested model.
          def pg_class_constant
            "#{self}::PgClass".constantize
          end

          # Create the constant for the PgConstraint nested model.
          def pg_constraint_constant
            "#{self}::PgConstraint".constantize
          end
          
          # Create the constant for the PgAttribute nested model.
          def pg_attribute_constant
            "#{self}::PgAttribute".constantize
          end

          # Turns out, we don't really use this...
          def pg_class
            @pg_class ||= pg_class_constant.find_by_relname(table_name)
          end
          
          # Find the constraints for this model / table
          def pg_constraints
            if @pg_constraints.nil?
              @pg_constraints = pg_constraint_constant.find(:all,
                                                            :joins => :conrel,
                                                            :conditions => { :pg_class => { :relname => table_name }})
              @pg_constraint_hash = Hash.new
              @pg_constraints.each { |c|
                ActiveRecord::Base.logger.debug("Adding '#{c.conname}' to constraint_hash")
                @pg_constraint_hash[c.conname] = c
              }
            end
            @pg_constraints
          end
          
          # Accessor for the constraint hash
          def pg_constraint_hash
            @pg_constraint_hash
          end
          
          # Find the attributes for this model
          def pg_attributes
            if @pg_attributes.nil?
              @pg_attributes = pg_attribute_constant.find(:all,
                                                          :joins => :attrel,
                                                          :conditions => { :pg_class => { :relname => table_name }})
              @pg_attribute_hash = Hash.new
              @pg_attributes.each { |a| @pg_attribute_hash[a.attnum] = a }
            end
            @pg_attributes
          end
          
          # Accessor for the attribute hash
          def pg_attribute_hash
            @pg_attribute_hash
          end

          # At the time of the first call, we create the models needed
          # for the code above as a nested subclass of the model using
          # the model as the base.
          def create_subclasses
            self.class_eval <<-EOF
              class PgClass < #{self}
                set_table_name "pg_class"
                set_primary_key "oid"
              end

              class PgAttribute < #{self}
                set_table_name "pg_attribute"
                set_primary_key "oid"
                belongs_to :attrel, :class_name => "PgClass", :foreign_key => :attrelid
              end

              class PgConstraint < #{self}
                set_table_name "pg_constraint"
                set_primary_key "oid"
                belongs_to :conrel, :class_name => "PgClass", :foreign_key => :conrelid
              end
            EOF
          end

          # We can not rummage around in the database after an error has
          # occurred or we will get back more errors that an error has
          # already occurred and further queries will be ignored.  So, we
          # pre-fetch the system tables that we need and save them in our
          # pockets.
          def pre_fetch
            ActiveRecord::Base.logger.debug("pre_fetch #{self} #{table_name} #{@pg_class.nil?}")
            if @pg_class.nil?
              create_subclasses
              pg_class
              pg_constraints
              pg_attributes
            end
          end
          
          # Converts the constraint name into a list of column names.
          def constraint_to_columns(constraint)
            ActiveRecord::Base.logger.debug("constraint_to_columns: '#{constraint}' (#{constraint.class})")

            # Should never hit this now... added during debugging.
            unless pg_constraint_hash.has_key?(constraint)
              ActiveRecord::Base.logger.debug("constraint_to_columns: constraint not found")
              return
            end
            # pg_constraint_hash is a hash from the contraint name to
            # the constraint.  The conkey is a string of the form:
            # +{2,3,4}+ (with the curly braces).  The numbers are
            # column indexes which we pull out from pg_attribute and
            # convert to a name.  Note that the PostgreSQL tables are
            # singular in name: pg_constraint and pg_attribute
            k = pg_constraint_hash[constraint].conkey
            k[1 ... (k.length - 1)].
              split(',').
              map{ |s| pg_attribute_hash[s.to_i].attname }
          end
        end

        # When the include of
        # ActiveRecord::ConnectionAdapters::ConstraintConnectionHook
        # happens this hook is called with ActiveRecord::Base as the
        # base.  We extend the base with the class methods so they are
        # class methods and the instance variables are then class
        # instance variables.
        def self.included(base)
          base.extend(ClassMethods)
        end

        # Called with exception when create_or_update throws an exception
        def handle_create_or_update_exception(e)
          raise e until e.is_a? ActiveRecord::StatementInvalid
          logger.debug("trace_report create_or_update error is '#{e.message}'")
          if md = NOT_NULL_REGEXP.match(e.message)
            errors.add(md[1].to_sym, "can't be blank")
          elsif md = UNIQUE_REGEXP.match(e.message)
            constraint = md[1]
            ffoo(constraint, "has already been taken")
          elsif md = FOREIGN_REGEXP.match(e.message)
            table = md[1]
            constraint = md[2]
            ffoo(constraint, "is invalid")
          else
            logger.debug("Nothing matched")
          end
          false
        end
    
        private

        # Could never figure out what to call this.  If the model
        # responds to the constraint name (i.e. there is a method by
        # the same name in the model), then it is call (currently with
        # no arguments).  If that is not done then the message is
        # added to the errors array for the column.
        def ffoo(constraint, message)
          ActiveRecord::Base.logger.debug("constraint: '#{constraint.inspect}', message: #{message}")
          c = constraint.to_sym
          # define a method in the model with the same name as the
          # constraint and it will be called so it can do whatever it
          # wants to.
          if self.respond_to? c
            self.send c
          else
            columns = self.class.constraint_to_columns(constraint)
            ActiveRecord::Base.logger.debug("columns are: #{columns.inspect}")
            columns.each { |name| errors.add(name, message) }
          end
        end
      end
    end

    # This module is included in ActiveRecord::Base.  The example
    # provided is for PostgreSQL.  During the connect, the adapter
    # specific connection routine is called.  The name of that routine
    # is the the adapter type with +_connection+ appened.
    # e.g. +postgresql_connection+
    module ConstraintConnectionHook
      def self.included(base)
        base.class_eval {
          class << self
            # An example for the postgresql adapter.  Other adapters
            # need only add to this list with the proper name.
            def postgresql_connection_with_constraints(config)
              ActiveRecord::Base.logger.debug("IN: ConstraintConnectionHook::postgresql_connection_with_constraints #{self}")
              # Pass the call up the chain
              v = postgresql_connection_without_constraints(config)

              # After we return, add in Postgres' constraint handlers
              # into "self".  Usually this will be ActiveRecord::Base
              # but I think if Model.establish_connection is called,
              # then self will be Model.
              include ConstraintHandlers::Postgresql

              # Return the original result.
              v
            end
            alias_method_chain :postgresql_connection, :constraints
          end
        }
      end
    end
  end
  
  class Base
    # Postgres needs a hook so it can load some tables when the
    # connection is first opened.  Other DB's may need a similar hook
    include ActiveRecord::ConnectionAdapters::ConstraintConnectionHook

    # Insert into the create_or_update call chain
    def create_or_update_with_constraints
      begin
        self.class.pre_fetch if self.class.respond_to? :pre_fetch
        create_or_update_without_constraints
      rescue => e
        if respond_to?(:handle_create_or_update_exception)
          handle_create_or_update_exception(e)
        else
          raise e
        end
      end
    end
    alias_method_chain :create_or_update, :constraints
  end
end
