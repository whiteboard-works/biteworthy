# BiteWorthy v2

A community-driven restaurant discovery and menu management platform with detailed food preference profiling and gamified user experience. This is the modern rewrite of BiteWorthy v1, migrating from Rails 5 to Rails 8 with Hotwire (Turbo + Stimulus) for a modern, server-rendered experience.

## 🔄 Migration Status Overview

BiteWorthy v2 is a complete rewrite of the original BiteWorthy application with modern technologies:

### Tech Stack Migration
| Component | BW/1 (Legacy) | BW/2 (Modern) | Status |
|-----------|---------------|---------------|---------|
| Rails | 5.2 | 8.0 | ✅ Complete |
| Ruby | 2.x | 3.4.4 | ✅ Complete |
| Frontend | ERB + jQuery | Hotwire (Turbo + Stimulus) | ✅ Complete |
| Styling | SCSS + Foundation | Tailwind CSS v4 | ✅ Complete |
| Database | MySQL | PostgreSQL 15 | ✅ Complete |
| Search | - | Elasticsearch 8 | ✅ Complete |
| Cache | - | Redis 7 | ✅ Complete |
| Asset Pipeline | Sprockets | Propshaft + importmaps | ✅ Complete |
| Authentication | Devise | Devise | ✅ Complete |
| File Storage | Paperclip | Active Storage | ✅ Complete |

### Architecture Improvements

