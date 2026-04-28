// This is a manifest file that'll be compiled into application.js, which will include all the files
// listed below.
//
// Any JavaScript/Coffee file within this directory, lib/assets/javascripts, vendor/assets/javascripts,
// or vendor/assets/javascripts of plugins, if any, can be referenced here using a relative path.
//
// It's not advisable to add code directly here, but if you do, it'll appear at the bottom of the
// compiled file.
//
// Read Sprockets README (https://github.com/sstephenson/sprockets#sprockets-directives) for details
// about supported directives.
//= require jquery
//= require jquery_ujs
//
//= require admin_item
//= require dataTables/jquery.dataTables
//= require dataTables/jquery.dataTables.foundation
//= require datatables
//= require fontawesome-all
//= require food_items
//= require foundation
//= require google_tracking_event
//= require ingredients
//= require images_loaded
//= require isotope_3.0.6
//= require ratings
//= require restaurant_menu_groups

var mql_small  = window.matchMedia("only screen and (max-width: 40em)");
var mql_medium = window.matchMedia("only screen and (min-width: 40.063em) and (max-width: 64em)");
var mql_large  = window.matchMedia("only screen and (min-width: 64.063em)");

$(function(){ $(document).foundation(); });
$(function(){
  // Foundation.global.namespace = ''
  $(document).foundation();
  $.food_form.init();
  $.ratings.init();
  setTimeout(function(){$('.alert-box').fadeOut();},11000);
});

jQuery(window).scroll(function() {
  var scrollBottom = $(document).height() - $(window).height() - $(window).scrollTop();

  if (scrollBottom < 150) {
    $(".footer").slideUp('slow');
  }
  if (scrollBottom >= 150) {
    $(".footer").slideDown('slow');
  }
});
