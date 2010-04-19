require 'active_record/connection_adapters/abstract_adapter'

module MasterSlave
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
        slave_configs = [config[:slave].merge(:adapter => config[:real_adapter])]
      elsif config.has_key?(:slaves)
        slave_configs = config[:slaves].collect {|c| c.merge(:adapter => config[:real_adapter])}
      else
        raise ArgumentError, "No slave database configuration specified."
      end

      ConnectionAdapters::MasterSlaveAdapter.new(logger, config, master_config, slave_configs)
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
      
      def initialize(logger, config, master_config, slave_configs)
        super(nil, logger)

        MasterSlave.class_eval <<-ENDEVAL
          class Master < ActiveRecord::Base
          end
        ENDEVAL
        MasterSlave::Master.establish_connection(master_config)
        @master  = MasterSlave::Master.connection

        @slaves = []
        slave_configs.each_with_index do |slave_config, i|
          MasterSlave.class_eval <<-ENDEVAL
            class Slave#{i} < ActiveRecord::Base
            end
          ENDEVAL
          klass = eval "MasterSlave::Slave#{i}"
          klass.establish_connection(slave_config)
          @slaves << klass.connection
        end
        
        if (config[:default] and config[:default].to_s.downcase == "master")
          @current = @master
        else
          @current = @slaves[rand(@slaves.size)]
        end
      end
      
      def adapter_name
        "MasterSlave"
      end
      
      def active?
        not_ok = ([@master] + @slaves).collect {|db| db.active?}.reject {|ok| ok}
        !not_ok.any?
      end

      def reconnect!
        not_ok = ([@master] + @slaves).collect {|db| db.reconnect!}.reject {|ok| ok}
        !not_ok.any?
      end

      def disconnect!
        not_ok = ([@master] + @slaves).collect {|db| db.disconnect!}.reject {|ok| ok}
        !not_ok.any?
      end

      def reset!
        not_ok = ([@master] + @slaves).collect {|db| db.reset!}.reject {|ok| ok}
        !not_ok.any?
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
        i = rand(@slaves.size)
        @logger.info "Switching to Slave #{i}"
        original = @current
        @current = @slaves[i]
        result = yield
        @current = original
        result
      end
      
      methods_to_delegate_to_current = ["select", "select_all", "select_one", "select_value", "select_values", "columns"]

      methods_to_delegate_to_master = []
      methods_to_delegate_to_master += ActiveRecord::ConnectionAdapters::Quoting.instance_methods(false)
      methods_to_delegate_to_master += ActiveRecord::ConnectionAdapters::SchemaStatements.instance_methods(false)
      methods_to_delegate_to_master += ActiveRecord::ConnectionAdapters::DatabaseStatements.instance_methods(false)
      methods_to_delegate_to_master += ActiveRecord::ConnectionAdapters::AbstractAdapter.instance_methods(false)

      methods_to_delegate_to_master -= methods_to_delegate_to_current
      methods_to_delegate_to_master -= MasterSlaveAdapter.instance_methods(false)

      delegate(*(methods_to_delegate_to_current.compact.uniq + [{:to => :current}]))
      delegate(*(methods_to_delegate_to_master.compact.uniq + [{:to => :master}]))
      
      def method_missing(method, *args, &block)
        # with all the dynamic method delegation above, we should not have to reach this point, but just in case...
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
