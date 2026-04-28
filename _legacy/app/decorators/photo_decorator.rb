class PhotoDecorator < Draper::Decorator
  include Draper::LazyHelpers
  delegate_all
end
