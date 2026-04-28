class UsersController < ApplicationController
  before_filter :authenticate_user!
  before_action :set_user, only: [:show, :edit, :update, :destroy]
  before_action :user_reviews, only: :my_points

  def set_user
    @tag_reviews        = Review.tag_reviews(current_user).order_desc
    @food_reviews       = Review.food_reviews(current_user).order_desc
    @item_reviews       = Review.item_reviews(current_user).order_desc
    @restaurant_reviews = Review.restaurant_reviews(current_user).order_desc
  end

  def show
    # @food_reviews
    #TODO allow eager loading of foods
    liked_foods    = @item_reviews.where('rating > 0').map{|item| item.review.foods.includes(:restaurant)}.flatten.uniq
    ok_foods       = @item_reviews.where('rating = 0').map{|item| item.review.foods.includes(:restaurant)}.flatten.uniq
    disliked_foods = @item_reviews.where('rating < 0').map{|item| item.review.foods.includes(:restaurant)}.flatten.uniq

    @ok_foods        = (liked_foods & disliked_foods).sort_by(&:name)
    @liked_foods     = (liked_foods - disliked_foods).sort_by(&:name)
    @disliked_foods  = (disliked_foods - liked_foods).sort_by(&:name)
    @undecided_foods = (liked_foods & ok_foods & disliked_foods).sort_by(&:name)
  end

  def choose_tags
    ingredient_tags = @tags.joins(:items).where(variety: 0).uniq.order(:name)
    choice_tags     = @tags.joins(:items).where(variety: 2).uniq.order(:name)
    nature_tags     = @tags.joins(:items).where(variety: 3).uniq.order(:name)
    @tags = [ingredient_tags, choice_tags, nature_tags]
    @ratings = Review.ratings
    @reviews = Review.tag_reviews(current_user.id)
  end

  def my_points
    @user_points = Rails.cache.fetch("points-user_#{current_user.id}",
                                     expires_in: 1.hours,
                                     race_condition_ttl: 10,
                                     force: @force_recache) do
      Point.where(user: current_user).to_a
    end
  end

  def ratings
    rating_hash = {'possible_death' => 0, 'allergic' => 0, 'vile' => 0, 'disgust' => 0, 'terrible' => 0, 'dislike' => 0,
                   "-" => 0,
                   'like' => 0, 'enjoy' => 0, 'great' => 0, 'delicious' => 0, 'love' => 0, 'heavenly' => 0}
    @item_reviews = Review.item_reviews(current_user).order_desc
    @food_reviews = Review.food_reviews(current_user).order_desc
    @food_ratings = {}
    @item_reviews.each do |item_review|
      item_review.review.foods.each do |food|
        if @food_ratings[food].blank?
          @food_ratings[food] = rating_hash.clone
        end
        if @food_reviews.map(&:review_id).include? food.id
          @food_ratings[food][@food_reviews.where(review_id: food.id).first.rating] += 1
        end
          @food_ratings[food][item_review.rating] += 1
      end
    end
    @food_ratings.keys.each do |food_key|
      sum = 0
      total = 0
      bonus = 0
      @food_ratings[food_key].keys.each do |rating_key|
        if @food_ratings[food_key][rating_key] > 0
          bonus += Review.ratings[rating_key]
          sum += @food_ratings[food_key][rating_key] * Review.ratings[rating_key]
          total += @food_ratings[food_key][rating_key]
          @food_ratings[food_key]['avg'] = sum / total
          @food_ratings[food_key]['percent'] = (sum / total) * 9 + 50 + bonus
        end
      end
    end
  end
end
