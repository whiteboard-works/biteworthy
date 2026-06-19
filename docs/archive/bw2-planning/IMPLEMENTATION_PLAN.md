# BiteWorthy v2 Implementation Plan

## Executive Summary

This plan outlines the systematic implementation of BiteWorthy v2, migrating from the legacy Rails 5 application to a modern Rails 8 architecture. The implementation is divided into 8 sprints over 8 weeks, with clear deliverables, technical specifications, and success metrics for each phase.

## Architecture Principles

### Core Technical Decisions
- **Frontend**: Server-rendered HTML with Hotwire (Turbo + Stimulus) enhancements
- **No-build Philosophy**: Using importmap-rails, avoiding complex JavaScript toolchains
- **Progressive Enhancement**: Base functionality works without JavaScript
- **Mobile-First**: Responsive design with Tailwind CSS
- **API-Ready**: RESTful design supporting future API development
- **Performance-First**: Redis caching, lazy loading, optimized queries

### Data Architecture
```
Restaurant (has_one :address, has_many :menus, :reviews, :hours)
    └── Menu (has_many :menu_groups, belongs_to :restaurant)
        └── MenuGroup (has_and_belongs_to_many :items)
            └── Item (has_many :foods, :extras, :prices, :reviews)
                ├── Food (has_many :ingredients)
                │   └── Ingredient (has_many :varieties)
                └── Extra (polymorphic, priceable)
```

---

## Sprint 1: Core Restaurant Infrastructure (Week 1)

### Goal
Complete restaurant management system with full CRUD operations and supporting features.

### Implementation Tasks

#### Day 1-2: Restaurant Management
```ruby
# app/controllers/restaurants_controller.rb
- Full CRUD with strong parameters
- Search and filtering by name, cuisine, location
- Status management (active/inactive/pending)
- Slug generation for SEO-friendly URLs

# app/views/restaurants/
- index.html.erb with Turbo Frame pagination
- show.html.erb with tabbed interface (Overview, Menu, Reviews, Info)
- _form.html.erb with nested address fields
- _search.html.erb Turbo Frame for live search
```

#### Day 3: Address & Hours System
```ruby
# app/models/address.rb
- Geocoding integration (geocoder gem)
- Distance calculations
- Validation of address components

# app/models/hour.rb
- Day of week + time ranges
- Special hours for holidays
- Seasonal variations
- "Open now" calculations

# app/views/restaurants/
- _hours_table.html.erb
- _map.html.erb (Stimulus controller for map integration)
```

#### Day 4: Menu & Menu Groups
```ruby
# app/controllers/menus_controller.rb
- Nested under restaurants
- Activation/deactivation
- Position ordering
- Copy/duplicate functionality

# app/controllers/menu_groups_controller.rb
- Nested under menus
- Drag-and-drop reordering (Stimulus)
- Bulk operations

# Database migrations
- add_position_to_menus
- add_position_to_menu_groups
- add_active_until_to_menus (for seasonal menus)
```

#### Day 5: Testing & Polish
```ruby
# spec/models/
- restaurant_spec.rb
- address_spec.rb
- hour_spec.rb
- menu_spec.rb

# spec/system/
- restaurant_browsing_spec.rb
- restaurant_management_spec.rb
```

### Deliverables
- [ ] Complete restaurant CRUD with address management
- [ ] Operating hours with "open now" status
- [ ] Menu and menu group management
- [ ] Search and filtering functionality
- [ ] 90% test coverage for models

---

## Sprint 2: Items & Pricing System (Week 2)

### Goal
Implement complete item management with flexible pricing and extras.

### Implementation Tasks

#### Day 1-2: Item Management
```ruby
# app/controllers/items_controller.rb
- CRUD with image uploads (Active Storage)
- Multiple menu group associations
- Status management (available/sold_out/seasonal)
- Recommended items flagging

# app/models/item.rb
- Price tier management
- Spice level validations
- Nutritional information (JSON field)
- Item variations support

# Stimulus controllers
- item_image_upload_controller.js
- item_preview_controller.js
```

#### Day 3: Dynamic Pricing System
```ruby
# app/models/price.rb
- Polymorphic pricing (items, extras)
- Size-based pricing (small, medium, large)
- Time-based pricing (happy hour)
- Special event pricing

# app/views/items/
- _price_table.html.erb
- _price_form_fields.html.erb (nested attributes)

# Stimulus controller
- dynamic_price_controller.js (calculate on selections)
```

