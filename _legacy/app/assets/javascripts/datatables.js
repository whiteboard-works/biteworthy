$(document).ready(function () {
  $('#admin-items-table').dataTable({
    "processing": true,
    "serverSide": true,
    "pageLength": 25,
    "ajax": {
      "url": $('#admin-items-table').data('source'),
      "type": "GET",
      "complete": function() {
        console.log("dataTable loaded.");
      }
    },
    "pagingType": "full_numbers",
    "columns": [
      {"data": "restaurant"},
      {"data": "name"},
      {"data": "description"},
      {"data": "actions", "sortable": false, "className": "nowrap"}
    ]
  });
  $('#admin-foods-table').dataTable({
    "processing": true,
    "serverSide": true,
    "pageLength": 25,
    "ajax": {
      "url": $('#admin-foods-table').data('source'),
      "type": "GET",
      "complete": function() {
        console.log("dataTable loaded.");
      }
    },
    "pagingType": "full_numbers",
    "columns": [
      {"data": "restaurant"},
      {"data": "name"},
      {"data": "description"},
      {"data": "actions", "sortable": false, "className": "nowrap"}
    ]
  });
  $('#admin-tags-table').dataTable({
    "processing": true,
    "serverSide": true,
    "pageLength": 25,
    "ajax": {
      "url": $('#admin-tags-table').data('source'),
      "type": "GET",
      "complete": function() {
        console.log("dataTable loaded.");
      }
    },
    "pagingType": "full_numbers",
    "columns": [
      {"data": "name"},
      {"data": "description"},
      {"data": "parent"},
      {"data": "variety"},
      {"data": "icon", "sortable": false},
      {"data": "actions", "sortable": false, "className": "nowrap"}
    ]
  });

  $('#admin-points-table').dataTable({
    "processing": true,
    "serverSide": true,
    "pageLength": 25,
    "ajax": {
      "url": $('#admin-points-table').data('source'),
      "type": "GET",
      "complete": function() {
        console.log("dataTable loaded.");
      }
    },
    "pagingType": "full_numbers",
    "columns": [
      {"data": "name"},
      {"data": "object_class"},
      {"data": "object_id"},
      {"data": "change_type"},
      {"data": "worth"},
      {"data": "object_changes"},
      {"data": "created_at"},
      {"data": "actions", "sortable": false, "className": "nowrap"}
    ]
  });
  $('#admin-ingredients-table').dataTable({
    "processing": true,
    "serverSide": true,
    "pageLength": 25,
    "ajax": {
      "url": $('#admin-ingredients-table').data('source'),
      "type": "GET",
      "complete": function() {
        console.log("dataTable loaded.");
      }
    },
    "pagingType": "full_numbers",
    "columns": [
      {"data": "name"},
      {"data": "normalized_name"},
      {"data": "tags", "sortable": false},
      {"data": "varieties", "sortable": false},
      {"data": "actions", "sortable": false, "className": "nowrap"}
    ]
  });

  $('#admin-users-table').dataTable({
    "processing": true,
    "serverSide": true,
    "pageLength": 25,
    "ajax": {
      "url": $('#admin-users-table').data('source'),
      "type": "GET",
      "complete": function() {
        console.log("dataTable loaded.");
      }
    },
    "pagingType": "full_numbers",
    "order": [[ 4, "desc" ]],
    "columns": [
      {"data": "user_name"},
      {"data": "email"},
      {"data": "level"},
      {"data": "approved"},
      {"data": "editor"},
      {"data": "admin"},
      {"data": "actions", "sortable": false, "className": "nowrap"}
    ]
  });
});
