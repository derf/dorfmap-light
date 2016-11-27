#!/usr/bin/env perl
use Mojolicious::Lite;
use 5.020;
use Data::Dumper;
use Encode qw(decode encode);
use File::Slurp qw(read_file write_file);

my %devices;

sub slurp {
	my ($file) = @_;

	my $content = read_file( $file, err_mode => 'quiet' );
	if ( defined $content ) {
		chomp $content;
	}
	return $content;
}

sub spew {
	my ( $file, $content ) = @_;

	return write_file( $file, { err_mode => 'quiet' }, $content );
}

sub set_device {
	my ( $device, $value ) = @_;
	my $path = $devices{$device}{path};
	my $bus = ( split( qr{ / }x, $devices{$device}{path} ) )[2];

	spew( $path, "$value\n" );
	system("${bus}-update");
}

sub get_device {
	my ($device) = @_;

	my $state = slurp( $devices{$device}{path} ) // 0;

	return $state;
}

sub load_devices {
	my $ccontent = slurp('devices');
	$ccontent =~ s{\\\n}{}gs;
	my @lines = split( /\n/, $ccontent );

	for my $line (@lines) {
		my ( $id, $left, $top, $right, $bottom, $controlpath, @rest )
		  = split( /\s+/, $line );
		my @text;

		if ( not $id or $id =~ m{ ^ [#] }x ) {
			next;
		}

		$devices{$id} = {
			x1   => $left,
			y1   => $top,
			x2   => $right - $left,
			y2   => $bottom - $top,
			path => "/tmp/$controlpath",
			pwm  => 0,
		};

		if ( $controlpath =~ m{ / pwm \d+ $ }x ) {
			$devices{$id}{pwm} = 1;
		}

		for my $elem (@rest) {
			if ( $elem =~ m{ ^ (?<key> [^=]+ ) = (?<value> .+ ) $ }x ) {
				$devices{$id}{ $+{key} } = $+{value};
			}
			else {
				push( @text, $elem );
			}
		}
	}
}

sub load_status {
	for my $device ( keys %devices ) {
		$devices{$device}{value} = get_device($device);
	}
}

post '/api/action' => sub {
	my ($self) = @_;
	my $params = $self->req->json;

	if ( not exists $params->{action} ) {
		$params = $self->req->params->to_hash;
	}

	my ( $action, $device ) = @{$params}{qw{action device}};

	if ( $action eq 'toggle' ) {
		my $state = get_device($device);
		if ( $state > 0 ) {
			set_device( $device, 0 );
		}
		elsif ( $devices{$device}{pwm} ) {
			set_device( $device, 255 );
		}
		else {
			set_device( $device, 1 );
		}
		load_status();
	}
	$self->render(
		json => {
			devices => \%devices,
		}
	);
};

get '/api/devices' => sub {
	my ($self) = @_;

	load_status();

	$self->render(
		json => {
			devices => \%devices,
		}
	);
};

get '/' => sub {
	my ($self) = @_;

	load_status();

	$self->render(
		'index',
		devices => \%devices,
	);
};

post '/' => sub {
	my ($self) = @_;

	my $params = $self->req->json;
	if ( not exists $params->{action} ) {
		$params = $self->req->params->to_hash;
	}

	my ( $action, $device ) = @{$params}{qw{action device}};

	if ( $action eq 'on' ) {
		if ( $devices{$device}{pwm} ) {
			set_device( $device, 255 );
		}
		else {
			set_device( $device, 1 );
		}
	}
	elsif ( $action eq 'off' ) {
		set_device( $device, 0 );
	}
	elsif ( $action eq 'toggle' ) {
		if ( get_device($device) == 0 ) {
			if ( $devices{$device}{pwm} ) {
				set_device( $device, 255 );
			}
			else {
				set_device( $device, 1 );
			}
		}
		else {
			set_device( $device, 0 );
		}
	}

	load_status();

	$self->render(
		'index',
		devices => \%devices,
	);
};

app->config(
	hypnotoad => {
		listen => [ $ENV{LISTEN} // 'http://*:8099' ],
		pid_file => '/tmp/dorfmap-light.pid',
		workers  => $ENV{WORKERS} // 1,
	},
);

app->defaults( layout => 'default' );

load_devices();

app->start;
