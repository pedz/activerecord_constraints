
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

require 'active_record'

# PostgresConstraints
module ActiveRecord
  module ConnectionAdapters
    # Module that will be included in other modules to reduce
    # duplication.  It implements the conversion from a list of
    # options that specify a constraint to the SQL statement that
    # implements the constraint.
    #
    # A constraint is broken into parts:
    # 1. An optional constraint name
    # 2. One of:
    #    1. unique constraint
    #    2. foreign key constraint
    #    3. check constraint
    # 3. An optional deferrable clause
    # 4. An optional initially clause
    #
    # There are two places to declare a constraint.  PostgreSQL calls
    # these column constraints and table constraints.  A column
    # constraint can have a few things that a table constraint can not
    # such as not null or null constraints.  Those are handled
    # elsewhere in Active Record although they might get moved in to
    # here since this code allows those constraints to be named which
    # may have some advantages.
    #
    # The SQL syntax for the column and table constraints are very
    # similar so the routines handle both with a flag that specifies
    # if the routine is being called to create a column constraint or
    # a table constraint.
    #
    # The name of a constraint can be specified with either a
    # <tt>:name => "constraint_name"</tt> option or, for example,
    # <tt>:unique => "constraint_name"</tt>.  The main advantage to
    # this is to allow a multiple named constraints in the same column
    # specification.
    #
    module Constraints
      # Generic constraint code
      module Abstract
      end

      # Generallized SQL constraint code.
      module Sql
        # Utility routine to return true if the options has the
        # indicated constraint type.
        def has_constraint(options, constraint_type)
          options.has_key?(constraint_type) &&
            options[constraint_type] != false
        end
        
        # Utility routine to produce the named part of a named
        # constraint: passed the full set of options along with the type
        # of the constraint, e.g. :unique.
        def name_str(options, constraint_type)
          if options[constraint_type] == true
            n = options[:name]
          else
            n = options[option_name]
          end
          n.blank? ? "" : " CONSTRAINT #{n}"
        end
        
        # Utility routine to produce the additional string needed in a
        # table constraint that is not needed in a column constraint.
        # Passed the column name (which may be an array of names), the
        # column_constraint flag, and the an optional prefix string.
        def table_str(column_name, column_constraint, prefix_string = "")
          # No space is needed around the parens but it looks nicer with
          # spaces.
          column_constraint ? "" :
            " #{prefix_string}( #{column_to_str(column_name)} )"
        end
        
        # Creates the DEFERRABLE string
        def deferrable_str(options)
          if options.has_key?(:deferrable)
            ((options[:deferrable] == false) ? " NOT" : "") +
              " DEFERRABLE"
          else
            ""
          end
        end
        
        # Creates the INITIALLY string
        def initially_str(options)
          if options.has_key?(:initially)
            ref_str << " INITIALLY #{to_db_string(options[:initially])}"
          else
            ""
          end
        end
        
        # Creates the suffix options deferrable and initially
        def suffix_str(options)
          deferrable_str(options) + initially_str(options)
        end
        
        # Utility routine to produce the string for the UNIQUE
        # constraint.  For a column constraint, the syntax may be
        # either <tt>:unique => "constraint_name"</tt> or it can be
        # <tt>:unique => true</tt> followed by an optional
        # <tt>:name => "constraint_name"</tt>.  If constraint_name is
        # a symbol, it is simply converted to a string.
        def unique_str(column_name, options, column_constraint)
          ActiveRecord::Base.logger.debug("IN: Constraints#unique_str")
          return "" unless has_constraint(options, :unique)
          constraint_name = name_str(options, :unique)
          column_spec = table_str(column_name, column_constraint)
          suffix_spec = suffix_str(options)
          constraint_name + " UNIQUE" + column_spec + suffix_spec
        end
        
        # Utility routine to produce the string for a CHECK constraint.
        # The alternatives here are: (the first two are named, the last
        # two are unnamed)
        # 1) :check => "constraint_name", :expr => "check expression"
        # 2) :check => true, :name => "constraint_name",
        #        :expr => "check expression"
        # 3) :check => true, :expr => "check expression"
        # 4) :check => "check expression"
        def check_str(column_name, options, column_constraint)
          ActiveRecord::Base.logger.debug("IN: Constraints#check_str")
          return "" unless has_constraint(options, :check)
          
          # Have to dance a little bit here...
          if options[:check] == true
            expr = options[:expr]
            name = options[:name]
          elsif options.has_key?(:expr)
            expr = options[:expr]
            name = options[:check]
          else
            expr = options[:check]
            name = nil
          end
          constraint_name = name_str({ :name => name, :check => true }, :check)
          # column string is not part of CHECK constraints
          suffix_spec = suffix_str(options)
          constraint_name + " CHECK ( #{expr} )" + suffix_spec
        end
        
        # Simple function to convert symbols and strings to what SQL
        # wants.
        # +:no_action+:: goes to "NO ACTION"
        # +:cascade+::   goes to "CASCADE"
        # etc
        def to_db_string(f)
          f.to_s.upcase.gsub(/_/, ' ')
        end
        
        # Utility routine to produce the string for a FOREIGN KEY
        # constraint.  Like a UNIQUE constraint, the optional name of
        # the constraint can either the string assigned to the
        # :reference option or a separate :name option.
        def reference_str(column_name, options, column_constraint)
          ActiveRecord::Base.logger.debug("IN: Constraints#reference_str")
          return "" unless has_constraint(options, :reference)
          constraint_name = name_str(options, :reference)
          column_spec = table_str(column_name, column_constraint,
                                  "FOREIGN KEY ")
          local_options = { }
          if md = /(.*)_id$/.match(column_name.to_s)
            local_options[:table_name] = md[1].pluralize
            local_options[:foreign_key] = "id"
          end
          local_options.merge!(options)
          ref_column_str = column_to_str(local_options[:foreign_key])
          ref_str = " REFERENCES #{local_options[:table_name]} (#{ref_column_str})"
          
          if local_options.has_key?(:delete)
            ref_str << " ON DELETE #{to_db_string(local_options[:delete])}"
          end
          
          if local_options.has_key?(:update)
            ref_str << " ON UPDATE #{to_db_string(local_options[:update])}"
          end
          
          constraint_name + column_spec + ref_str + suffix_str(options)
        end
        
        # Utility routine to return the column or the array of columns
        # as a string.
        def column_to_str(column)
          ActiveRecord::Base.logger.debug("IN: Constraints#column_to_str")
          if column.is_a? Array
            column.map { |c| "\"#{c.to_s}\""}.join(", ")
          else
            "\"#{column.to_s}\""
          end
        end
      end

      # Postgresql specific constraint code
      module Postgresql
        include Sql
      end
    end

    module SchemaStatements
      # When base.add_column_options_with_constraints! is called by
      # ColumnDefinition#add_column_options_with_constraints! it ends
      # up calling
      # SchemaStatements#add_column_options_with_constraints!.  We
      # capture that call as well so that we can append the constraint
      # clauses to the sql statement.
      def add_column_options_with_constraints!(sql, options)
        ActiveRecord::Base.logger.debug("IN: SchemaStatements#add_column_options_with_constraints!")

        # TODO:
        # This needs to dig out the database type of the connection
        # and then extend the database specific set of Constraints
        extend Constraints::Postgresql

        add_column_options_without_constraints!(sql, options)
        column_name = options[:column].name
        sql << unique_str(column_name, options, true)
        sql << reference_str(column_name, options, true)
        sql << check_str(column_name, options, true)
      end
      alias_method_chain :add_column_options!, :constraints
    end
    
    class ColumnDefinition
      # Will contain all the options used on a column definition
      def options
        ActiveRecord::Base.logger.debug("IN: ColumnDefinition#options")
        @options
      end
      
      # Called from TableDefinition#column_with_constraints so we
      # remember the options for each column being defined.
      def options=(arg)
        ActiveRecord::Base.logger.debug("IN: ColumnDefinition#options=")
        @options = arg
      end
      
      # ColumnDefinition@add_column_options! is called which calls
      # base.add_column_options! by to_sql of ColumnDefinition.  We
      # capture this call so that we can merge in the options we are
      # interested in (namely, all of the original options used in to
      # create the column
      def add_column_options_with_constraints!(sql, options)
        ActiveRecord::Base.logger.debug("IN: ColumnDefinition#add_column_options_with_constraints!")
        add_column_options_without_constraints!(sql, options.merge(@options))
      end
      alias_method_chain :add_column_options!, :constraints
    end
    
    class TableDefinition
      # TODO:
      # This include needs to be an extend executed perhaps when the
      # connection is created.
      include Constraints::Postgresql
      
      # As the table is being defined, we capture the call to column.
      # column (now called column_with_constraints returns self which
      # is a TableDefinition. TableDefinition#[] returns the column
      # for the name passed.  We add an @options attribute for later
      # use (see ColumnDefinition#options=).
      def column_with_constraints(name, type, options = { })
        ActiveRecord::Base.logger.debug("IN: TableDefinition#column_with_constraints for #{name}")
        ret = column_without_constraints(name, type, options)
        ret[name].options = options
        ret
      end
      alias_method_chain :column, :constraints
      
      # to_sql is called to transform the table definition into an sql
      # statement.  We insert ourselves into that so that we can
      # append the extra string needed for the constraints added by
      # the +unique+ and +references+ table definition methods.
      def to_sql_with_constraints
        ActiveRecord::Base.logger.debug("IN: TableDefinition#to_sql_with_constraints")
        to_sql_without_constraints + extra_str
      end
      alias_method_chain :to_sql, :constraints
      
      # _fk_ stands for <em>foreign key</em>.  This is more like a macro that
      # defines a column that is a foreign key.
      # This:
      #
      #   create_table :foos do |t|
      #     # Make a foreign key to the id column in the bars table
      #     t.fk :bar_id
      #   end
      #
      # is the equivalent of this:
      #
      #   create_table :foos do |t|
      #     # Make a foreign key to the id column in the bars table
      #     t.integer :bar_id, :null => false, :reference => true,
      #         :delete => :cascade, :deferrable => true
      #   end
      #
      # which is the same as this:
      #
      #   create_table :foos do |t|
      #     # Make a foreign key to the id column in the bars table
      #     t.integer :bar_id, :null => false, :reference => true,
      #         :delete => :cascade, :deferrable => true,
      #         :table_name => :bars, :foreign_key => :id
      #   end
      #
      # These defaults were chosen because despite common practice,
      # nulls in databases should be avoided, the constraint needs to
      # be deferrable to get fixtures to work, and cascade on delete
      # keeps things simple.
      #
      # But this should work also:
      #
      #   create_table :foos do |t|
      #     # Make a foreign key to the id column in the bars table
      #     t.fk :bar_id, :toad_id, :banana_id, :delete => :no_action
      #   end
      #
      def fk(*names)
        options = {
          :null => false,
          :reference => true,
          :delete => :cascade,
          :deferrable => true
        }.merge(names.last.is_a?(Hash) ? names.pop : { })
        self.integer(names, options)
      end
      
      # Add a "unique" method to TableDefinition.  e.g.
      #   create_table :users do |t|
      #     t.string  :name,  :null    => false
      #     t.boolean :admin, :default => false
      #     t.timestamps
      #     t.unique :name
      #   end
      #
      # A list of UNIQUE can be specified by simply listing the
      # columns:
      #   t.unique :name1, :name2, :name3
      # This produces separate constraints. To produce a specification
      # where a set of columns needs to be unique, put the column
      # names inside an array.  Both can be done at the same time:
      #   t.unique [ :name1, :name2 ], :name3
      # produces where the tulple (name1, name2) must be unique and
      # the name3 column must also be unique.
      def unique(*args)
        ActiveRecord::Base.logger.debug("IN: TableDefinition#unique")
        options = { :unique => true }.merge(args.last.is_a?(Hash) ? args.pop : { })
        args.each { |arg| extra_str << ", #{unique_str(arg, options, false)}" }
      end
      
      # Pass a column and options (which may be empty).  The column
      # name of foo_id, by default, creates a reference to table foos,
      # column id.  :table_name may be passed in options to specify
      # the foreign table name.  :foreign_key may be passed to specify the
      # foreign column.
      # Both the passed in column (first argument) as well as thee
      # :foreign_key option may be an array.
      # :delete option may be passed in with the appropriate value
      # such as :restrict, :cascade, etc.
      def reference(column, options = { })
        ActiveRecord::Base.logger.debug("IN: TableDefinition#reference")
        extra_str << ", #{reference_str(column, options, false)}"
      end
      
      # Specify a check table constrant. In the simple case, this can
      # be done as:
      #   create_table :users do |t|
      #     t.string  :name,     :null    => false
      #     t.string  :password, :null    => false
      #     t.boolean :admin,    :default => false
      #     t.timestamps
      #     t.check "password_check(password)"
      #   end
      #
      # Alternate forms for the above are:
      # 1. To give the constraint a name of "password_constraint":
      #      t.check "password_check(password)", :name => "password_constraint"
      # 2. Flip the above around:
      #      t.check "password_constraint", expr => "password_check(password)"
      # 3. Same but perhaps more obvious:
      #      t.check name => "password_constraint", expr => "password_check(password)"
      #
      # The expression must be specified, the name of the constraint
      # is always optional
      #
      def check(*args)
        ActiveRecord::Base.logger.debug("IN: TableDefinition#check")
        extra_str << ", #{check_str(column, options, false)}"
      end
      
      private
      
      def extra_str
        ActiveRecord::Base.logger.debug("IN: TableDefinition#extra_str")
        @extra_str ||= ""
      end
      
      def extra_str=(arg)
        ActiveRecord::Base.logger.debug("IN: TableDefinition#extra_str=")
        @extra_str = arg
      end
    end
  end
end
