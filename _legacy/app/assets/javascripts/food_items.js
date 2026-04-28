$.food_form = {
  init: function(){
    this.wireupListeners();
  },

  wireupListeners: function(){
    //Update possible content for season based on show tag.
    $('#food_restaurant_id').change(function() {
      var restaurant_id  = $(this).val();
      $.food_form.reloadMenuSelect(restaurant_id);
    });
  },

  reloadMenuSelect: function(restaurant_id) {
    if(restaurant_id != ""){
      $.ajax({
        url: "/admin/get_menu_groups_by_restaurant",
        cache: false,
        dataType: "html",
        type: "GET",
        data: { restaurant_id: restaurant_id },
        success: function(menu_group_select){
          $('#menu-group-select').html(menu_group_select);
          $('#menu-group-select').show();
          $('#food-form').show();
        },
        error: function(error) {
          console.log("load menu_group_select ajax error: ");
          console.log(error);
        }
      });
    }
  }
}
