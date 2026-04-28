server '52.27.124.36', user: 'ubuntu', roles: %w{web app db}
set :branch, 'master'
set :deploy_to, "/data/#{fetch(:application)}"
set :rails_env, 'production'
