package Compost::Template::Runtime;

# see Compost::Template.pod

package Compost::Template;

use strict;
use warnings;
use 5.014;
use autodie;

use Compost::Template::Constants qw(:all);
use Compost::Template::Misc;

our $VERSION = '0.4.0';

# keep in sync with Compost::Template::Parser
# Index = opcode value (see Constants.pm)
my @opmap = (
	undef,          # OP_CONFIG (0) - not a runtime op
	\&_opData,      # OP_DATA (1)
	\&_opVar,       # OP_VAR (2)
	\&_opPrintf,    # OP_PRINTF (3)
	\&_opCall,      # OP_CALL (4)
	\&_opStartblock, # OP_STARTBLOCK (5)
	\&_opEndblock,  # OP_ENDBLOCK (6)
	undef,          # OP_FINISH (7) - handled by early return
	undef,          # OP_EXTENDS (8) - handled at parse time
	\&_opSuper,     # OP_SUPER (9)
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
	\&_blockBlock,
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
my $RE_ARRAY_REF  = qr/ARRAY/;
my $RE_HASH_ARRAY = qr/HASH|ARRAY/;
my $RE_NUMERIC    = qr/^\d+$/;

# -------------------------------------------------------------------
sub _process_commands {
	my ( $self, $stack, $pa, $cursor, $output_ref ) = @_;

	my $output = defined $output_ref ? $output_ref : [];
	my $state = {
		self   => $self,
		stack  => $stack,
		cursor => $cursor,
		pa     => $pa,     # params
		output => $output,
		global => {},
		arg    => [],
	};
	$state->{global} = $self->{_PARAMS};

	while ( 1 ) {
		$state->{arg} = $state->{stack}[ $state->{cursor} ];

		$DEBUG and print "$state->{cursor}: " . join( ' ', @{ $state->{arg} } ) . "\n";

		my $op = $state->{arg}[1];
		return join( '', @{ $state->{output} } ) if $op == OP_FINISH;

		# mode: normal, next, endblock, finish
		my ( $jump, $mode ) = &{ $opmap[$op] }( $state );
		( defined $mode and $mode == 1 ) and return ( join( '', @{ $state->{output} } ), $jump );
		$state->{cursor} = $jump;
	}
}

# -------------------------
sub _opData {
	my $s = shift;

	defined $s->{arg}[3]
     and push @{ $s->{output} }, $s->{arg}[3];
	return $s->{arg}[2];
}

# -------------------------
sub _opVar {
	my $s = shift;

	my $name = $s->{arg}[3];
	my $path_count = $s->{arg}[4] // 0;
	my @path_parts = $path_count ? @{ $s->{arg} }[ 5 .. 4 + $path_count ] : ();

	my %options;
	my $opt_start = 5 + $path_count;
	if ( scalar @{ $s->{arg} } > $opt_start ) {
		my $c = $opt_start;
		while ( $c < scalar @{ $s->{arg} } ) {
			my $opt = $s->{arg}[$c++];
			die "Bad var option '$opt'" . _linenum( $s, $s->{arg}[0] )
			 if ( $opt > $#varmap );
			$options{ $varmap[ $opt ]  } = 1;
		}
	}

	my $global = ( exists $options{global} ) ? 1 : 0;
	my $var = _get_var( $s, $name, $global, \@path_parts );
	unless ( defined $var ) {
		return $s->{arg}[2]
		 if ( $s->{self}{CONFIG}{die_on_bad_params} == 0
		 or exists $options{shrug} );
		die "Error: undefined var '$name' " . _linenum( $s, $s->{arg}[0] )
	}

	if ( exists $options{html} ) {
		$var = Compost::Template::Misc::htmlize( $var );
	}
	if ( exists $options{url} ) {
		$var = Compost::Template::Misc::url_encode( $var );
	}
	push @{ $s->{output} }, $var;

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

	push @{ $s->{output} }, sprintf( $pattern, @args );
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

	push @{ $s->{output} }, &{ $s->{self}{_CALLS}{$callname} }( @args );
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
sub _opSuper {
	my $s = shift;

	# Execute parent's default block body if available
	if ( exists $s->{self}{_SUPER_BODY} and defined $s->{self}{_SUPER_BODY} ) {
		my ( $ret, undef ) = $s->{self}->_process_commands(
			$s->{self}{_SUPER_BODY}, $s->{pa}, 0
		);
		push @{ $s->{output} }, $ret;
	}

	return $s->{arg}[2];
}

# -------------------------
sub _blockIf {
	my $s = shift;

	if ( _do_test( $s ) ) {
		my ( $ret, $jump ) = $s->{self}->_process_commands(
			$s->{stack}, $s->{pa}, $s->{cursor} + 1
		);
		push @{ $s->{output} }, $ret;
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
		push @{ $s->{output} }, $ret;
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

	my $list = _get_loop_list( $s );
	my $total = scalar @$list;

	my $count = 0;
	for my $item ( @$list ) {
		$item = _wrap_anon_item( $item );
		_set_loop_vars( $item, $count, $total );

		$s->{self}->_process_commands( $s->{stack}, $item, $s->{cursor} + 1, $s->{output} );
		$count++;
	}

	return $s->{arg}[2];
}

# -------------------------
sub _blockRandom {
	my $s = shift;

	my $list = _get_loop_list( $s );

	die "Empty list for random " . _linenum( $s, $s->{arg}[0] )
	 unless @$list;

	my $index = int( rand( scalar @$list ) );
	my $item = _wrap_anon_item( $list->[$index] );
	_set_loop_vars( $item, $index, scalar @$list );

	$s->{self}->_process_commands( $s->{stack}, $item, $s->{cursor} + 1, $s->{output} );

	return $s->{arg}[2];
}

# -------------------------
sub _blockDice {
	my $s = shift;

	my $expr = $s->{arg}[4];

	# letter dice: Nd[ABHXxa] - concatenate results
	if ( $expr =~ /^(\d+)d([ABHXxa])$/ ) {
		my ( $count, $type ) = ( $1, $2 );
		my $result = '';
		for ( 1 .. $count ) {
			if ( $type eq 'B' ) {
				$result .= int( rand(2) );
			}
			elsif ( $type eq 'X' ) {
				$result .= sprintf( '%X', int( rand(16) ) );
			}
			elsif ( $type eq 'x' ) {
				$result .= sprintf( '%x', int( rand(16) ) );
			}
			elsif ( $type eq 'A' ) {
				$result .= chr( 65 + int( rand(26) ) );
			}
			elsif ( $type eq 'a' ) {
				$result .= chr( 97 + int( rand(26) ) );
			}
		}
		push @{ $s->{output} }, $result;
		return $s->{arg}[2];
	}

	# numeric dice: NdS+/-M - sum results
	my ($count, $sides, $mod) = $expr =~ /^(\d+)d(\d+)([+-]\d+)?$/;
	$mod //= 0;

	my $total = 0;
	for ( 1 .. $count ) {
		$total += int( rand($sides) ) + 1;
	}
	$total += $mod;

	push @{ $s->{output} }, $total;
	return $s->{arg}[2];
}

# -------------------------
sub _blockBlock {
	my $s = shift;

	my $name = $s->{arg}[4];

	# Check if there's a child override for this block
	if ( exists $s->{self}{_BLOCK_BODIES} and exists $s->{self}{_BLOCK_BODIES}{$name} ) {
		# Set up super context so _opSuper can find the parent body
		# Store on $self so it's accessible from nested _process_commands calls
		my $parent_body = undef;
		if ( exists $s->{self}{_PARENT_BLOCK_BODIES} and exists $s->{self}{_PARENT_BLOCK_BODIES}{$name} ) {
			$parent_body = $s->{self}{_PARENT_BLOCK_BODIES}{$name};
		}
		$s->{self}{_SUPER_BODY} = $parent_body;

		my $child_body = $s->{self}{_BLOCK_BODIES}{$name};
		my ( $ret, undef ) = $s->{self}->_process_commands(
			$child_body, $s->{pa}, 0
		);
		push @{ $s->{output} }, $ret;

		$s->{self}{_SUPER_BODY} = undef;
		return $s->{arg}[2];
	}

	# No child override - execute parent's default block body
	my ( $ret, $jump ) = $s->{self}->_process_commands(
		$s->{stack}, $s->{pa}, $s->{cursor} + 1
	);
	push @{ $s->{output} }, $ret;
	return $jump;
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
	push @{ $s->{output} }, $ret;

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
	push @{ $s->{output} }, Compost::Template::Format->format( $ret, $format, @args);

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
		push @{ $s->{output} }, $ret;
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
sub _testCompare {
	my ( $s, $args, $op ) = @_;
	my $var1 = _get_var( $s, $args->[0], 0 );
	my $var2 = _get_var( $s, $args->[1], 0 );
	return 0 if !defined $var1 || !defined $var2;
	if    ( $op eq 'eq' ) { return ( $var1 eq $var2 ) ? 1 : 0 }
	elsif ( $op eq 'ne' ) { return ( $var1 ne $var2 ) ? 1 : 0 }
	elsif ( $op eq 'gt' ) { return ( $var1 gt $var2 ) ? 1 : 0 }
	elsif ( $op eq 'ge' ) { return ( $var1 ge $var2 ) ? 1 : 0 }
	elsif ( $op eq 'lt' ) { return ( $var1 lt $var2 ) ? 1 : 0 }
	elsif ( $op eq 'le' ) { return ( $var1 le $var2 ) ? 1 : 0 }
	return 0;
}

sub _testEquals { return _testCompare( $_[0], $_[1], 'eq' ) }
sub _testGt     { return _testCompare( $_[0], $_[1], 'gt' ) }
sub _testGte    { return _testCompare( $_[0], $_[1], 'ge' ) }
sub _testLt     { return _testCompare( $_[0], $_[1], 'lt' ) }
sub _testLte    { return _testCompare( $_[0], $_[1], 'le' ) }

# ====================================================
# helper subs

# -------------------------
sub _get_loop_list {
	my ( $s ) = @_;

	my $global = ( $#{ $s->{arg} } > 4 and $s->{arg}[5] == GLOBAL_VAR ) ? 1 : 0;
	my $list = _get_var( $s, $s->{arg}[4], $global );
	die "'$list' is not an ARRAY ref " . _linenum( $s, $s->{arg}[0] )
	 if ( not ref $list or ref $list ne 'ARRAY' );

	return $list;
}

# -------------------------
sub _wrap_anon_item {
	my ( $item ) = @_;

	if ( ref $item eq '' ) {
		return { __anon__ => $item };
	}
	elsif ( ref $item eq 'SCALAR' ) {
		return { __anon__ => $$item };
	}
	return $item;
}

# -------------------------
sub _set_loop_vars {
	my ( $item, $index, $total ) = @_;

	$item->{'__count__'} = $index + 1;
	$item->{'__index__'} = $index;
	$item->{'__total__'} = $total;
	$item->{'__first__'} = ( $index == 0 ) ? 1 : 0;
	$item->{'__last__'}  = ( $index == $total - 1 ) ? 1 : 0;
	$item->{'__inner__'} = ( $index != 0 and $index != $total - 1 ) ? 1 : 0;
	$item->{'__outer__'} = !$item->{'__inner__'};
	$item->{'__even__'}  = ( $index % 2 ) ? 1 : 0;
	$item->{'__odd__'}   = !$item->{'__even__'};
}

# -------------------------
sub _linenum {
	my ( $s, $db ) = @_;

	$db =~ m/^\[(\d+)\:(\d+)\]$/
	 or die "Bad debug info '$db'";

	my $f = ( exists $s->{self}{_INCLUDE_FILES} ) ?
	 $s->{self}{_INCLUDE_FILES}[$1] : $s->{self}{CONFIG}{filename};
	return " at $f:$2\n"
}

# -------------------------
sub _get_var {
	my ( $s, $name, $global, $path_parts ) = @_;

	# anon arrays
	if ( $name eq '$_' ) {
		die "Anon array item called, but not found " . _linenum( $s, $s->{arg}[0] )
		 unless ( exists $s->{pa}{__anon__} );
		return $s->{pa}{__anon__}
	}

	# magic variables
	if ( $name eq '$__line__' or $name eq '$__file__' ) {
		$s->{arg}[0] =~ m/^\[(\d+)\:(\d+)\]$/
		 or die "Bad debug info '$s->{arg}[0]'";
		if ( $name eq '$__line__' ) {
			return $2;
		}
		else {
			my $f = '';
			if ( exists $s->{self}{_INCLUDE_FILES} and defined $s->{self}{_INCLUDE_FILES}[$1] ) {
				$f = $s->{self}{_INCLUDE_FILES}[$1];
			}
			elsif ( defined $s->{self}{CONFIG}{filename} and $s->{self}{CONFIG}{filename} ne '' ) {
				$f = $s->{self}{CONFIG}{filename};
			}
			return $f || '(template)';
		}
	}
	if ( $name eq '$__time__' ) {
		return time;
	}
	if ( $name eq '$__user__' ) {
		return $ENV{USER} || $ENV{LOGNAME} || '(unknown)';
	}
	if ( $name eq '$__version__' ) {
		return $Compost::Template::VERSION;
	}

	return $name
	 unless ( $name =~ s/^\$\b(\w+)/$1/ );

	# use pre-compiled path parts if available
	if ( defined $path_parts and @$path_parts ) {
		my $basename = $path_parts->[0];
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

		for my $i ( 1 .. $#$path_parts ) {
			my $p = $path_parts->[$i];
			die "Deep link is empty string in '\$$name' " . _linenum( $s, $s->{arg}[0] )
			 if ( $p eq '' );

			last unless ref $tmpref;
			my $type = ref $tmpref;
			if ( $type =~ $RE_ARRAY_REF ) {
				die "Attempting to access an array with '$p' " . _linenum( $s, $s->{arg}[0] )
				 unless ( $p =~ $RE_NUMERIC );
				die "'$p' out of bounds in array '\$$name' " . _linenum( $s, $s->{arg}[0] )
				 unless ( $p < scalar @{ $tmpref } );
				$tmpref = $tmpref->[$p];
			}
			elsif ( $type =~ m/HASH/ ) {
				die "Deep link '$p' in '\$$name' does not exist " . _linenum( $s, $s->{arg}[0] )
				 unless exists $tmpref->{$p};
				$tmpref = $tmpref->{$p};
			}
			else {
				die "No handler for '$p' in $type '\$$name' " . _linenum( $s, $s->{arg}[0] );
			}
		}
		return $tmpref;
	}

	# fallback: legacy path (no pre-compiled parts)
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

	my @parts = split( /\./, $name );
	shift @parts;
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
