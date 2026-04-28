// Unused ATM
$.admin_ingredients = {
  init: function(){
    this.wireupListeners();
  },

  wireupListeners: function(){
       //Update possible content for season based on show tag.
    console.log("admin_ingredients");
    $('.remove-ingredient-tag').click(function() {
      var ingredient = $(this).data('ingredient-id');
      var tag        = $(this).data('tag-id');

      $.admin_ingredients.removeTagFromIngredient(ingredient, tag);
    });
  },

  removeTagFromIngredient: function(ingredient, tag) {
    $.ajax({
      url: "/admin/ingredients/"+ingredient+"remove_tag",
      cache: false,
      dataType: "html",
      type: "POST",
      data: { tag_id: tag_id },
      success: function(tags_partial){
        console.log("tag REMOVED")
        // $('#menu-group-select').html(menu_group_select);
      },
      error: function(error) {
        console.log("load removeTagFromIngredient ajax error: ");
        console.log(error);
      }
    });
  }
}