#### Day 4: Extras Management
```ruby
# app/models/extra.rb
- Required vs optional
- Single vs multiple selection
- Price types (fixed amount, percentage)
- Compatibility rules with items

# app/controllers/extras_controller.rb
- AJAX add/remove from items
- Bulk extra management
- Extra groups (e.g., "Toppings", "Sides")

# Turbo Streams
- create.turbo_stream.erb
- destroy.turbo_stream.erb
```

#### Day 5: Item Discovery UI
```ruby
# app/views/items/
- index.html.erb with filter sidebar
- _item_card.html.erb (responsive cards)
- _quick_view.html.erb (modal preview)

# Stimulus controllers
- filter_controller.js
- quick_view_controller.js
```

### Deliverables
- [ ] Complete item CRUD with images
- [ ] Flexible pricing system
- [ ] Extras management with rules
- [ ] Item discovery interface
- [ ] Price calculations in real-time

---

## Sprint 3: Food & Ingredient System (Week 3)

### Goal
Build comprehensive food and ingredient tracking with hierarchical relationships.

### Implementation Tasks

#### Day 1-2: Food Management
```ruby
# app/models/food.rb
- Food groups/categories
- Preparation methods
- Serving sizes
- Calorie tracking

# app/controllers/foods_controller.rb
- CRUD operations
- Food-to-item associations
- Bulk food assignment
- Food search API endpoint

# Join table with metadata
# app/models/foods_item.rb
- Quantity
- Preparation notes
- Is primary ingredient flag
```

#### Day 3-4: Ingredient System
```ruby
# app/models/ingredient.rb
- Hierarchical structure (closure_tree)
- Allergen flagging
- Supplier information
- Seasonal availability

# app/models/variety.rb
- Different forms (fresh, dried, frozen)
- Conversion ratios
- Default selections
- Unit management

# app/controllers/ingredients_controller.rb
- CRUD with varieties
- Allergen warnings
- Substitute suggestions
```

#### Day 5: Food/Ingredient UI
```ruby
# app/views/foods/
- Autocomplete search (Stimulus)
- Drag-drop assignment to items
- Nutritional information display

# app/views/ingredients/
- Tree view for hierarchies
- Allergen badges
- Variety selector

# Stimulus controllers
- autocomplete_controller.js
- drag_drop_controller.js
- tree_view_controller.js
```

### Deliverables
- [ ] Food and ingredient CRUD
- [ ] Hierarchical ingredient system
- [ ] Variety management
- [ ] Allergen tracking and warnings
- [ ] Nutritional information system

---

## Sprint 4: Review & Rating System (Week 4)

### Goal
Implement comprehensive review system for all reviewable entities.

### Implementation Tasks

#### Day 1-2: Review Infrastructure
```ruby
# app/models/review.rb
- Polymorphic reviewable
- Rating validations (1-5)
- Title and content
- Approved/pending/rejected states
- Helpful votes counter

# app/controllers/reviews_controller.rb
- Create reviews for any entity
- Edit own reviews (time-limited)
- Admin moderation queue
- Review reporting system
```

#### Day 3: Review Display & Interactions
```ruby
# app/views/reviews/
- _form.html.erb (works for all reviewables)
- _review.html.erb (responsive review cards)
- _rating_stars.html.erb (interactive stars)
- _review_stats.html.erb (rating distribution)

# Stimulus controllers
- rating_stars_controller.js
- helpful_vote_controller.js
- review_form_controller.js (character count, validations)
```

#### Day 4: Review Analytics
```ruby
# app/models/concerns/reviewable.rb
- Average rating calculations
- Rating distribution
- Recent reviews scope
- Top reviewers

# app/views/shared/
- _rating_summary.html.erb
- _rating_distribution.html.erb
- _reviewer_badge.html.erb
```

#### Day 5: Moderation Tools
```ruby
# app/controllers/admin/reviews_controller.rb
- Bulk approval/rejection
- Flag inappropriate content
- Review editing by admins
- Automated spam detection

# Background job
# app/jobs/review_spam_checker_job.rb
- Check for spam patterns
- Flag suspicious reviews
- Rate limiting per user
```

### Deliverables
- [ ] Polymorphic review system
- [ ] Interactive rating interface
- [ ] Review moderation queue
- [ ] Review analytics and stats
- [ ] Spam detection system

---

## Sprint 5: Search & Discovery (Week 5)

### Goal
Implement powerful search and filtering capabilities.

### Implementation Tasks

#### Day 1-2: Elasticsearch Integration
```ruby
# app/models/concerns/searchable.rb
- Searchkick integration
- Multi-model search
- Faceted search
- Autocomplete suggestions

# config/initializers/elasticsearch.rb
- Index configuration
- Custom analyzers
- Synonym support

# app/controllers/search_controller.rb
- Global search endpoint
- Search suggestions API
- Recent/popular searches
```

