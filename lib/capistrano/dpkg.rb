require 'fileutils'
require 'tempfile'  # Dir.tmpdir

module Capistrano
  module DpkgCode

    protected
    # The directory to which the copy should be checked out
    def tmpdir
      @tmpdir ||= configuration[:copy_dir] || Dir.tmpdir
    end

    def package_dir
      @package_dir ||= File.join(tmpdir, release_name)
    end

    def release_name
      @release_name ||= configuration[:release_name]
    end
  end
end



module Capistrano
  class Configuration
    module Connections

      class DpkgConnectionFactory #:nodoc:
	def initialize(options)
	  @options = options
	end

	def connect_to(server)
	  DpkgConnection.new(server, @options)
	end
      end

      class DpkgPostinstChannel
	include Capistrano::DpkgCode

	def self.close_all
	  @@allfiles.each { |f| f.close }
	end

	def initialize(connection)
	  @dpkgconnection = connection

	  debian_dir=File.join(package_dir, "DEBIAN")
	  FileUtils.mkdir_p(debian_dir)
	  logger.debug "Opening new postinst\n"

	  @file = IO.popen("-", "w+")
	  if @file.nil?
	    # this is to make sure that the "fi" gets written!
	    postinst=File.join(package_dir, "DEBIAN/postinst")
	    File.open(postinst, "w") do |out|
	      out.puts "#!/bin/sh\n"
	      out.puts "if [ configure = \"$1\" ]; then\n  :\n"
	      STDIN.each do |line|
		out.puts line
	      end
	      out.puts "\nfi\n"
	      out.close
	    end
	    File.chmod(0755, postinst)
	    # exit! avoids calling exception handlers, etc.
	    exit!
	  end
	  @file.sync=1

	  @@allfiles ||= Array.new
	  @@allfiles << @file

	  @values = Hash.new
	end

	def configuration
	  @dpkgconnection.configuration
	end

	def logger
	  @dpkgconnection.logger
	end
	
	def []=(index,value)
	  @values[index] = value
	  #logger.debug "DpkgConnectionChannel setting [#{index}] = #{value}\n"
	end

	def [](index)
	  case index
	  when :status then
	    0
	  else
	    @values[index]
	  end
	end

	def exec(cmd)
	  @file.puts cmd
	end

	def on_data
	  # there is never any data coming back!
	  #logger.debug "DpkgConnectionChannel on_data called\n"
	  false
	end
	def on_extended_data
	  #logger.debug "DpkgConnectionChannel on_extended_data called\n"
	  false
	end

	def on_request(kind)
	  #logger.debug "DpkgConnectionChannel on_request(#{kind}) called\n"
	  false
	end

	def on_close
	  #logger.debug "DpkgConnectionChannel on_close called\n"
	  false
	end

	def request_pty
	  yield self, true
	end

	def method_missing(sym, *args, &block)
	  logger.debug "DpkgConnectionChannel Call to #{sym}("+args.join(',')+")\n"
  	  exit
	end
      end

      class DpkgConnection
	include Capistrano::DpkgCode

	def initialize(server, options)
	  @server  = server
	  @options = options
	  @logger  = options[:logger]
	  @cmds    = []
	  @channel = nil
	end

	def configuration
	  @options
	end

	def logger
	  @logger
	end
	
	def xserver
	  @server
	end

	def preprocess
	  true
	end

	def open_channel
	  @channel ||= DpkgPostinstChannel.new(self)
	  yield @channel
	  @channel
	end

	def listeners
	  #logger.debug "DpkgConnection Call to listeners\n"
	  Hash.new
	end

	def postprocess(readers, writers)
	  @channel[:closed]=true
	end

	def method_missing(sym, *args, &block)
	  logger.debug "DpkgConnection Call to #{sym}("+args.join(',')+")\n"
  	  exit
	end
      end
    end
  end
end

