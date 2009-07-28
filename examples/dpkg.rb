require "mongrel_cluster/recipes"

set :deploy_via,    :dpkg
set :application, "spartan"
set :user, 'spartan'

#ssh_options[:verbose] = :debug

set :deploy_to, "/data/deploy/#{application}"
set :mongrel_conf, "/etc/mongrel_cluster/spartan.yml"

set :repository, "."
set :scm, :git
set :branch, "release1_branch"

set :host, "somehost-does-not-really-matter"

role :app, "#{host}", :starling => true
role :web, "#{host}"
role :db,  "#{host}", :primary => true

set :use_sudo, false

set :rails_env, "production_migration"

deploy_dir = "/data/deploy"

task :after_update_code, :roles => [:app,:web] do
	db_config = "#{deploy_dir}/spartan-database.yml"
	run "cp #{db_config} #{release_path}/config/database.yml"
	env_config = "#{deploy_dir}/spartan-production.rb"
	run "cp #{env_config} #{release_path}/config/environments/production.rb"
	run "cp #{deploy_dir}/mailer_db.php #{release_path}/public/admin/mailer/db.php"
end

