require 'active_record/connection_adapters/abstract_adapter'

module MasterSlave
  class Master < ActiveRecord::Base
  end
  
  class Slave < ActiveRecord::Base
  end
end

module ActiveRecord
  class Base
    # Establishes a connection to the database that's used by all Active Record objects.
    def self.master_slave_connection(config) # :nodoc:
      config = config.symbolize_keys

      if config.has_key?(:master)
        master_config = config[:master].merge(:adapter => config[:real_adapter])
      else
        raise ArgumentError, "No master database configuration specified."
      end

      if config.has_key?(:slave)
        slave_config = config[:slave].merge(:adapter => config[:real_adapter])
      else
        raise ArgumentError, "No slave database configuration specified."
      end

      ConnectionAdapters::MasterSlaveAdapter.new(logger, config, master_config, slave_config)
    end
    
    def self.with_master(*args, &block)
      if connection.respond_to? :with_master
        connection.with_master(*args, &block)
      else
        yield if block_given?
      end
    end

    def self.with_slave(*args, &block)
      if connection.respond_to? :with_slave
        connection.with_slave(*args, &block)
      else
        yield if block_given?
      end
    end
    
    def with_master(*args)
      self.class.with_master(*args, &block)
    end

    def with_slave(*args)
      self.class.with_slave(*args, &block)
    end
  end
  
  module ConnectionAdapters
    class MasterSlaveAdapter < AbstractAdapter
      attr_accessor :master
      attr_accessor :slave
      attr_accessor :current
      
      def initialize(logger, config, master_config, slave_config)
        super(nil, logger)

        MasterSlave::Master.establish_connection(master_config)
        MasterSlave::Slave.establish_connection(slave_config)
        @master  = MasterSlave::Master.connection
        @slave   = MasterSlave::Slave.connection
        if (config[:default] and config[:default].to_s.downcase == "master")
          @current = @master
        else
          @current = @slave
        end
      end
      
      def adapter_name
        "MasterSlave"
      end
      
      def active?
        @master.active? and @slave.active?
      end

      def reconnect!
        result_master = @master.reconnect!
        result_slave = @slave.reconnect!
        result_master && result_slave
      end

      def disconnect!
        result_master = @master.disconnect!
        result_slave = @slave.disconnect!
        result_master && result_slave
      end

      def reset!
        result_master = @master.reset!
        result_slave = @slave.reset!
        result_master && result_slave
      end
          
      def with_master
        @logger.info "Switching to Master"
        original = @current
        @current = @master
        result = yield
        @current = original
        result
      end

      def with_slave
        @logger.info "Switching to Slave"
        original = @current
        @current = @slave
        result = yield
        @current = original
        result
      end
      
      delegate :select, :select_all, :select_one, :select_value, :select_values, :columns, 
        :to => :current

      delegate :execute, :insert, :insert_sql, :update, :delete,
        :to => :master
      
      def method_missing(method, *args, &block)
        master.send(method, *args, &block)
      end

    end
  end
  
  # extend observer to always use the master database
  # observers only get triggered on writes, so shouldn't be a performance hit
  # removes a race condition if you are using conditionals in the observer
  module ObserverExtensions
    def self.included(base)
      base.alias_method_chain :update, :master_slave_master
    end

    # Send observed_method(object) if the method exists.
    def update_with_master_slave_master(observed_method, object) #:nodoc:
      if object.class.connection.respond_to?(:with_master)
        object.class.connection.with_master do
          update_without_master_slave_master(observed_method, object)
        end
      else
        update_without_master_slave_master(observed_method, object)
      end
    end
  end
end