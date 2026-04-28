module CacheInvalidator
  extend ActiveSupport::Concern

  included do
    after_destroy :invalidate_cache

    def set_cache_keys
      case self.class.to_s
      when 'Point'
        add_cache_keys(["points-user_#{self.user_id}_sum"])
      when 'Review'
        add_cache_keys(["reviews-user_#{self.user_id}_sum"])

      end
    end

    def invalidate_cache
      set_cache_keys
      clear_cache(@cache_keys)
      log_invalidate(@cache_keys)
    end


    def add_cache_keys(keys)
      if @cache_keys
        @cache_keys |= keys
      else
        @cache_keys = keys
      end
    end

    def clear_cache(keys)
      if keys.present?
        keys.each do |key|
          Rails.cache.write("#{key}-reload", true) if Rails.cache.exist?(key)
        end
      end
    end

    def log_invalidate(keys)
      cache_logger = Logger.new(Rails.root.join("log", "#{Rails.env}_cache.log"), 10, 30 * 1024 * 1024)
      cache_logger.info("#{self.class} - #{id} - '#{keys.present? ? keys.join("', '") : "NO CACHE KEYS"}'")
      @cache_keys = nil
    end
  end
end
