
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

# This test makes sure that opening a second connection keeps things working.

# The matching models
class Foo < ActiveRecord::Base
end

class Xyz < ActiveRecord::Base
end

class DoubleConnectionTest < ActiveSupport::TestCase
  self.pre_loaded_fixtures = true
  def setup
    create_db(ActiveRecord::Base, db_config1)
    ActiveRecord::Base.connection.create_table :foos do |t|
      t.string :name, :unique => true
    end
    
    create_db(Xyz, db_config2)
    Xyz.connection.create_table :xyzs do |t|
      t.string :name, :unique => true
    end
  end

  def teardown
    ActiveRecord::Base.connection.drop_table :foos
    Xyz.connection.drop_table :xyzs
  end

  def test_dc_can_save_valid_null_foo
    f = Foo.new()
    assert(f.save, "Can not save valid model with null name")
  end

  def test_dc_can_save_valid_null_xyz
    f = Xyz.new()
    assert(f.save, "Can not save valid model with null name")
  end

  def test_dc_can_save_valid_foo
    f = Foo.new(:name => "dog")
    assert(f.save, "Can not save valid model with name")
  end

  def test_dc_can_save_valid_xyz
    f = Xyz.new(:name => "dog")
    assert(f.save, "Can not save valid model with name")
  end

  def test_dc_cannot_save_duplicate_foo
    f = Foo.new(:name => "myname")
    g = Foo.new(:name => "myname")
    f.save
    assert_equal(false, g.save, "Should not be able to save duplicate")
  end

  def test_dc_cannot_save_duplicate_xyz
    f = Xyz.new(:name => "myname")
    g = Xyz.new(:name => "myname")
    f.save
    assert_equal(false, g.save, "Should not be able to save duplicate")
  end

  def test_dc_save_bang_throws_foo
    f = Foo.new(:name => "myname")
    g = Foo.new(:name => "myname")
    f.save
    assert_raise(ActiveRecord::RecordNotSaved) do
      g.save!
    end
  end

  def test_dc_save_bang_throws_xyz
    f = Xyz.new(:name => "myname")
    g = Xyz.new(:name => "myname")
    f.save
    assert_raise(ActiveRecord::RecordNotSaved) do
      g.save!
    end
  end

  def test_dc_error_message_foo
    f = Foo.new(:name => "myname")
    g = Foo.new(:name => "myname")
    f.save
    g.save
    assert_equal("has already been taken", g.errors.on(:name))
  end

  def test_dc_error_message_xyz
    f = Xyz.new(:name => "myname")
    g = Xyz.new(:name => "myname")
    f.save
    g.save
    assert_equal("has already been taken", g.errors.on(:name))
  end
end
