package Compost::Template::Runtime;

# see Compost::Template.pod

package Compost::Template;

use strict;
use warnings;
use 5.014;
use autodie;

use Compost::Template;
use Compost::Template::Misc;

our $VERSION = '0.1.1';

# keep in sync with Compost::Template::Parser
my @opmap = (
	\&_opFinish,
	\&_opData,
	\&_opVar,
	\&_opPrintf,
	\&_opCall,
	\&_opStartblock,
	\&_opEndblock,
);

my @blockmap = (
	\&_blockNotif,
	\&_blockIf,
	\&_blockElse,
	\&_blockLoop,
	\&_blockInsert,
	\&_blockPrefix,
	\&_blockMap,
	\&_blockFormat,
	\&_blockState,
	\&_blockRandom,
	\&_blockDice,
);

my @testmap = (
	\&_testNot,
	\&_testDefined,
	\&_testEquals,
	\&_testGt,
	\&_testGte,
	\&_testLt,
	\&_testLte,
);

my @varmap   = qw{ global html url shrug };

my $DEBUG = 0;

# Compiled regexes
my $RE_GLOBAL_OPT = qr/^-global$/;
my $RE_VAR_PREFIX = qr/^\$/;
my $RE_CODEREF    = qr/CODE/;
my $RE_ARRAY_REF  = qr/ARRAY/;
my $RE_HASH_ARRAY = qr/HASH|ARRAY/;
my $RE_NUMERIC    = qr/^\d+$/;
my $RE_NEGATE     = qr{^\!};
my $RE_ANON_SCALAR = qr{^$};

# -------------------------------------------------------------------
sub _process_commands {
	my ( $self, $stack, $pa, $cursor ) = @_;

	my $state = {
		self   => $self,
		stack  => $stack,
		cursor => $cursor,
		pa     => $pa,     # params
		output => '',
		global => {},
		arg    => [],
	};
	$state->{global} = $self->{_PARAMS};

	while ( 1 ) {
		$state->{arg} = $state->{stack}[ $state->{cursor} ];

		$DEBUG and print "$state->{cursor}: " . join( ' ', @{ $state->{arg} } ) . "\n";

		my $op = $state->{arg}[1];
		return $state->{output} if $op == OP_FINISH;
		$state->{_INCLUDE_FILES} = $self->{_INCLUDE_FILES};
		$state->{CONFIG} = $self->{CONFIG};

		# mode: normal, next, endblock, finish
		my ( $jump, $mode ) = &{ $opmap[$op] }( $state );
		( defined $mode and $mode == 1 ) and return ( $state->{output}, $jump );
		$state->{cursor} = $jump;
	}
}

# -------------------------
sub _opFinish {
	my $s = shift;
	die "FINISH called";
}

# -------------------------
sub _opData {
	my $s = shift;

	defined $s->{arg}[3]
     and $s->{output} .= $s->{arg}[3];
	return $s->{arg}[2];
}

