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
SLAVE_DB = File.expand_path(File.join(File.dirname(__FILE__), "test_slave.sqlite3"))
FileUtils.rm_f(MASTER_DB)
FileUtils.rm_f(SLAVE_DB)

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
    :slave => {
      :database => SLAVE_DB
    },
  },
  
  "direct_master" => {
    :adapter => "sqlite3",
    :database => MASTER_DB
  },
  "direct_slave" => {
    :adapter => "sqlite3",
    :database => SLAVE_DB
  }
}

$: << File.expand_path(File.join(File.dirname(__FILE__), "../lib"))
require File.expand_path(File.join(File.dirname(__FILE__), "..", "init.rb"))

FileUtils.rm_f(MASTER_DB)
FileUtils.rm_f(SLAVE_DB)

class DirectMaster < ActiveRecord::Base
  establish_connection :direct_master
end
class DirectSlave < ActiveRecord::Base
  establish_connection :direct_slave
end
class SampleModel < ActiveRecord::Base
end
ActiveRecord::Base.establish_connection :test

DirectMaster.connection.execute('CREATE TABLE sample_models (id integer primary key autoincrement, value varchar(16))')
DirectMaster.connection.execute('INSERT INTO sample_models (id, value) VALUES (1, "one - in both")')
DirectMaster.connection.execute('INSERT INTO sample_models (id, value) VALUES (2, "two - only in master")')
DirectMaster.connection.execute('INSERT INTO sample_models (id, value) VALUES (4, "four - in both")')

DirectSlave.connection.execute('CREATE TABLE sample_models (id integer primary key autoincrement, value varchar(16))')
DirectSlave.connection.execute('INSERT INTO sample_models (id, value) VALUES (1, "one - in both")')
DirectSlave.connection.execute('INSERT INTO sample_models (id, value) VALUES (3, "three - only in slave")')
DirectSlave.connection.execute('INSERT INTO sample_models (id, value) VALUES (4, "four - in both")')


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

  def test_insert
    new_record = SampleModel.create(:value => "new record")
    assert_equal SampleModel.with_master { SampleModel.find(new_record.id) }, new_record
    assert_raises ActiveRecord::RecordNotFound do SampleModel.with_slave { SampleModel.find(new_record.id) } end
    assert_raises ActiveRecord::RecordNotFound do SampleModel.find(new_record.id) end
  end
end
