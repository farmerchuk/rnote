$.fn.scrollView = function () {
  return this.each(function () {
    $('html, body').animate({
      scrollTop: $(this).offset().top
    }, 0);
  });
}

$(document).ready(function() {
  $('#active-note').scrollView();
  $(".flash").delay(5000).fadeOut("slow");
});