# -------------------------
sub _opVar {
	my $s = shift;

	my %options;
	if ( scalar @{ $s->{arg} } > 4 ) {
		my $c = 4;
		while ( $c < scalar @{ $s->{arg} } ) {
			my $opt = $s->{arg}[$c++];
			die "Bad var option '$opt'" . _linenum( $s, $s->{arg}[0] )
			 if ( $opt > $#varmap );
			$options{ $varmap[ $opt ]  } = 1;
		}
	}

	my $global = ( exists $options{global} ) ? 1 : 0;
	my $var = _get_var( $s, $s->{arg}[3], $global );
	unless ( defined $var ) {
		return $s->{arg}[2]
		 if ( $s->{self}{CONFIG}{die_on_bad_params} == 0
		 or exists $options{shrug} );
		die "Error: undefined var '$s->{arg}[3]' " . _linenum( $s, $s->{arg}[0] )
	}

	if ( exists $options{html} ) {
		$var = Compost::Template::Misc::htmlize( $var );
	}
	if ( exists $options{url} ) {
		$var = Compost::Template::Misc::url_encode( $var );
	}
	$s->{output} .= $var;

	return $s->{arg}[2];
}

# -------------------------
sub _opPrintf {
	my $s = shift;

	my $pattern = _get_var( $s, $s->{arg}[3], 0 );

	my @args;
	my $global = 0;
	for ( 4..$#{ $s->{arg} } ) {
		m/$RE_GLOBAL_OPT/ and $global = 1 and next;
		push @args, _get_var( $s, $s->{arg}[$_], $global );
		$global = 0;
	}

	$s->{output} .= sprintf( $pattern, @args );
	return $s->{arg}[2];
}

# -------------------------
sub _opCall {
	my $s = shift;

	my $callname = _get_var( $s, $s->{arg}[3] );
	die "Unknown Call '$callname' " . _linenum( $s, $s->{arg}[0] )
	 unless ( exists $s->{self}{_CALLS}{$callname} );

	die "Call '$callname' is not a coderef " . _linenum( $s, $s->{arg}[0] )
	 unless ( ref $s->{self}{_CALLS}{$callname} eq 'CODE' );

	my @args;
	my $global = 0;
	for ( 4..$#{ $s->{arg} } ) {
		$s->{arg}[$_] =~ $RE_GLOBAL_OPT and $global = 1 and next;
		push @args,
		 ( $s->{arg}[$_] =~ m/^\$/ )?
		 _get_var( $s, $s->{arg}[$_], $global ) : $s->{arg}[$_] ;
		$global = 0;
	}

	$s->{output} .= &{ $s->{self}{_CALLS}{$callname} }( @args );
	return $s->{arg}[2];
}

# -------------------------
sub _opStartblock {
	my $s = shift;

	my $blocktype = $s->{arg}[3];
	return &{ $blockmap[$blocktype] }( $s );
}

# -------------------------
sub _opEndblock {
	my $s = shift;

	my $op = $s->{arg}[3];
	if ( $op == BLOCK_ELSE ) {
		return $s->{arg}[2];
	}
	return ( $s->{arg}[2], 1 );
}

# -------------------------
sub _blockIf {
	my $s = shift;

	if ( _do_test( $s ) ) {
		my ( $ret, $jump ) = $s->{self}->_process_commands(
			$s->{stack}, $s->{pa}, $s->{cursor} + 1
		);
		$s->{output} .= $ret;
		return $jump;
	}
	return $s->{arg}[2];
}

# -------------------------
sub _blockNotif {
	my $s = shift;

	unless ( _do_test( $s ) ) {
		my ( $ret, $jump )
		 = $s->{self}->_process_commands( $s->{stack}, $s->{pa}, $s->{cursor} + 1 );
		$s->{output} .= $ret;
		return $jump;
	}
	return $s->{arg}[2];
}

# -------------------------
sub _blockElse {
	my $s = shift;
	return $s->{arg}[2];
}

# -------------------------
sub _blockLoop {
	my $s = shift;

	my $global = ( $#{ $s->{arg} } > 4 and $s->{arg}[5] == GLOBAL_VAR ) ? 1 : 0;
	my $list = _get_var( $s, $s->{arg}[4], $global );
	die "'$list' is not an ARRAY ref " . _linenum( $s, $s->{arg}[0] )
	 if ( not ref $list or ref $list ne 'ARRAY' );

	my $count = 0;
	my $top = $#{ $list };
	for my $item ( @$list ) {
		# anon arrays
		if ( ref $item eq '' ) {
			$item = { __anon__ => $item };
		}
		elsif ( ref $item eq 'SCALAR' ) {
			$item = { __anon__ => $$item };
		}

		# insert loop data tags
		$item->{'__count__'} = $count + 1;
		$item->{'__index__'} = $count;
		$item->{'__first__'} = ( $count == 0 ) ? 1 : 0;
		$item->{'__last__'}  = ( $count == $top ) ? 1 : 0;
		$item->{'__inner__'} = ( $count != 0 and $count != $top ) ? 1 : 0;
		$item->{'__outer__'} = !$item->{'__inner__'};
		$item->{'__even__'}  = ( $count % 2 ) ? 1 : 0;
		$item->{'__odd__'}   = !$item->{'__even__'};

		my ( $ret, $jump )
		 = $s->{self}->_process_commands( $s->{stack}, $item, $s->{cursor} + 1 );
		$s->{output} .= $ret;
		$count++;
	}

	return $s->{arg}[2];
}

# -------------------------
sub _blockRandom {
	my $s = shift;

	my $global = ( $#{ $s->{arg} } > 4 and $s->{arg}[5] == GLOBAL_VAR ) ? 1 : 0;
	my $list = _get_var( $s, $s->{arg}[4], $global );
	die "'$list' is not an ARRAY ref " . _linenum( $s, $s->{arg}[0] )
	 if ( not ref $list or ref $list ne 'ARRAY' );

	die "Empty list for random " . _linenum( $s, $s->{arg}[0] )
	 unless @$list;

	my $index = int( rand( scalar @$list ) );
	my $item = $list->[$index];

	# anon arrays
	if ( ref $item eq '' ) {
		$item = { __anon__ => $item };
	}
	elsif ( ref $item eq 'SCALAR' ) {
		$item = { __anon__ => $$item };
	}

	$item->{'__count__'} = $index + 1;
	$item->{'__index__'} = $index;

	my ( $ret, $jump )
	 = $s->{self}->_process_commands( $s->{stack}, $item, $s->{cursor} + 1 );
	$s->{output} .= $ret;

	return $s->{arg}[2];
}

# -------------------------
sub _blockDice {
	my $s = shift;

	my $expr = $s->{arg}[4];
	my ($count, $sides, $mod) = $expr =~ /^(\d+)d(\d+)([+-]\d+)?$/;
	$mod //= 0;

	my $total = 0;
	for ( 1 .. $count ) {
		$total += int( rand($sides) ) + 1;
	}
	$total += $mod;

	$s->{output} .= $total;
	return $s->{arg}[2];
}

# -------------------------
sub _blockMap {
	my $s = shift;

	my $global = ( $#{ $s->{arg} } > 4 and $s->{arg}[5] == GLOBAL_VAR ) ? 1 : 0;
	my $var = _get_var( $s, $s->{arg}[4], $global );
	die "$s->{arg}[4] = '$var' and is not an HASH ref nor a ARRAY ref " . _linenum( $s, $s->{arg}[0] )
	 if ( not ref $var or ref $var !~ $RE_HASH_ARRAY );

	my ( $ret, $jump )
	 = $s->{self}->_process_commands( $s->{stack}, $var, $s->{cursor} + 1 );
	$s->{output} .= $ret;

	return $jump;
}

# -------------------------
sub _blockFormat {
	my $s = shift;

	require Compost::Template::Format;
	my $format = $s->{arg}[4];
	die "'$format' is not an known format " . _linenum( $s, $s->{arg}[0] )
	 unless ( Compost::Template::Format->isKnown( $format ) );

	my @args;
	if ( scalar @{ $s->{arg} } > 4 ) {
		@args = @{ $s->{arg} }[ 5 .. $#{ $s->{arg} } ];
	}

	my ( $ret, $jump )
	 = $s->{self}->_process_commands( $s->{stack}, $s->{pa}, $s->{cursor} + 1 );
	$s->{output} .= Compost::Template::Format->format( $ret, $format, @args);

	return $jump;
}

# -------------------------
sub _blockState {
	my $s = shift;

	my $key = $s->{arg}[4];
	return $s->{arg}[2]
	 unless ( exists $s->{self}{CONFIG}{State}{$key} );

	my $state = $s->{self}->{CONFIG}{State}{$key};
	my $val   = $s->{arg}[5];
	my $match = ( $val =~ s/^\!// ) ? 0 : 1;
	my $test  = ( $state =~ m/^$val$/ ) ? 1 : 0;

	if ( $match == $test ) {
		my ( $ret, $jump )
		 = $s->{self}->_process_commands( $s->{stack}, $s->{pa}, $s->{cursor} + 1 );
		$s->{output} .= $ret;
	}
	return $s->{arg}[2];
}

# -------------------------
sub _testNot {
	my ( $s, $args ) = @_;
	my $test = shift @{ $args };
	return ( &{ $testmap[$test] }( $s, $args ) ) ? 0 : 1;
}

# -------------------------
sub _testDefined {
	my ( $s, $args ) = @_;
	my $ret = _get_var( $s, $args->[0], 0 );
	return ( $ret ) ? 1 : 0;
}

# -------------------------
sub _testEquals {
	my ( $s, $args ) = @_;

	my $var1 = _get_var( $s, $args->[0], 0 );
	my $var2 = _get_var( $s, $args->[1], 0 );
	return 0 if !defined $var1 || !defined $var2;
	return ( $var1 eq $var2 ) ? 1 : 0;
}

# -------------------------
sub _testGt {
	my ( $s, $args ) = @_;
	my $var1 = _get_var( $s, $args->[0], 0 );
	my $var2 = _get_var( $s, $args->[1], 0 );
	return ( defined $var1 && defined $var2 && $var1 gt $var2 ) ? 1 : 0;
}

# -------------------------
sub _testGte {
	my ( $s, $args ) = @_;
	my $var1 = _get_var( $s, $args->[0], 0 );
	my $var2 = _get_var( $s, $args->[1], 0 );
	return ( defined $var1 && defined $var2 && $var1 ge $var2 ) ? 1 : 0;
}

# -------------------------
sub _testLt {
	my ( $s, $args ) = @_;
	my $var1 = _get_var( $s, $args->[0], 0 );
	my $var2 = _get_var( $s, $args->[1], 0 );
	return ( defined $var1 && defined $var2 && $var1 lt $var2 ) ? 1 : 0;
}

# -------------------------
sub _testLte {
	my ( $s, $args ) = @_;
	my $var1 = _get_var( $s, $args->[0], 0 );
	my $var2 = _get_var( $s, $args->[1], 0 );
	return ( defined $var1 && defined $var2 && $var1 le $var2 ) ? 1 : 0;
}

# ====================================================
# helper subs

# -------------------------
sub _linenum {
	my ( $s, $db ) = @_;

	$db =~ m/^\[(\d+)\:(\d+)\]$/
	 or die "Bad debug info '$db'";

	my $f = ( exists $s->{_INCLUDE_FILES} ) ?
	 $s->{_INCLUDE_FILES}[$1] : $s->{CONFIG}{filename};
	return " at $f:$2\n"
}

# -------------------------
sub _get_var {
	my ( $s, $name, $global ) = @_;

	# anon arrays
	if ( $name eq '$_' ) {
		die "Anon array item called, but not found " . _linenum( $s, $s->{arg}[0] )
		 unless ( exists $s->{pa}{__anon__} );
		return $s->{pa}{__anon__}
	}

	return $name
	 unless ( $name =~ s/^\$\b(\w+)/$1/ );
	my $basename = $1;

	my $tmpref;
	if ( $global == 0 ) {
		if ( exists $s->{pa}{ $basename } ) {
			$tmpref = $s->{pa}{ $basename };
		}
	}
	else {
		if ( exists $s->{global}{ $basename } ) {
			$tmpref = $s->{global}{ $basename };
		}
	}
	return $tmpref unless ( $name =~ m/\./ );

	# handle complex names
	my @parts = split( /\./, $name );
	shift @parts;  # we've already got the base
	for my $p ( @parts ) {
		die "Deep link is empty string in '\$$name' " . _linenum( $s, $s->{arg}[0] )
		 if ( $p eq '' );

		if ( ref $tmpref ) {
			my $type = ref $tmpref;
			if ( $type =~ $RE_ARRAY_REF ) {
				die "Attempting to access an array with '$p' " . _linenum( $s, $s->{arg}[0] )
				 unless ( $p =~ $RE_NUMERIC );

				die "'$p' out of bounds in array '\$$name' " . _linenum( $s, $s->{arg}[0] )
				 unless ( $p < scalar @{ $tmpref } );

				$tmpref = $tmpref->[$p];
				next;
			}
			elsif ( $type =~ m/HASH/ ) {
				die "Deep link '$p' in '\$$name' does not exist " . _linenum( $s, $s->{arg}[0] )
				 unless exists $tmpref->{$p};
				$tmpref = $tmpref->{$p};
				next;
			}
			else {
				die "No handler for '$p' in $type '\$$name' " . _linenum( $s, $s->{arg}[0] );
			}
		}
		else {
			return $tmpref;
		}
	}

	return $tmpref;
}

# -------------------------
# general conditional testing
sub _do_test {
	my $s = shift;

	my @args = @{ $s->{arg} };
	splice( @args, 0, 4 );   # get rid of op, jump & block
	my $test = shift @args;

	return &{ $testmap[$test] }( $s, \@args );
}

1;
