namespace :deploy do
  task :starting do
    invoke "deploy:print_config_variables" if fetch(:print_config_variables, false)
    invoke "deploy:check"
    invoke "deploy:set_previous_revision"
  end

  task :print_config_variables do
    puts
    puts "------- Printing current config variables -------"
    env.keys.each do |config_variable_key|
      if is_question?(config_variable_key)
        puts "#{config_variable_key.inspect} => Question (awaits user input on next fetch(#{config_variable_key.inspect}))"
      else
        puts "#{config_variable_key.inspect} => #{fetch(config_variable_key).inspect}"
      end
    end

    puts
    puts "------- Printing current config variables of SSHKit mechanism -------"
    puts env.backend.config.inspect
    # puts env.backend.config.backend.config.ssh_options.inspect
    # puts env.backend.config.command_map.defaults.inspect

    puts
  end

  task updating: :new_release_path do
    invoke "deploy:set_current_revision"
    invoke "deploy:symlink:shared"
  end

  task :reverting do
    invoke "deploy:revert_release"
  end

  task :publishing do
    invoke "deploy:symlink:release"
  end

  task :finishing do
    invoke "deploy:cleanup"
  end

  task :finishing_rollback do
    invoke "deploy:cleanup_rollback"
  end

  task :finished do
    invoke "deploy:log_revision"
  end

  desc "Check required files and directories exist"
  task :check do
    invoke "deploy:check:directories"
    invoke "deploy:check:linked_dirs"
    invoke "deploy:check:make_linked_dirs"
    invoke "deploy:check:linked_files"
  end

  namespace :check do
    desc "Check shared and release directories exist"
    task :directories do
      on release_roles :all do |role|
        execute :mkdir, "-p", shared_path, releases_path(role)
      end
    end

    desc "Check directories to be linked exist in shared"
    task :linked_dirs do
      next unless any? :linked_dirs
      on release_roles :all do
        execute :mkdir, "-p", linked_dirs(shared_path)
      end
    end

    desc "Check directories of files to be linked exist in shared"
    task :make_linked_dirs do
      next unless any? :linked_files
      on release_roles :all do |_host|
        execute :mkdir, "-p", linked_file_dirs(shared_path)
      end
    end

    desc "Check files to be linked exist in shared"
    task :linked_files do
      next unless any? :linked_files
      on release_roles :all do |host|
        linked_files(shared_path).each do |file|
          unless test "[ -f #{file} ]"
            error t(:linked_file_does_not_exist, file: file, host: host)
            exit 1
          end
        end
      end
    end
  end

  namespace :symlink do
    desc "Symlink release to current"
    task :release do
      on release_roles :all do |role|
        tmp_current_path = release_path(role).parent.join(current_path(role).basename)
        execute :ln, "-s", release_path(role), tmp_current_path
        execute :mv, tmp_current_path, current_path(role).parent
      end
    end

    desc "Symlink files and directories from shared to release"
    task :shared do
      invoke "deploy:symlink:linked_files"
      invoke "deploy:symlink:linked_dirs"
    end

    desc "Symlink linked directories"
    task :linked_dirs do
      next unless any? :linked_dirs
      on release_roles :all do |role|
        execute :mkdir, "-p", linked_dir_parents(release_path(role))

        fetch(:linked_dirs).each do |dir|
          target = release_path(role).join(dir)
          source = shared_path(role).join(dir)
          next if test "[ -L #{target} ]"
          execute :rm, "-rf", target if test "[ -d #{target} ]"
          execute :ln, "-s", source, target
        end
      end
    end

    desc "Symlink linked files"
    task :linked_files do
      next unless any? :linked_files
      on release_roles :all do |role|
        execute :mkdir, "-p", linked_file_dirs(release_path(role))

        fetch(:linked_files).each do |file|
          target = release_path(role).join(file)
          source = shared_path(role).join(file)
          next if test "[ -L #{target} ]"
          execute :rm, target if test "[ -f #{target} ]"
          execute :ln, "-s", source, target
        end
      end
    end
  end

  desc "Clean up old releases"
  task :cleanup do
    on release_roles :all do |host|
      releases = capture(:ls, "-x", releases_path(host)).split
      valid, invalid = releases.partition { |e| /^\d{14}$/ =~ e }

      warn t(:skip_cleanup, host: host.to_s) if invalid.any?

      if valid.count >= fetch(:keep_releases)
        info t(:keeping_releases, host: host.to_s, keep_releases: fetch(:keep_releases), releases: valid.count)
        directories = (valid - valid.last(fetch(:keep_releases))).map do |release|
          releases_path(host).join(release).to_s
        end
        if test("[ -d #{current_path} ]")
          current_release = capture(:readlink, current_path(host)).to_s
          if directories.include?(current_release)
            warn t(:wont_delete_current_release, host: host.to_s)
            directories.delete(current_release)
          end
        else
          debug t(:no_current_release, host: host.to_s)
        end
        if directories.any?
          directories_str = directories.join(" ")
          execute :rm, "-rf", directories_str
        else
          info t(:no_old_releases, host: host.to_s, keep_releases: fetch(:keep_releases))
        end
      end
    end
  end

  desc "Remove and archive rolled-back release."
  task :cleanup_rollback do
    on release_roles(:all) do |host|
      last_release = capture(:ls, "-xt", releases_path(host)).split.first
      last_release_path = releases_path(host).join(last_release)
      if test "[ `readlink #{current_path}` != #{last_release_path} ]"
        execute :tar, "-czf",
                deploy_path.join("rolled-back-release-#{last_release}.tar.gz"),
                last_release_path
        execute :rm, "-rf", last_release_path
      else
        debug "Last release is the current release, skip cleanup_rollback."
      end
    end
  end

  desc "Log details of the deploy"
  task :log_revision do
    on release_roles(:all) do |host|
      within releases_path(host) do
        execute :echo, %Q{"#{revision_log_message}" >> #{revision_log}}
      end
    end
  end

  desc "Revert to previous release timestamp"
  task revert_release: :rollback_release_path do
    on release_roles(:all) do
      set(:revision_log_message, rollback_log_message)
    end
  end

  task :new_release_path do
    timestamp = now

    # must be each, not "on", because on creates ephermal
    # roles that do not retain settings.
    release_roles(:all).each do |role|
      set_release_path(role, now)
    end
  end

  task :rollback_release_path do
    on release_roles(:all) do |role|
      releases = capture(:ls, "-xt", releases_path(role)).split
      if releases.count < 2
        error t(:cannot_rollback)
        exit 1
      end

      rollback_release = ENV["ROLLBACK_RELEASE"]
      index = rollback_release.nil? ? 1 : releases.index(rollback_release)
      if index.nil?
        error t(:cannot_found_rollback_release, release: rollback_release)
        exit 1
      end

      last_release = releases[index]
      set_release_path(role, last_release)
      set(:rollback_timestamp, last_release)
    end
  end

  desc "Place a REVISION file with the current revision SHA in the current release path"
  task :set_current_revision  do
    on release_roles(:all) do |role|
      within release_path(role) do
        execute :echo, "\"#{fetch(:current_revision)}\" >> REVISION"
      end
    end
  end

  task :set_previous_revision do
    on release_roles(:all) do |role|
      target = release_path(role).join("REVISION")
      if test "[ -f #{target} ]"
        set(:previous_revision, capture(:cat, target, "2>/dev/null"))
      end
    end
  end

  task :restart
  task :failed
end
