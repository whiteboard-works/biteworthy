$.admin_item = {
  init: function(){
    this.wireupListeners();
  },

  wireupListeners: function(){
    $('.rating-review').click(function(event) {
      event.preventDefault();
      var rating    = $(this).data('rating');
      var review_id   = $(this).data('review-id');
      var review_type = $(this).data('review-type');
      console.log("rating="+rating+" review_id="+review_id+" review_type="+review_type);
      $.admin_item.create_rating(rating, review_id, review_type);
      return false;
    });
  },

  create_rating: function(rating, review_id, review_type) {
    if(review_id != ""){
      $.ajax({
        url: "/create_user_rating",
        cache: false,
        dataType: "html",
        type: "GET",
        data: { rating: rating, review_id: review_id, review_type: review_type },
        success: function(new_rating_reviews){
          var rating_reviews_div = '#rating-reviews-'+review_type.toLowerCase()+'-'+review_id;
          console.log("success, updating="+rating_reviews_div.toString());
          $(rating_reviews_div.toString()).html(new_rating_reviews);
          $.admin_item.wireupListeners();
        },
        error: function(error) {
          console.log("create ajax error: ");
          console.log(error);
        }
      });
    }
  }
}