#### Day 3-4: Advanced Filtering (Isotope.js)
```javascript
// app/javascript/controllers/isotope_controller.js
- Initialize Isotope layout
- Multi-attribute filtering
- Real-time result counting
- Filter state persistence

// app/javascript/controllers/filter_manager_controller.js
- Coordinate multiple filters
- Update URL parameters
- Apply/clear all filters
```

```erb
<!-- app/views/shared/_filter_sidebar.html.erb -->
- Price range sliders
- Cuisine checkboxes
- Dietary restrictions
- Rating minimum
- Distance radius
- "Open now" toggle
```

#### Day 5: Discovery Features
```ruby
# app/services/recommendation_service.rb
- Similar items algorithm
- User preference matching
- Trending items calculation
- Personalized suggestions

# app/controllers/discoveries_controller.rb
- Trending this week
- New additions
- Staff picks
- Recommended for you
```

### Deliverables
- [ ] Elasticsearch integration
- [ ] Global search with autocomplete
- [ ] Isotope.js filtering system
- [ ] Multi-faceted filtering
- [ ] Recommendation engine

---

## Sprint 6: Tag System & Admin Panel (Week 6)

### Goal
Build hierarchical tagging system and comprehensive admin interface.

### Implementation Tasks

#### Day 1-2: Tag System
```ruby
# app/models/tag.rb
- Hierarchical tags (closure_tree)
- Tag types (cuisine, dietary, feature)
- Icon support
- Slug generation
- Usage counters

# app/models/tagging.rb
- Polymorphic taggable
- Tag weight/priority
- User who tagged
- Approved status

# app/controllers/tags_controller.rb
- Tag browsing interface
- Tag merger tool
- Popular tags API
- Tag suggestions
```

#### Day 3-4: Admin Panel Foundation
```ruby
# app/controllers/admin/dashboard_controller.rb
- Statistics overview
- Recent activity feed
- Pending approvals count
- System health checks

# config/initializers/administrate.rb
- Configure Administrate gem
- Custom field types
- Dashboard customization

# app/dashboards/
- Restaurant dashboard
- User dashboard
- Review dashboard
- Custom actions
```

#### Day 5: Admin Tools
```ruby
# app/controllers/admin/tools_controller.rb
- Bulk operations interface
- Data import/export
- Duplicate detection
- Content validation

# app/jobs/
- BulkOperationJob
- DataExportJob
- DuplicateDetectionJob

# app/views/admin/
- Custom admin layouts
- DataTables integration
- Action buttons and modals
```

### Deliverables
- [ ] Hierarchical tag system
- [ ] Tag management interface
- [ ] Administrate integration
- [ ] Admin dashboard with metrics
- [ ] Bulk operation tools

---

## Sprint 7: User Features & Gamification (Week 7)

### Goal
Implement user profiles, preferences, and gamification system.

### Implementation Tasks

#### Day 1-2: User Profiles
```ruby
# app/controllers/users_controller.rb
- Public profile pages
- Edit profile with avatar
- Privacy settings
- Account deletion

# app/models/user.rb
- Avatar processing
- Username uniqueness
- Profile completeness score
- Activity tracking

# app/views/users/
- show.html.erb (public profile)
- edit.html.erb (settings page)
- _stats.html.erb (contribution stats)
```

#### Day 3-4: Gamification System
```ruby
# app/models/point.rb
- Polymorphic pointable
- Point categories
- Expiration dates
- Point history

# app/services/gamification_service.rb
- Award points for actions
- Level calculations
- Achievement checking
- Leaderboard generation

# app/models/achievement.rb
- Achievement definitions
- Progress tracking
- Badge images
- Notification triggers

# app/controllers/leaderboards_controller.rb
- Weekly/monthly/all-time
- Category-specific boards
- Friend leaderboards
```

#### Day 5: User Preferences
```ruby
# app/models/user_preference.rb
- Dietary restrictions
- Allergen alerts
- Favorite cuisines
- Price preferences
- Location preferences

# app/controllers/preferences_controller.rb
- Preference wizard
- Quick toggle interface
- Import from profile

# app/services/preference_matcher.rb
- Match items to preferences
- Warning generation
- Recommendation scoring
```

### Deliverables
- [ ] User profile system
- [ ] Points and levels
- [ ] Achievement system
- [ ] Leaderboards
- [ ] Dietary preference management

---

## Sprint 8: Polish, Performance & Deployment (Week 8)

### Goal
Optimize performance, polish UI/UX, and prepare for production deployment.

### Implementation Tasks

