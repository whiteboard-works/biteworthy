# Search Setup Documentation

## Elasticsearch Search Implementation

This application now includes advanced search functionality powered by Elasticsearch via the Searchkick gem.

### Models with Search

The following models are configured for search:

1. **Restaurant** - Search by name, description, slogan
2. **Item** - Search by name, description, price notes
3. **Food** - Search by name, description

### Initial Setup

After deployment, you'll need to create and populate the search indexes:

```bash
# Create indexes for all searchable models
docker compose exec web bin/rails searchkick:reindex:all

# Or reindex individual models
docker compose exec web bin/rails runner "Restaurant.reindex"
docker compose exec web bin/rails runner "Item.reindex"
docker compose exec web bin/rails runner "Food.reindex"
```

### Search Features

- **Global Search**: Search across restaurants, items, and foods simultaneously
- **Autocomplete**: Real-time suggestions as you type (minimum 2 characters)
- **Filtering**: Filter by price range, ratings, dietary restrictions, and restaurant features
- **Highlighting**: Search terms are highlighted in results
- **Smart Suggestions**: Predictive search with type indicators

### Search Endpoints

- `GET /search` - Main search page with filters
- `GET /search/autocomplete` - AJAX endpoint for autocomplete suggestions

### Filters Available

- **Price Range**: $, $$, $$$, $$$$
- **Minimum Rating**: 2+, 3+, 4+ stars
- **Restaurant Features**: Delivery, Takeout, WiFi, Reservations
- **Food Types**: Protein, Vegetable, Grain, Dairy, Fruit, Sauce, Spice, Beverage

### Integration

The search bar is integrated into the main navigation and uses Stimulus for interactive autocomplete functionality.

### Maintenance

Indexes are automatically updated when models are created, updated, or deleted. For bulk operations, you may need to manually reindex:

```bash
docker compose exec web bin/rails runner "ModelName.reindex"
```