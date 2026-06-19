# Changelog

All notable changes to BiteWorthy v2 are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] - 2024-12-19

### Added
#### UI/UX
- Modern design system using Tailwind CSS v4 with indigo/purple gradient theme
- Responsive navigation bar with user menu and mobile support
- Beautiful homepage with hero section, statistics, and feature cards
- Reusable components: restaurant cards, rating stars, user avatars
- Professional footer with company information and links
- Glass morphism effects and backdrop blur throughout

#### Authentication
- Redesigned all Devise views with modern styling
- User dashboard with statistics, recent activity, and quick actions
- Google OAuth2 integration
- Magic link (passwordless) authentication
- Proper session management and redirects

#### Restaurant Features
- Advanced restaurant browsing with sidebar filters
- Filtering by cuisine type, price range, delivery/takeout options
- Full-text search across restaurant names and descriptions
- Sorting options (name, rating, newest)
- Beautiful restaurant detail pages with comprehensive information
- Restaurant cards with ratings, reviews, and service badges

#### Menu System
- Organized menu display with sections and groups
- Comprehensive item cards with pricing and dietary information
- Spice level indicators with visual peppers
- Dietary flags (vegan, gluten-free, etc.) with color coding
- Individual item detail pages
- Foods and ingredients breakdown

#### Review System
- Interactive star rating using Stimulus controller
- Review creation and editing with proper authorization
- Helpful/unhelpful voting system with Turbo Stream updates
- Polymorphic reviews for restaurants, items, and foods
- Review statistics and breakdowns
- Points awarded for writing reviews

### Changed
- Migrated from React frontend to Rails with Hotwire (Turbo + Stimulus)
- Updated all controllers with proper eager loading
- Enhanced data model with better relationships
- Improved seed data with realistic content

### Fixed
- N+1 query issues throughout the application
- Authentication flow redirects
- Mobile responsive layout issues
- RuboCop style violations

### Technical
- Rails 8.0.2 with Ruby 3.3.6
- PostgreSQL 15 for database
- Redis 7 for caching
- Elasticsearch 8 for search (ready for integration)
- Tailwind CSS v4 for styling
- Hotwire (Turbo + Stimulus) for interactivity
- Docker Compose for development environment

## [0.1.0] - 2024-05-23 (Initial Setup)

### Added
- Initial Rails 8 application structure
- Database schema with 34 tables
- User authentication with Devise
- Admin panel with Administrate
- Docker development environment
- Basic models and relationships
- Comprehensive seed data