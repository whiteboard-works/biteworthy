# # encoding: ascii
# # frozen_string_literal: true
# module ActiveSupport
#   module Cache
#     class Store
#       if Services.enable_cache == "true"
#         alias_method :old_fetch, :fetch

#         def fetch(name, options = {}, &block)
#           if exist?("#{name}-reload")
#             options[:force] = true
#             delete("#{name}-reload")
#             CacheHistory.where(name: "#{name}-reload").destroy_all if Services.enable_cache_history == "true"
#           end
#           if options && options[:force] && options[:force] == true && Services.enable_cache_history == "true"
#             CacheHistory.find_or_create_by(name: name.truncate(250)).increment!(:recache_count)
#           end
#           old_fetch(name, options, &block)
#         end

#         if Services.enable_cache_history == "true"
#           alias_method :old_write, :write

#           def write(name, value, options = nil)
#             begin
#               cache = CacheHistory.find_or_create_by(name: name.truncate(250))
#               if options && options[:expires_in]
#                 expires_at = DateTime.now + options[:expires_in]
#                 cache.update(expires_at: expires_at)
#               end
#               cache.increment!(:write_count)
#             rescue => error
#               cache_logger = Logger.new(Rails.root.join("log", "#{Rails.env}_cache.log"), 10, 30 * 1024 * 1024)
#               cache_logger.info(error)
#             end
#             old_write(name, value, options)
#           end
#         end

#       end
#     end
#   end
# end
