$(document).ready(function() {

	function refreshAll() {
		$.getJSON('/api/devices.json', {}, function(data) {
			refreshBy(data);
		});
	}

	function refreshBy(data) {
		$('li.device').each(function() {
			var device = $(this).data('device')
			if (data['devices'][device]['value'] == 0) {
				$(this).removeClass('active');
			}
			else {
				$(this).addClass('active');
			}
		});
	}

	$('li.device').click(function() {
		var link = $(this);
		$.post('/api/action', {action: 'toggle', device: link.data('device')}, function(data) {
			refreshBy(data);
		});
	});
});
