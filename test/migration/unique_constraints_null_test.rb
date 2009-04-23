
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

require 'test_helper'

# table with unique clauses
class CreateBars < ActiveRecord::Migration
  def self.up
    create_table :bars do |t|
      t.string :name, :unique => true, :null => false
    end
  end

  def self.down
    drop_table :bars
  end
end

# The matching model
class Bar < ActiveRecord::Base
end

class UniqueConstraintsNullTest < ActiveSupport::TestCase
  def setup
    create_db(ActiveRecord::Base, db_config1)
    CreateBars.up
  end

  def teardown
    CreateBars.down
  end

  def test_cannot_save_valid_null
    f = Bar.new()
    assert_equal(false, f.save, "Can save model with null name")
  end

  def test_can_save_valid
    f = Bar.new(:name => "dog")
    assert(f.save, "Can not save valid model with name")
  end

  def test_cannot_save_duplicate
    f = Bar.new(:name => "myname")
    g = Bar.new(:name => "myname")
    f.save
    assert_equal(false, g.save, "Should not be able to save duplicate")
  end

  def test_save_bang_throws
    f = Bar.new(:name => "myname")
    g = Bar.new(:name => "myname")
    f.save
    assert_raise(ActiveRecord::RecordNotSaved) do
      g.save!
    end
  end

  def test_error_message
    f = Bar.new(:name => "myname")
    g = Bar.new(:name => "myname")
    f.save
    g.save
    assert_equal("has already been taken", g.errors.on(:name))
  end

  def test_null_name_message
    f = Bar.new
    f.save
    assert("can't be blank", f.errors.on(:name))
  end
end