#### Day 1-2: Performance Optimization
```ruby
# Caching implementation
- Fragment caching for expensive views
- Redis caching for calculations
- Russian doll caching for nested content
- ETags for API responses

# Database optimization
- Missing indexes audit
- N+1 query elimination
- Counter caches implementation
- Database view for complex queries

# Asset optimization
- Image lazy loading
- CDN integration
- JavaScript splitting
- Critical CSS extraction
```

#### Day 3: Mobile Experience
```ruby
# Progressive Web App
- Service worker for offline
- Web app manifest
- Push notifications setup
- Install prompts

# Mobile-specific views
- app/views/layouts/mobile.html.erb
- Touch-optimized interfaces
- Swipe gestures (Stimulus)
- Bottom navigation bar
```

#### Day 4: Testing & Quality
```ruby
# Complete test coverage
- Model specs (100% coverage)
- Controller specs
- System tests for critical paths
- Performance tests
- API tests

# Quality tools
- RuboCop configuration
- Brakeman security audit
- Bundle audit
- Code climate setup
```

#### Day 5: Deployment Preparation
```yaml
# Production Docker setup
- Multi-stage Dockerfile
- docker-compose.production.yml
- Environment configuration
- Secret management

# CI/CD Pipeline (GitHub Actions)
- Test runner
- Security scanning
- Automated deployment
- Rollback procedures

# Monitoring
- Error tracking (Honeybadger)
- Performance monitoring (Skylight)
- Uptime monitoring
- Log aggregation
```

### Deliverables
- [ ] Performance optimization complete
- [ ] Mobile PWA features
- [ ] 95%+ test coverage
- [ ] Production Docker setup
- [ ] CI/CD pipeline configured

---

## Success Metrics

### Performance Targets
- Page load time: < 2 seconds
- Time to interactive: < 3 seconds
- Lighthouse score: > 90
- Database queries per page: < 15
- Memory usage: < 512MB per process

### Quality Metrics
- Test coverage: > 95%
- Code climate: A rating
- Zero security vulnerabilities
- Zero N+1 queries
- All WCAG 2.1 AA compliance

### Business Metrics
- User registration rate: 20% of visitors
- Review submission rate: 10% of users
- Daily active users: 30% of total
- Page views per session: > 5
- Session duration: > 3 minutes

---

## Risk Mitigation

### Technical Risks
1. **Data Migration Complexity**
   - Mitigation: Incremental migration with rollback plans
   - Tool: Custom rake tasks with progress tracking

2. **Performance Degradation**
   - Mitigation: Performance budget and monitoring
   - Tool: Continuous performance testing

3. **Search Complexity**
   - Mitigation: Start with PostgreSQL full-text, add Elasticsearch later
   - Tool: Adapter pattern for search backend

### Business Risks
1. **Feature Parity Gaps**
   - Mitigation: User feedback loop, beta testing
   - Tool: Feature flag system for gradual rollout

2. **User Migration**
   - Mitigation: Parallel running, gradual transition
   - Tool: Account migration wizard

---

## Technology Stack Summary

### Backend
- Rails 8.0.0
- Ruby 3.4.4
- PostgreSQL 15
- Redis 7
- Elasticsearch 8
- Sidekiq for background jobs

### Frontend
- Hotwire (Turbo + Stimulus)
- Tailwind CSS v4
- Importmap for JavaScript
- Isotope.js for filtering
- Chart.js for analytics

### Infrastructure
- Docker & Docker Compose
- GitHub Actions for CI/CD
- AWS/Heroku for hosting
- Cloudflare for CDN
- S3 for file storage

### Development Tools
- RSpec for testing
- RuboCop for linting
- Foreman for process management
- Letter Opener for email testing
- Faker for seed data

---

## Team Resources Needed

### Development Team
- 1 Senior Rails Developer (full-time)
- 1 Frontend Developer (Stimulus/Turbo expertise)
- 1 DevOps Engineer (part-time)
- 1 QA Engineer (part-time)

### Support Roles
- Product Owner for requirement clarification
- UX Designer for complex interactions
- Data Migration Specialist (Sprint 1-2)
- Security Auditor (Sprint 8)

---

## Post-Launch Roadmap

### Phase 1 (Months 1-2)
- Bug fixes and performance tuning
- User feedback incorporation
- Mobile app development kickoff

### Phase 2 (Months 3-4)
- API v1 public release
- Third-party integrations
- Advanced analytics dashboard

### Phase 3 (Months 5-6)
- Machine learning recommendations
- Social features
- Booking system integration

---

This implementation plan provides a clear, sprint-by-sprint roadmap to rebuild BiteWorthy with modern Rails architecture while maintaining all the sophisticated features of the original application.