- **Modern Frontend**: Hotwire-powered UX with minimal JavaScript (#nobuild philosophy)
- **Server-Rendered Design**: Rails renders HTML enhanced with Turbo frames and Stimulus controllers
- **Enhanced Data Model**: Improved schema with better normalization and relationships
- **Flexible Flagging System**: Replaced boolean sprawl with polymorphic flags/flaggings
- **Audit Trail**: Added PaperTrail for comprehensive version history
- **Better Search**: Integrated Elasticsearch for powerful search capabilities
- **Performance**: Redis caching, optimized database queries, and Turbo-accelerated navigation

## 📊 Database Migration Progress

### ✅ Completed Tables (Core Structure Migrated)
- [x] **users** - Enhanced with username, points_total, better role management
- [x] **restaurants** - Added slug, better address handling, enhanced metadata
- [x] **menus** - Improved with availability times and active status
- [x] **menu_groups** - Better sorting and active status
- [x] **items** - Enhanced with spice_level, base_price, better status tracking
- [x] **foods** - Maintained food_group, added usage tracking
- [x] **ingredients** - Added allergens JSON field, better hierarchy
- [x] **extras** - Improved pricing model with price_type
- [x] **reviews** - Enhanced with approval workflow and helpful counts
- [x] **points** - Renamed from object_* to pointable_* (polymorphic)
- [x] **tags** - Enhanced with slug, better hierarchy support
- [x] **addresses** - Separated from restaurants, improved structure
- [x] **hours** - Simplified model with better day/season handling
- [x] **prices** - New polymorphic pricing system
- [x] **varieties** - Enhanced with conversion factors and units

### ✅ New Tables (Feature Enhancements)
- [x] **flags** - Flexible boolean/attribute system
- [x] **flaggings** - Polymorphic flag assignments
- [x] **taggings** - Proper polymorphic tagging system
- [x] **versions** - PaperTrail audit log
- [x] **active_storage_*** - Modern file handling

### ✅ Improved Join Tables
- [x] **foods_ingredients** - Added quantity and preparation notes
- [x] **foods_items** - Better many-to-many with metadata
- [x] **ingredients_items** - Enhanced join table
- [x] **items_extras** - Added required flag and price override
- [x] **extras_foods** - Compatibility tracking
- [x] **foods_varieties** - Default variety and quantity tracking

### ❌ Not Migrated (Deprecated/Redesigned)
- **cache_histories** - Replaced with Redis
- **sessions** - Using Rails session store
- **tag_histories** - Replaced with versions table
- **photos** - Replaced with Active Storage
- **reports** - To be redesigned
- **seasons** - Merged into hours model
- **restaurants_users** - Replaced with roles system
- **user_roles** - Replaced with modern roles/users_roles

## 📝 Recent Changes (December 2024 MVP Development)

### Phase 1: UI Foundation ✅
- **Modern Design System**: Implemented comprehensive Tailwind CSS v4 design with indigo/purple gradient theme
- **Application Layout**: Created professional navigation bar with user menu, search, and responsive mobile design
- **Homepage Redesign**: Built hero section with animations, statistics display, feature cards, and cuisine categories
- **Reusable Components**: Created `_restaurant_card`, `_rating_stars`, and `_user_avatar` partials
- **Footer**: Added comprehensive footer with company info, links, and social media

### Phase 2: Authentication & User Experience ✅
- **Authentication Views**: Redesigned all Devise views (sign in, sign up, password reset, profile edit)
- **User Dashboard**: Created comprehensive dashboard with stats, recent reviews, and activity
- **OAuth Integration**: Configured Google OAuth2 with modern UI
- **Magic Links**: Implemented passwordless authentication option
- **Navigation Integration**: Added dashboard link and improved user menu

### Phase 3: Restaurant Discovery ✅
- **Restaurant Browsing**: Built beautiful index page with filters, search, and pagination
- **Advanced Filtering**: Added cuisine type, price range, delivery/takeout, and feature filters
- **Restaurant Details**: Created comprehensive show page with hero section, info grid, and reviews
- **Search Functionality**: Implemented full-text search across names, descriptions, and addresses
- **Sorting Options**: Added sorting by name, rating, newest, and distance

### Phase 4: Menu System ✅
- **Menu Display**: Beautiful menu pages with organized sections and item cards
- **Item Cards**: Comprehensive component showing price, spice level, dietary flags, and ingredients
- **Item Details**: Dedicated pages for individual items with full information
- **Dietary Information**: Visual indicators for vegan, gluten-free, and other dietary needs
- **Restaurant Integration**: Seamless menu preview on restaurant pages

### Phase 5: Review System ✅
- **Review Forms**: Interactive star rating with Stimulus controller
- **CRUD Operations**: Complete create, read, update, delete functionality
- **Voting System**: Helpful/unhelpful voting with Turbo Stream updates
- **Authorization**: Proper checks ensuring users can only edit their own reviews
- **Polymorphic Support**: Reviews work for restaurants, items, foods, and ingredients
- **Points Integration**: Users earn points for writing reviews

### Technical Improvements
- **Performance**: Optimized database queries with eager loading
- **Code Quality**: All code passes RuboCop standards
- **Responsive Design**: Mobile-first approach throughout
- **Accessibility**: Proper semantic HTML and ARIA attributes
- **Security**: CSRF protection, parameter sanitization, and authorization checks

## 🚀 Quick Start with Docker

### Prerequisites
- [Docker](https://docs.docker.com/get-docker/)
- [Docker Compose](https://docs.docker.com/compose/install/)

### Development Setup

1. **Clone and enter the project**
   ```bash
   git clone <repository-url>
   cd bw2
   ```

2. **Start the development environment**
   ```bash
   ./bin/docker-dev
   ```
   
   Or manually:
   ```bash
   docker compose up --build
   ```

3. **Access the application**
   - Web Application: http://localhost:3000

## 🛠️ Technology Stack

- **Backend**: Rails 8.0 + Ruby 3.4.4
- **Frontend**: Hotwire (Turbo + Stimulus) with #nobuild philosophy
- **Assets**: Propshaft + importmaps (no build step required)
- **Styling**: Tailwind CSS v4
- **Database**: PostgreSQL 15
- **Search**: Elasticsearch 8
- **Cache**: Redis 7
- **Admin**: Administrate
- **Testing**: RSpec + System tests

## 📁 Project Structure

```
├── app/
│   ├── assets/           # CSS and JavaScript assets
│   │   ├── stylesheets/  # CSS and Tailwind
│   │   └── javascript/   # Stimulus controllers
│   ├── controllers/      # Rails controllers
│   ├── models/          # Rails models
│   ├── views/           # Rails views with Turbo frames
│   │   └── layouts/     # Application layouts
│   └── javascript/      # Stimulus controllers and utilities
├── config/              # Rails configuration
│   └── importmap.rb     # JavaScript module imports
├── db/                  # Database migrations and seeds
├── spec/                # RSpec tests
└── docker-compose.yml   # Docker services configuration
```

## 🗺️ Migration Roadmap

### Phase 1: Foundation (✅ Complete)
- [x] Rails 8 setup with PostgreSQL
- [x] Docker environment configuration
- [x] Hotwire (Turbo + Stimulus) setup
- [x] Propshaft + importmaps configuration
- [x] Tailwind CSS v4 setup
- [x] Basic routing and layouts

### Phase 2: Data Migration (✅ Complete)
- [x] Core database schema migration
- [x] Model relationships and validations
- [x] Active Storage configuration
- [x] PaperTrail audit system
- [x] Flexible flags/flaggings system

### Phase 3: Authentication & Authorization (🚧 In Progress)
- [x] Devise setup and configuration
- [ ] User registration/login flows
- [ ] OAuth integration
- [ ] Role-based permissions (CanCanCan)
- [ ] Admin user management

### Phase 4: Core Features (📋 Planned)
- [ ] Restaurant CRUD operations
- [ ] Menu and item management
- [ ] Food and ingredient tracking
- [ ] Review system implementation
- [ ] Points and gamification

### Phase 5: Frontend Development (📋 Planned)
- [ ] Turbo frame setup for dynamic updates
- [ ] Stimulus controllers for interactivity
- [ ] Restaurant browsing with Turbo streams
- [ ] Menu display with lazy-loaded frames
- [ ] User dashboard with real-time updates
- [ ] Admin interface (Administrate)

### Phase 6: Advanced Features (📋 Planned)
- [ ] Elasticsearch integration
- [ ] Advanced search filters
- [ ] Recommendation engine
- [ ] API rate limiting
- [ ] Background job processing (Sidekiq)

### Phase 7: Testing & Optimization (📋 Planned)
- [ ] Comprehensive test suite
- [ ] Performance optimization
- [ ] Security audit
- [ ] Documentation
- [ ] Deployment preparation

## 🔧 Development Commands

### Docker Environment
```bash
# Start full development environment
docker compose up --build

# Database operations
docker compose exec web bin/rails db:migrate
docker compose exec web bin/rails db:seed
docker compose exec web bin/rails console

# Testing
docker compose exec web bundle exec rspec

# Access containers
docker compose exec web bash
docker compose exec db psql -U postgres -d bw2_development
```

### Native Development
```bash
# Install dependencies
bundle install

# Start development server
./bin/dev  # Runs Rails via foreman

# Database operations
bin/rails db:migrate
bin/rails db:seed
bin/rails console

# Asset compilation (if needed)
bin/rails assets:precompile

# Testing
bundle exec rspec
```

## 📋 Key Technical Changes

### Database Enhancements
- **PostgreSQL**: Better JSON support, full-text search, and performance
- **Polymorphic Patterns**: Reviews, points, flags work across entity types
- **Hierarchical Data**: Closure tree for tags and ingredients
- **Audit Trail**: Comprehensive versioning with PaperTrail

### Frontend Architecture
- **Server-Rendered**: Rails handles routing and renders HTML
- **Progressive Enhancement**: Turbo enhances navigation without full page reloads
- **Minimal JavaScript**: Stimulus controllers for targeted interactivity
- **No Build Step**: Propshaft and importmaps eliminate build complexity

### View Design
- **RESTful Routes**: Standard Rails conventions
- **Turbo Frames**: Partial page updates for dynamic content
- **Turbo Streams**: Real-time updates via WebSockets
- **Form Helpers**: Rails form builders with Turbo integration

## 🐛 Troubleshooting

### Port Conflicts
If ports 3000, 5432, 6379, or 9200 are already in use:
```bash
docker compose down
# Edit docker-compose.yml to change port mappings
docker compose up
```

### Database Issues
```bash
# Reset database
docker compose exec web bin/rails db:drop db:create db:migrate db:seed

# Or reset everything
docker compose down -v
docker compose up --build
```

### Asset Issues
```bash
# Clear asset cache
docker compose exec web bin/rails assets:clobber
docker compose exec web bin/rails assets:precompile
docker compose restart web
```

## 🤝 Contributing

This is a migration project from BW/1 to BW/2. When contributing:
1. Check the migration roadmap above
2. Ensure compatibility with the new architecture
3. Write tests for new features
4. Update documentation as needed
