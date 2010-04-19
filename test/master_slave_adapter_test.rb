require 'rubygems'
require 'test/unit'
require 'fileutils'
if ENV['DEBUG']
  STDERR.puts "Enabling debugger"
  require 'ruby-debug'
  Debugger.start
  Debugger.settings[:autoeval] = 1
  Debugger.settings[:autolist] = 1
else
  class Object; def debugger; end; end
end

# ENV['RAILS_ENV'] = 'test'
# RAILS_ENV = 'test'

MASTER_DB = File.expand_path(File.join(File.dirname(__FILE__), "master_slave.sqlite3"))
SLAVE0_DB = File.expand_path(File.join(File.dirname(__FILE__), "test_slave0.sqlite3"))
SLAVE1_DB = File.expand_path(File.join(File.dirname(__FILE__), "test_slave1.sqlite3"))
FileUtils.rm_f(MASTER_DB)
FileUtils.rm_f(SLAVE0_DB)
FileUtils.rm_f(SLAVE1_DB)

require 'active_record'
ActiveRecord::Base.logger = Logger.new(STDOUT)
ActiveRecord::Base.logger.level = Logger::WARN

ActiveRecord::Base.configurations = {
  "test" => {
    :adapter => "master_slave",
    :real_adapter => "sqlite3",
    :master => {
      :database => MASTER_DB
    },
    :slaves => [
      {
        :database => SLAVE0_DB
      },
      {
        :database => SLAVE1_DB
      },
    ],
  },

  "direct_master" => {
    :adapter => "sqlite3",
    :database => MASTER_DB
  },
  "direct_slave0" => {
    :adapter => "sqlite3",
    :database => SLAVE0_DB
  },
  "direct_slave1" => {
    :adapter => "sqlite3",
    :database => SLAVE1_DB
  }
}

$: << File.expand_path(File.join(File.dirname(__FILE__), "../lib"))
require File.expand_path(File.join(File.dirname(__FILE__), "..", "init.rb"))

class DirectMaster < ActiveRecord::Base
  establish_connection :direct_master
end
class DirectSlave0 < ActiveRecord::Base
  establish_connection :direct_slave0
end
class DirectSlave1 < ActiveRecord::Base
  establish_connection :direct_slave1
end
class SampleModel < ActiveRecord::Base
end
ActiveRecord::Base.establish_connection :test

DirectMaster.connection.execute('CREATE TABLE sample_models (id integer primary key autoincrement, value varchar(16))')
DirectMaster.connection.execute('INSERT INTO sample_models (id, value) VALUES (1, "one - in both")')
DirectMaster.connection.execute('INSERT INTO sample_models (id, value) VALUES (2, "two - only in master")')
DirectMaster.connection.execute('INSERT INTO sample_models (id, value) VALUES (4, "four - in both")')
DirectMaster.connection.execute('INSERT INTO sample_models (id, value) VALUES (5, "five - master")')

DirectSlave0.connection.execute('CREATE TABLE sample_models (id integer primary key autoincrement, value varchar(16))')
DirectSlave0.connection.execute('INSERT INTO sample_models (id, value) VALUES (1, "one - in both")')
DirectSlave0.connection.execute('INSERT INTO sample_models (id, value) VALUES (3, "three - only in slave")')
DirectSlave0.connection.execute('INSERT INTO sample_models (id, value) VALUES (4, "four - in both")')
DirectSlave0.connection.execute('INSERT INTO sample_models (id, value) VALUES (5, "five - slave 0")')

DirectSlave1.connection.execute('CREATE TABLE sample_models (id integer primary key autoincrement, value varchar(16))')
DirectSlave1.connection.execute('INSERT INTO sample_models (id, value) VALUES (1, "one - in both")')
DirectSlave1.connection.execute('INSERT INTO sample_models (id, value) VALUES (3, "three - only in slave")')
DirectSlave1.connection.execute('INSERT INTO sample_models (id, value) VALUES (4, "four - in both")')
DirectSlave1.connection.execute('INSERT INTO sample_models (id, value) VALUES (5, "five - slave 1")')


class MasterSlaveAdapterTest < Test::Unit::TestCase
  def test_read_from_current
    assert_equal 1, SampleModel.find(1).id
    assert_raises ActiveRecord::RecordNotFound do SampleModel.find(2) end
    assert_equal 3, SampleModel.find(3).id 
    assert_equal 4, SampleModel.find(4).id
  end

  def test_read_from_master
    SampleModel.with_master do
      assert_equal 1, SampleModel.find(1).id
      assert_equal 2, SampleModel.find(2).id
      assert_raises ActiveRecord::RecordNotFound do SampleModel.find(3) end
      assert_equal 4, SampleModel.find(4).id
    end
  end

  def test_read_from_slave
    SampleModel.with_slave do
      assert_equal 1, SampleModel.find(1).id
      assert_raises ActiveRecord::RecordNotFound do SampleModel.find(2) end
      assert_equal 3, SampleModel.find(3).id 
      assert_equal 4, SampleModel.find(4).id
    end
  end

  def test_randomized_slaves
    counts = Hash.new {|h, k| h[k] = 0}
    20.times do
      SampleModel.with_slave do
        counts[SampleModel.find(5).value] += 1
      end
    end
      
    assert (counts["five - master"] == 0)
    assert (counts["five - slave 0"] > 0)
    assert (counts["five - slave 1"] > 0)
  end
  
  def test_insert
    new_record = SampleModel.create(:value => "new record")
    assert_equal SampleModel.with_master { SampleModel.find(new_record.id) }, new_record
    assert_raises ActiveRecord::RecordNotFound do SampleModel.with_slave { SampleModel.find(new_record.id) } end
    assert_raises ActiveRecord::RecordNotFound do SampleModel.find(new_record.id) end
  end
end
