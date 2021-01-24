/**
 * Web application
 */
const apiUrl = 'https:/d402b46a-a6dc-493a-aa24-955795f7a190-bluemix:b421adb6be6386bd98c22c1cc7a3158f229ee9bf34b1fbf84960b002ae0a3f7d@d402b46a-a6dc-493a-aa24-955795f7a190-bluemix.cloudantnosqldb.appdomain.cloud/database-vulnerability/all_docs';
const guestbook = {
  // retrieve the existing guestbook entries
  get() {
    return $.ajax({
      type: 'GET',
      url: `${apiUrl}/entries`,
      dataType: 'json'
    });
  },
  // add a single guestbood entry
  add(name, email, comment) {
    console.log('Sending', name, email, comment)
    return $.ajax({
      type: 'PUT',
      url: `${apiUrl}/entries`,
      contentType: 'application/json; charset=utf-8',
      data: JSON.stringify({
        name,
        email,
        comment,
      }),
      dataType: 'json',
    });
  }
};

(function() {

  let entriesTemplate;

  function prepareTemplates() {
    entriesTemplate = Handlebars.compile($('#entries-template').html());
  }
  /*$(function(){
    Handlebars.registerHelper('link', function(vulnerabilityID) {
        var url = Handlebars.escapeExpression(vulnerabilityID);
        var result = "<a href='https://d402b46a-a6dc-493a-aa24-955795f7a190-bluemix.cloudantnosqldb.appdomain.cloud/database-vulnerability/"+url+"'></a>";
        console.log(result);

        return new Handlebars.SafeString(result);
    });
});*/

  // retrieve entries and update the UI
  function loadEntries() {
    console.log('Loading entries...');
    $('#entries').html('Loading entries...');
    guestbook.get().done(function(result) {
      if (!result.entries) {
        return;
      }

      const context = {
        entries: result.entries
      }
      $('#entries').html(entriesTemplate(context));
    }).error(function(error) {
      $('#entries').html('No entries');
      console.log(error);
    });
  }

  // intercept the click on the submit button, add the guestbook entry and
  // reload entries on success
  $(document).on('submit', '#addEntry', function(e) {
    e.preventDefault();

    guestbook.add(
      $('#name').val().trim(),
      $('#email').val().trim(),
      $('#comment').val().trim()
    ).done(function(result) {
      // reload entries
      loadEntries();
    }).error(function(error) {
      console.log(error);
    });
  });

  $(document).ready(function() {
    prepareTemplates();
    loadEntries();
  });
})();