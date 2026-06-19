# External Services Configuration

This document describes the external services configuration for BiteWorthy v2.

## ✅ Completed Configuration

### 1. Ruby Version
- **Updated to Ruby 3.3.6** across all configuration files
- Dockerfile now uses `ruby:3.3.6` base image
- mise.toml configured for Ruby 3.3.6
- Gemfile specifies Ruby 3.3.6
- .ruby-version file set to 3.3.6

### 2. Environment Variables
- **.env file** configured with all necessary environment variables
- **.env.docker** file updated for Docker environment
- **SECRET_KEY_BASE** generated and added

### 3. Redis Configuration
- **Redis initializer** created at `config/initializers/redis.rb`
- Uses connection pooling for better performance
- Configured Rails cache store to use Redis
- Added `connection_pool` gem to Gemfile
- Environment variables:
  - Local: `REDIS_URL=redis://localhost:6379/0`
  - Docker: `REDIS_URL=redis://redis:6379/0`

### 4. Elasticsearch Configuration
- **Searchkick initializer** created at `config/initializers/searchkick.rb`
- Configured with proper timeouts and retry settings
- Disabled in test environment for faster tests
- Environment variables:
  - Local: `ELASTICSEARCH_URL=http://localhost:9200`
  - Docker: `ELASTICSEARCH_URL=http://elasticsearch:9200`

### 5. Mailgun Configuration
- **Mailgun initializer** already exists at `config/initializers/mailgun.rb`
- Environment variables configured:
  - `MAILGUN_API_KEY`
  - `MAILGUN_DOMAIN`
  - `MAILGUN_SMTP_LOGIN`
  - `MAILGUN_SMTP_SERVER`
  - `DEFAULT_FROM_EMAIL`

### 6. Google OAuth Configuration
- Environment variables configured:
  - `GOOGLE_CLIENT_ID`
  - `GOOGLE_CLIENT_SECRET`

### 7. Docker Configuration
- Docker Compose includes all required services:
  - PostgreSQL 15
  - Redis 7
  - Elasticsearch 8.11.0
- All services properly linked and configured

## 🚀 How to Start the Application

### Option 1: Using Docker (Recommended)
```bash
# Build and start all services
docker compose up --build

# In another terminal, run migrations and seed data
docker compose exec web bin/rails db:create db:migrate db:seed
```

### Option 2: Local Development
```bash
# Ensure you have PostgreSQL, Redis, and Elasticsearch running locally

# Use mise to set Ruby version
mise use ruby@3.3.6

# Install dependencies
bundle install

# Create and setup database
bin/rails db:create db:migrate db:seed

# Start the Rails server
bin/rails server
```

## 📝 Service URLs

- **Web Application**: http://localhost:3000
- **PostgreSQL**: localhost:5432
- **Redis**: localhost:6379
- **Elasticsearch**: localhost:9200

## 🔐 Security Notes

- The `.env` file contains sensitive credentials and should NEVER be committed to version control
- The SECRET_KEY_BASE has been generated and should be kept secure
- For production, all credentials should be replaced with production values

## ✅ Code Quality

- All Ruby files have been checked and fixed with RuboCop
- No style violations remain in the codebase