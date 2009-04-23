
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
# Note that null does not equal null.  So, testing with columns equal
# to null is sometimes not intuitively obvious.  I'm going to avoid
# it.
class CreateBlahs < ActiveRecord::Migration
  def self.up
    create_table :blahs do |t|
      t.string :name1, :null => false
      t.string :name2, :null => false
      t.unique [ :name1, :name2 ]
    end
  end

  def self.down
    drop_table :blahs
  end
end

# The matching model
class Blah < ActiveRecord::Base
end

class UniqueConstraintsMultiTest < ActiveSupport::TestCase
  def setup
    create_db(ActiveRecord::Base, db_config1)
    CreateBlahs.up
  end

  def teardown
    CreateBlahs.down
  end

  def test_can_save_valid
    f = Blah.new(:name1 => "happy", :name2=> "doggy")
    assert(f.save, "Can not save valid model")
  end

  def test_duplicate_in_one_column_ok
    f = Blah.new(:name1 => "happy", :name2=> "doggy")
    g = Blah.new(:name1 => "happy", :name2=> "kitten")
    f.save
    assert(g.save, "Can not save valid model")
  end

  def test_duplicates_are_rejected
    f = Blah.new(:name1 => "happy", :name2=> "doggy")
    g = Blah.new(:name1 => "happy", :name2=> "doggy")
    f.save
    assert_equal(false, g.save, "Duplicate should have been rejected")
  end

  def test_errors_in_both_columns
    f = Blah.new(:name1 => "happy", :name2=> "doggy")
    g = Blah.new(:name1 => "happy", :name2=> "doggy")
    f.save
    g.save
    assert_equal("has already been taken", g.errors.on(:name1))
    assert_equal("has already been taken", g.errors.on(:name2))
  end

  def test_save_bang_throws
    f = Blah.new(:name1 => "happy", :name2=> "doggy")
    g = Blah.new(:name1 => "happy", :name2=> "doggy")
    f.save
    assert_raise(ActiveRecord::RecordNotSaved) do
      g.save!
    end
  end
end
