
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
#
#
# To get the tests to work, the plug in needs to be in the typical
# vendor/plugins directory of a working rails project
#
ENV["RAILS_ENV"] = "test"
ENV['RAILS_ROOT'] ||= File.dirname(__FILE__) + '/../../../..' 
require File.expand_path(File.join(ENV["RAILS_ROOT"], "/config/environment"))
require 'test_help'

def db_config1
  configurations = YAML::load(IO.read(File.dirname(__FILE__) + '/database.yml'))
  db_adapter = ENV['DB']
  db_adapter ||= 'postgres'
  configurations[db_adapter]
end

def db_config2
  configurations = YAML::load(IO.read(File.dirname(__FILE__) + '/database.yml'))
  db_adapter = ENV['DB2']
  if db_adapter.nil? && ENV['DB']
    db_adapter = ENV['DB'] + "2"
  end
  db_adapter ||= 'postgres2'
  configurations[db_adapter]
end

#
# create_db is called at the start of a test case to create a fresh
# and empty database.
#
def create_db(klass, config)
  klass.logger = Logger.new(File.dirname(__FILE__) + "/debug.log")
  case config['adapter']
  when 'postgresql'
    # Connect to postgres database
    klass.establish_connection(config.merge('database' => 'postgres'))
    # Drop old database (error ignored if not already present)
    klass.connection.drop_database(config['database'])
    # Create new fresh database
    klass.connection.create_database(config['database'])
    # Attach to new database
    klass.establish_connection(config)
  end
end

def one_time_setup
  # Stop the printing of the migration messages
  ActiveRecord::Migration.verbose = false
  require File.dirname(__FILE__) + "/../init.rb"
end

one_time_setup
