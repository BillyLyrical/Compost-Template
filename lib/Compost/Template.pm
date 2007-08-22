package Compost::Template;

# See Compost::Template.pod for documentation

use strict;
use warnings;
#use diagnostics;

use File::Spec;
use Compost::Template::Misc;

our $VERSION = '0.07';

use constant {

	OP_CONFIG      =>  0,
	OP_DATA        =>  1,
	OP_VAR         =>  2,
	OP_PRINTF      =>  3,
	OP_CALL        =>  4,
	OP_STARTBLOCK  =>  5,
	OP_ENDBLOCK    =>  6,
	OP_FINISH      =>  7,

	BLOCK_NOTIF    => 0,
	BLOCK_IF       => 1,
	BLOCK_ELSE     => 2,
	BLOCK_LOOP     => 3,
	BLOCK_INSERT   => 4,
	BLOCK_PREFIX   => 5,
	BLOCK_MAP      => 6,
	BLOCK_FORMAT   => 7,
	BLOCK_STATE    => 8,
  
	TEST_NOT       => 0,
	TEST_DEFINED   => 1,
	TEST_EQUALS    => 2,
	TEST_GT        => 3,
	TEST_GTE       => 4,
	TEST_LT        => 5,
	TEST_LTE       => 6,

	GLOBAL_VAR     => 0,
	ESCAPE_HTML    => 1,
	ESCAPE_URL     => 2,
	VAR_SHRUG      => 3,

	DELIMITER      => "\0\n",  # FIXME: is this the best we can do?
};


