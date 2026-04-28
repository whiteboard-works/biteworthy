# config valid only for current version of Capistrano
lock '3.10.2'

set :application, 'biteworthy'
set :repo_url, 'git@github.com:shadoath/biteworthy.git'
set :rake, 'bundle exec rake'
set :bundle_flags, "--deployment" # --quiet
set :scm, :git
set :log_level, :debug
set :pty, true
set :rvm_ruby_string, :local
set :deploy_to, "/data/#{fetch(:application)}"
set :bundle_gemfile, -> { release_path.join('Gemfile') }
set :keep_releases, 3

set :log_level, :debug
# set :linked_files, fetch(:linked_files, []).push('config/application.yml')

# Default value for linked_dirs is []
set :linked_dirs, fetch(:linked_dirs, []).push("public/system", "public/cache")

# Default value for default_env is {}
# set :default_env, { path: "/opt/ruby/bin:$PATH" }

# Default value for keep_releases is 5

namespace :deploy do

  task :restart_nginx do
    on roles(:app), in: :sequence, wait: 5 do
      execute "sudo service nginx restart"
    end
  end
end

namespace :figaro do
  desc "SCP transfer figaro configuration to the shared folder"
  task :setup do
    on roles(:app) do
      upload! "config/application.yml", "#{shared_path}/application.yml", via: :scp
    end
  end

  desc "Symlink application.yml to the release path"
  task :symlink do
    on roles(:app) do
      execute "ln -sf #{shared_path}/application.yml #{release_path}/config/application.yml"
    end
  end
end


before "bundler:install",      "figaro:setup"
before "bundler:install",      "figaro:symlink"
after  "deploy:finishing",     "deploy:restart_nginx"
