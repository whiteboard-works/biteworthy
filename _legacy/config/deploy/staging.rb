server '52.27.124.36', user: 'ubuntu', roles: %w{web app db}
set :branch, 'staging'
set :deploy_to, "/data/#{fetch(:application)}_staging"
set :rails_env, 'staging'