# -------------------
sub new {
	my ( $class, %opt ) = @_;

	# a new template or a changed one
	my $self = bless( { CONFIG => {
		filename            => '',
		max_depth           => 10,
		die_on_bad_params   => 1,
		remake              => 0,
		allow_absolute_path => 0,
		allow_relative_path => 1,
		no_includes         => 0,
	} }, ref $class || $class );
	map { $self->{CONFIG}{$_} = $opt{$_} } keys %opt;

	# pull in the factory's params
	if ( defined $opt{params} ) {
		$self->param( $opt{params} );
	}

	# set up the template paths
	$self->{CONFIG}{path} = [];

	push @{ $self->{CONFIG}{path} }, File::Spec->rel2abs( $ENV{COMPOST_TEMPLATE_ROOT} )
	 if ( exists $ENV{COMPOST_TEMPLATE_ROOT} and defined $ENV{COMPOST_TEMPLATE_ROOT} );

	if ( exists $opt{path} and defined $opt{path} ) {
		push @{ $self->{CONFIG}{path} },
		 map { s{\/*$}{/}; File::Spec->rel2abs( $_ ) }
		 ( ref $opt{path} eq 'ARRAY' ) ? @{ $opt{path} } : $opt{path};
	}

	push @{ $self->{CONFIG}{path} }, File::Spec->rel2abs(File::Spec->curdir())
	 unless ( scalar @{ $self->{CONFIG}{path} } );

	# define cache location
	if ( exists $opt{cache} ) {
		$self->{CONFIG}{cache} = File::Spec->rel2abs( $opt{cache} );
	} 
	elsif ( exists $opt{cache_dir} ) {
		$opt{filename} =~ m/(\w+)\.\w+$/;
		$self->{CONFIG}{cache} = File::Spec->rel2abs( "$opt{cache_dir}/$1.cache" );
	}

	# use cache?
	if ( not defined $opt{template}
	 and defined $self->{CONFIG}{cache}
	 and $self->{CONFIG}{remake} == 0
	 and -e $self->{CONFIG}{cache}
	 and -s _ and -r _  ) {
		my $usecache = 1;

		my $s = _read_cache( $self->{CONFIG}{cache});
		$s->{_PARAMS} = $self->{_PARAMS};

		my $mtime = ( stat( $s->{CONFIG}{cache} ) )[9];
		for my $f ( @{ $s->{_INCLUDE_FILES} } ) {
			if ( $f =~ s/^\#// ) {                  # previously missing include found
				$f = $s->_find_file( $f );
				$f or next;
				$usecache = 1;
				last;
			}
			if ( ( stat( $f ) )[9] > $mtime ) {     # file has changed
				$usecache = 0;
				last;
			}
		}

		# we got a cached parse tree
		return $s if $usecache;
	}

	# parse tokens - reduce template to a list of commands
	require Compost::Template::Parser;
	if ( defined $opt{template} ) {
		delete $self->{CONFIG}{cache};
		my $buf = _add_debug_data( $opt{template}, 0 );
		$self->{_STACK} = $self->_parse( \$buf );
	}
	else {
		$self->{_STACK} = $self->_parse( $self->_include( $self->{CONFIG}{filename} ));
	}

	# empty file cache
	$self->{_FILE_CACHE} = {};

	# cache template
	$self->_dump()
	 if ( $self->{CONFIG}{cache} );

	return $self;
}

# -------------------
sub param {
	my $s = shift;

	if ( scalar @_ == 1 ) {
		die "Invalid Parameter, '$_[0]' is not a HASH"
		  unless ( ref $_[0] eq 'HASH' );
		for ( keys %{ $_[0] } ) {
			$s->{_PARAMS}{$_} = ${ $_[0] }{$_};
		}
	}
	else {
		while (@_) {
			my $k = shift;
			last unless (@_);
			$s->{_PARAMS}{$k} = shift;
		}
	}
	return $s;
}

# -------------------
sub run {
	my $s = shift;

	require Compost::Template::Runtime;
	my $output = $s->_process_commands(
		$s->{_STACK}, $s->{_PARAMS}, 0
	);
	$s->{_PARAMS} = {};
	return $output;
}

# -------------------
sub reply {
	my $s = shift;

	$s->param(@_);
	print "Content-type: text/html\n\n";
	print $s->run;
	exit 1;
}

# -------------------
sub set_call {
 	my ( $s, $name, $callback ) = @_;

	die "set_call '$name':'$callback' is not a code ref\n"
	 unless ref $callback;
	$s->{_CALLS}{$name} = $callback;
	return $s;
}

# -------------------
sub delete_call {
 	my ( $s, $name ) = @_;
	delete $s->{_CALLS}{$name};
	return $s;
}

# -------------------
sub set_state {
 	my ( $s, $key, $val ) = @_;
	$s->{CONFIG}{State}{$key} = $val;
	return $s;
}

# -------------------
sub get_state {
 	my ( $s, $key ) = @_;
	return '' unless ( exists $s->{CONFIG}{State}{$key} );
	return $s->{CONFIG}{State}{$key};
}

# -------------------
sub match {
	my ( $s, $key, $test ) = @_;

	return 0 unless ( exists $s->{CONFIG}{State}{$key} );
	my $state = $s->{CONFIG}{State}{$key};

	if ( $test !~ m/[\!\*\?]/ ) {
		return ( $test eq $state ) ? 1 : 0;	
	}

	my $match  = ( $test =~ s/^!// ) ? 0 : 1;
	my $regex  = _make_match( $test );
	my $ret    = ( $state =~ m/^$regex$/ ) ? 1 : 0;
	my $notRet = ( $ret == 1 ) ? 0 : 1;
	return ( $match ) ? $ret : $notRet;
}

# ==============
# private subs

# -------------------
sub _read_cache {
	my $file = shift;

	open( my $fh, '<', $file )
	 or die "Unable to open cache '$file' for reading:$!";
	sysread( $fh, my $buffer, -s $file )
	 or die "Unable to sysread '$file':$!";
	close $fh;

	my $self = bless {
		_PARMS      => {},
		CONFIG      => {},
		CACHE_FILES => [],
	}, 'Compost::Template';

	my @stack;
	my $c = 0;
	for my $line ( split DELIMITER, $buffer ) {
		$c++;

		$line =~ m/^(\d+),/
		 or die "Bad line $c '$line' in cache '$file'";
		if ( $1 == OP_CONFIG ) {
			my ( $op, $key, $val, $val2 ) = split ',', $line;
			if ( $key eq 'cache' ) {
				$self->{CONFIG}{cache} = $val;
			}
			elsif ( $key eq 'filename' ) {
				$self->{CONFIG}{filename} = $val;
			}
			elsif ( $key eq 'includes' ) {
				push @{ $self->{_INCLUDE_FILES} }, $val;
			}
			elsif ( $key eq 'path' ) {
				push @{ $self->{CONFIG}{path} }, $val;
			}
			elsif ( $key eq 'config' ) {
				$self->{CONFIG}{$val} = $val2;
			}
			else {
				die "Unknown CONFIG key '$key' in cache '$file' line $c";
			}
		}
		elsif ( $1 == OP_DATA ) {
			$line =~ s/^(\d+),(\d+),//;
			push @stack, [ $1, $2, $line ];
		}
		else {
			push @stack, [ split( ',', $line ) ];
		}

		$line = '';
	}
	$self->{_STACK} = \@stack;

	return $self;
}

# -------------------
sub _make_match {
	my $test = shift;

	return !warn "Invalid Match '$test'\n" unless (
		   $test =~ m/^\!?[\w\.\*\?]+$/
		&& $test !~ m/[\*\?][\*\?]/
		&& $test !~ m/\.\./
		&& $test !~ m/^\./
		&& $test !~ m/\.$/
	);

	# define regex atoms
	my $one  = '\w+';          # ?
	my $any  = "$one(\\.$one)*";    # *

	$test =~ s/\./'\.'/eg;
	$test =~ s/\?/$one/g;
	$test =~ s/\*/$any/g;
	return $test; 
}

# -------------------
sub _find_file {
	my ( $s, $file ) = @_;

	# is it an absolute path
	if ( File::Spec->file_name_is_absolute( $file ) ) {
		if ( $s->{CONFIG}{allow_absolute_path} == 0 ) {
			die "Illegal attempt to read absolute path '$file'";
		}
		my $filename = Compost::Template::Misc::safe_file( $file );
		return ( -r $filename ) ? $filename : undef;
	}

	# is it in path
	for my $path ( @{ $s->{CONFIG}{path} } ) {
		my $filename = File::Spec->catfile( $path, $file );

		$filename = File::Spec->rel2abs( $filename )
		 if ( $s->{CONFIG}{allow_relative_path} == 1 );

		$filename = Compost::Template::Misc::safe_file( $filename );
		return Compost::Template::Misc::safe_file( $filename )
		 if ( -e $filename and -r _ );
	}

	return undef;
}

# ==============
package Compost::Template::Factory;

# -------------------
# wrapper around instantiation - holds vars
#
# my $factory = Compost::Template::Factory->create( @options );
# my $t = $factory->new( $filename );
# 
sub create {
	my $class = shift;
	my $self  = { @_ };
	return bless $self, ref $class || $class;
}

sub new {
	my ( $s, $filename ) = @_;
	return Compost::Template->new( 'filename' => $filename, %{ $s } );
}

# thankyouverymuchgoodnight
1;

