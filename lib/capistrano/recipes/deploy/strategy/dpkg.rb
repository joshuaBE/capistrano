require 'capistrano/recipes/deploy/strategy/base'
require 'capistrano/dpkg'
require 'fileutils'
require 'tempfile'  # Dir.tmpdir

module Capistrano
  class Configuration
    module Connections
      class DpkgConnectionFactory
      end
    end
  end
  module Deploy
    module Strategy

      # Implements the deployment strategy which does a local SCM export,
      # and then packages the result into a debian dpkg format rather
      # than communicate directly with the remote system.

      class Dpkg < Base

	include Capistrano::DpkgCode

        def deploy!
	  debian_dir=File.join(package_dir, "DEBIAN")
	  FileUtils.mkdir_p(debian_dir)

	  control = File.join(debian_dir, "control")

	  versionnum = File.basename(configuration[:release_path])
	  ver = "1.0." + versionnum
	  
	  File.open(control, "w") do |f|
	    f.puts "Package: #{package_version_name}\n"
	    f.puts "Version: #{ver}\n"
	    f.puts "Section: capistrano\n"
	    f.puts "Priority: optional\n"
	    f.puts "Architecture: all\n"
	    f.puts "Provides: #{package_name}\n"
	    f.puts "Maintainer: #{maintainer}\n"
	    f.puts "Description: This was packaged automatically from #{revision}.\n"
	  end

	  logger.debug "getting (via :export) revision #{revision} to #{destination}"
	  system(command)

	end

	def finish!
	  Capistrano::Configuration::Connections::DpkgPostinstChannel.close_all

	  sleep(1)

	  system("cd #{package_dir}/.. && fakeroot -u sh -c 'chown -f -R root #{package_dir}; dpkg-deb -b #{release_name} #{release_name}.deb' " )
	ensure
	  system("mv #{package_dir}/../#{release_name}.deb #{package_version_name}.deb")
	  system("echo #{package_version_name}.deb >deployed-deb-name.txt")
	  system("rm -rf #{package_dir}")
	end

        protected


          # Returns the SCM's export command for the revision to deploy.
          def command
            @command ||= source.export(revision, destination)
          end

	  def release_name
	    @release_name ||= File.basename(configuration[:release_path])
	  end

	  def package_dir
	    @package_dir ||= File.join(tmpdir, release_name)
	  end

	  def deploy_dir
	    return @deploy_dir if @deploy_dir

	    localdir=configuration[:deploy_to]
	    @deploy_dir = localdir[1..(localdir.size)]
	  end

          def destination
            @destination ||= File.join(package_dir, deploy_dir, release_name)
          end
      end

    end
  end
end
