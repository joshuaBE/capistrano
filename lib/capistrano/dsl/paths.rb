require "pathname"
module Capistrano
  module DSL
    module Paths
      def deploy_to(role = nil)
        fetch(:deploy_to)
      end

      def deploy_path(role = nil)
        Pathname.new(deploy_to(role))
      end

      def current_path(role = nil)
        role = dig_up_role(role)
        deploy_path(role).join(fetch(:current_directory, "current"))
      end

      def releases_path(role)
        deploy_path(role).join("releases")
      end

      def dig_up_role(role)
        unless role
          role = Thread.current["sshkit_backend"].host
        end
        role
      end

      def release_path(role = nil)
        role = dig_up_role(role)
        unless role.properties.fetch(:release_path)
          role.properties.set(:release_path, current_path(role))
        end
        role.properties.fetch(:release_path)
      end

      def set_release_path(role, timestamp=now)
        set(:release_timestamp, timestamp)
        role.properties.set(:release_path, releases_path(role).join(timestamp))
      end

      def stage_config_path
        Pathname.new fetch(:stage_config_path, "config/deploy")
      end

      def deploy_config_path
        Pathname.new fetch(:deploy_config_path, "config/deploy.rb")
      end

      def repo_url
        fetch(:repo_url)
      end

      def repo_path(role = nil)
        unless role
          if Thread.current["sshkit_backend"]
            role = Thread.current["sshkit_backend"].host
            #puts "host: #{role.hostname}"
          else
            puts "no thread found to get host"
          end
        end
        path = deploy_path(role).join("repo")
        #puts "REPO_PATH: #{path}"
        path
      end

      def shared_path(role = nil)
        deploy_path(role).join("shared")
      end

      def revision_log(role = nil)
        deploy_path(role).join("revisions.log")
      end

      def now
        env.timestamp.strftime("%Y%m%d%H%M%S")
      end

      def asset_timestamp
        env.timestamp.strftime("%Y%m%d%H%M.%S")
      end

      def linked_dirs(parent)
        paths = fetch(:linked_dirs)
        join_paths(parent, paths)
      end

      def linked_files(parent)
        paths = fetch(:linked_files)
        join_paths(parent, paths)
      end

      def linked_file_dirs(parent)
        map_dirnames(linked_files(parent))
      end

      def linked_dir_parents(parent)
        map_dirnames(linked_dirs(parent))
      end

      def join_paths(parent, paths)
        paths.map { |path| parent.join(path) }
      end

      def map_dirnames(paths)
        paths.map(&:dirname).uniq
      end
    end
  end
end
