class ReviewDecorator < Draper::Decorator
  include Draper::LazyHelpers
  delegate_all

  def icon(value, up = true)
    case value
    when 5
      "<i class='fa fa-sun' data-fa-transform='up-4 left-2 grow-2' style='color:yellow;'></i>" +
        "<i class='fa fa-cloud' data-fa-transform='grow-6'></i>" +
       "<i class='fas fa-dove' data-fa-transform='shrink-5' style='color:white;'></i>"
    when 4
      "<i class='fa fa-heart'></i>"
    when 3
      "<i class='fa fa-trophy'></i>"
    when 2
      "<i class='fa fa-smile'></i>"
    when 1
      ""
    when 0
      ""
    when -1
      ""
    when -2
      "<i class='fa fa-frown'></i>"
    when -3
      "<i class='fa fa-arrow-from-top'></i>"
    when -4
      "<i class='fa fa-trash-alt'></i>"
    when -5
      "<i class='fa fa-exclamation-triangle'></i>"
    when -6
      "<i class='fa fa-chevron-down'></i>"
    end
  end

  def up_down(value,  up = true)
    if up
      "<i class='fa fa-chevron-up'></i>"
    else
      "<i class='fa fa-chevron-down'></i>"
    end
  end
    # case
    # when value >= 2
    #   "<i class='fa fa-chevron-up' data-fa-transform='up-4'></i>" +
    #     "<i class='fa fa-chevron-up'></i>"
    # when value == 1
    #   "<i class='fa fa-chevron-up'></i>"
    # when value == 0
    #   "<i class='fa fa-meh'></i>"
    # when value == -1
    #   "<i class='fa fa-chevron-down'></i>"
    # when value <= -2
    #   "<i class='fa fa-chevron-down'></i>"
end
