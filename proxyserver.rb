#
# $Id: proxyserver.rb,v 1.1 2001/11/17 17:17:53 michael Exp $
# Copyright (c) 2001 by Michael Neumann (neumann@s-direktnet.de)
# 

require "drb"
require "dbi"

module DBI
module ProxyServer

USED_DBD_API = "0.1"

module HelperMixin
  def catch_exception
    begin
      yield
    rescue Exception => err
      if err.kind_of? DBI::Error or err.kind_of? DBI::Warning
	err
      else
	DBI::InterfaceError.new("Unexpected Exception was raised in " +
	  "ProxyServer (#{err.inspect})")
      end
    end
  end

  def define_methods(meths)
    meths.each {|d|
      eval %{
	def #{d}(*a) 
	  catch_exception do
	    @handle.#{d}(*a) 
	  end
	end
      }
    } 
  end

end # module HelperMixin


class ProxyServer
  include HelperMixin

  attr_reader :databases

  def initialize
    @databases = []
  end

  def get_used_DBD_version
    USED_DBD_API
  end
  
  def DBD_connect(driver_url, user, auth, attr)
    catch_exception do
      ret = DBI._get_full_driver(driver_url)
      drh = ret[0][1]
      db_args = ret[1]

      dbh = drh.connect(db_args, user, auth, attr)
      DatabaseProxy.new(self, dbh)
    end
  end
end # class ProxyServer

class DatabaseProxy
  include HelperMixin
  
  METHODS = %w(ping commit rollback tables execute do quote [] []=)

  attr_reader :statements

  def initialize(parent, dbh)
    @parent = parent
    @handle = dbh
    define_methods METHODS
    @statements = []

    # store it otherwise, it'll get recycled
    @parent.databases << self
  end

  def disconnect
    begin
      catch_exception do
        @handle.disconnect
        @handle = nil
      end
    ensure
      @parent.databases.delete(self) 
    end
  end

  def prepare(stmt)
    catch_exception do
      sth = @handle.prepare(stmt)
      StatementProxy.new(self, sth)
    end
  end
end # class DatabaseProxy

class StatementProxy
  include HelperMixin

  METHODS = %w(bind_param execute fetch column_info bind_params
               cancel fetch_scroll fetch_many fetch_all)

  def initialize(parent, sth)
    @parent = parent
    @handle = sth
    define_methods(METHODS)

    # store it otherwise, it'll get recycled
    @parent.statements << self
  end

  def finish
    begin
      catch_exception do
        @handle.finish
        @handle = nil
      end
    ensure
      @parent.statements.delete(self) 
    end
  end


end # class StatementProxy

end # module ProxyServer

end # module DBI


if __FILE__ == $0
  unless DBI::DBD::API_VERSION.split(".")[0].to_i != DBI::DBD::DBI::ProxyServer::USED_DBD_API.split(".")[0].to_i 
    raise "Wrong DBD Version"
  end
  
  HOST = ARGV.shift || 'localhost'
  PORT = (ARGV.shift || 9001).to_i
  URL  = "druby://#{HOST}:#{PORT}"

  proxyServer = DBI::ProxyServer::ProxyServer.new
  DRb.start_service(URL, proxyServer)
  puts "DBI::ProxyServer started as #{URL} at #{Time.now.to_s}"
  DRb.thread.join
end

