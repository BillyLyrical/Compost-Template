package Compost::Template::Parser;

# See Compost::Template.pod for documentation

use strict;
use warnings;
#use diagnostics;

use Compost::Template;
use Compost::Template::Misc;

our $VERSION = '0.07';

package Compost::Template;
# keep in sync with Compost::Template::Runtime;

my %parsemap = (
	data       => \&_badCall,
	var        => \&_doVar,
	if         => \&_doIf,
	unless     => \&_doUnless,
	loop       => \&_doLoop,
	counter    => \&_doCounter,
	map        => \&_doMap,
	switch     => \&_doSwitch,
	prefix     => \&_badCall,
	insert     => \&_badCall,
	call       => \&_doCall,
	printf     => \&_doPrintf,
	format     => \&_doFormat,
	state      => \&_doState,
	ignore     => \&_doIgnore,
	FINISH     => \&_doFinish,
);

#my @opmap    = qw{ FINISH data var printf call startblock endblock   };
my @opmap    = qw{ FINISH data var printf call startblock endblock   };
my @blockmap = qw{ notif if else loop insert prefix map format state };

sub _badCall {
	die "BAD CALL from parsemap";
}

my $DEBUG = 0;

# -------------------------------------------------------------------
# $data is a ref to a string
sub _parse {
	my ( $self, $data ) = @_;

	my $depth = $self->{CONFIG}{max_depth};
	while ( $$data =~ m/<%[+-]?\s+\[\d+\:\d+\]\s+include\s+\S+?\s+(-shrug\s+)?[+-]?%>/ ) {

		die "Illegal attempt to use Includes"
		 if $self->{CONFIG}{no_includes};

		die "Maximum recursion depth reached"
		 if ( $depth-- == 0 ); 

		# the 'nop's are there to conserve whitespace swallowing
		$$data =~ s{
			(<%[+-]?)\s+       # $1
			(\[\d+\:\d+\])\s+  # $2
			include            # keyword
			\s+(\S+?)\s+       # $3
			((\-shrug)\s+)?    # $4 $5
			([+-]?%>)          # $6
		}{
			my $f = $self->_include( $3, $5 || 0, $2 );
			"$1 $2 nop \%>${ $f }<\% $2 nop $6"
		}smexg;
	}

	die "Template has zero length"
	 unless ( length $$data );
	_trim( $data );
	_expand_syntactic_sugar( $data );

	my $global_state = {
		chunks => [ split /(<%\s.+?\s%>)/s, $$data . '<% [0:0] FINISH %>' ],
		self   => $self,
		stack  => [],
		ignore => 0,     # if ignore is on
		block  => [],    # current blocktype stack
	};

	_process_tokens( $global_state, -1 );
	return $global_state->{stack};
}

# -------------------------
sub _trim {
	my $data = shift;

	$$data =~ s{\s*\-%>\s*} { %>}g;
	$$data =~ s{\s*<%\-\s*} {<% }g;
	$$data =~ s{\s*\+%>\s*} { %> }g;
	$$data =~ s{\s*<%\+\s*} { <% }g;
}

# useful parsing vars
my $ST = '<%\s+(\[\d+\:\d+\])';  # start of tag + debug info
my $ET = '\s*%>';                # end of tag
my $OT = '\s*(\-\w+)\s*';        # -options
my $DQ = '\"([^\"]*)\"';         # double quotes
my $SQ = "\\'([^\\']*)\\'";      # single quotes
my $VR = '(\$\w+)';              # variable

# -------------------------
sub _expand_syntactic_sugar {
	my $data = shift;

	# 'nop' is removed
	$$data =~ s{$ST\s*nop$ET} {}smgo;

	# comments - another sort of nop
	$$data =~ s{$ST\s*\#.*?$ET} {}smgo;

	# "or" in $var tags
	# FIXME: parsing like this makes it hard to report syntactic errors
	$$data =~ s{
		$ST\s+                      # start of tag + debug info
		($DQ|$SQ|$VR)               # some var or quoted thing
		((\s+or\s+($DQ|$SQ|$VR))+)  # or more vars, quoted bits
		(($OT)*)                    # -options
		$ET                         # end of tag ";
	}{
		my ( $buf, $d, $v1, $ors, $opts ) = ( '', $1, $2, $6, $12 || '' );
		my $e = ( $opts eq '' )? '%>' : $opts . '%>'; 
		$buf =  "<% $d if $v1 -shrug %><% $d $v1 $e"
		 . _or_vars( $d, $ors, $opts );
		$buf;
	}smgoex;

	# exact insertion ( $1 is in $ST, $2 is in $SQ )
	$$data =~ s{$ST\s*$SQ$ET} {$2}smgo;

	# interpolated insertion ( $1 is in $ST, $2 is in $DQ )
	$$data =~ s{$ST\s*$DQ$ET} {
		my ( $d, $r ) = ( $1, $2 );
		$r =~ s/$VR/<% $d $1 %>/g; # $1 is in $VR
		$r;
	}smgoex;

	$DEBUG and print $$data, "\n";
}

# -------------------------------------------------------------------
sub _or_vars {
	my ( $d, $buf, $opts ) = @_;
	my $op = $opts . '%>';

	$buf =~ s{^\s+or\s+($DQ|$SQ|$VR)}{}smo;
	my $got = $1;
	$op = '%>' if ( $got =~ m/^($DQ|$SQ)$/smo ); 

 	if ( $buf eq '' ) { # end of the line, unroll recursion  
		return "<% $d else %><% $d $got $op<% $d /if %>";
	}
	else {
		return "<% $d elsif $got -shrug %><% $d $got $op"
		 . _or_vars( $d, $buf, $opts );
	}
}

# -------------------------------------------------------------------
sub _process_tokens {
	my $gs = shift;

	# local block state
	my $bs = {
		chunk  => '',  # whole tag - good for warnings
		tag    => '',  # actual key word
		arg    => [],  # args to tag
		opt    => {},  # tag options
		debug  => '',  # debug info ( filename, line number )
        gs     => $gs, # pointer to global state
	};

	while ( scalar @{ $gs->{chunks} } ) {
		$bs->{chunk} = shift @{ $gs->{chunks} };
		next if ( !defined $bs->{chunk} or $bs->{chunk} eq '' );

		$DEBUG and print "$bs->{chunk}\n";

		# not a command, output as is
		unless ( $bs->{chunk} =~ m/^<%/ ) {
			_push_stack( $gs, '[0:0]', OP_DATA, 'JUMP_NEXT', $bs->{chunk} );
			next;
		}

		@{ $bs->{arg} } = grep { !/(^<%|%>|\-\w+$)/ } split /\s+/, $bs->{chunk};
        $bs->{opt} = {};
		map{ $bs->{opt}{$_} = 1 } grep { /^\-\w+$/ } split /\s+/, $bs->{chunk};

		#$bs->{debug} = $gs->{self}->_debug( shift @{ $bs->{arg} } );
		$bs->{debug} = shift @{ $bs->{arg} };
		$bs->{chunk} =~ s/\[\d+\:\d+\]//;

		die "No tags in '$bs->{chunk}' " . _debug( $bs )
		 unless scalar @{ $bs->{arg} };

		$bs->{tag} = ( $bs->{arg}[0] =~ m/^\$\b\w/ ) ? 'var' : shift @{ $bs->{arg} };

		# end of block?
		if ( $bs->{tag} =~ m{^(/\w+|elsif|else|when)$} ) {
			return $bs;
		}
		else {
			die "Unknown tag '$bs->{tag}' in '$bs->{chunk}' " . _debug( $bs )
			 unless ( exists $parsemap{ $bs->{tag} } );

			&{ $parsemap{ $bs->{tag} } }( $gs, $bs );
		}
	}
	return 0;
}

# -------------------------
# handy - returns index
sub _push_stack {
	my ( $gs, $db, $op, $jumpnext, @args ) = @_;

	if ( $jumpnext eq 'JUMP_NEXT' ) {
		$jumpnext = scalar @{ $gs->{stack} } + 1;
	}

	push @{ $gs->{stack} }, [ $db, $op, $jumpnext, @args ];
	return $#{ $gs->{stack} };
}

# -------------------------
# tidy up block jumps
sub _tidy_jump {
	my ( $gs, $pos, $expected, $replacement ) = @_;

	die "Unexpected Jump var '$gs->{stack}[$pos][2]'"
	 . " in stack \#${pos}\n (expected $expected)"
	 unless ( $gs->{stack}[$pos][2] eq $expected );

	$replacement = scalar @{ $gs->{stack} }
	 if ( $replacement eq 'NEXT' );

	$gs->{stack}[$pos][2] = $replacement;
}

# -------------------------
# insert variable
#    gs = global stack
#    bs = block stack
sub _doVar {
	my ( $gs, $bs ) = @_;

	my $name = shift @{ $bs->{arg} };
	die "Bad variable '$name' in $bs->{chunk} " . _debug( $bs )
	 unless ( $name =~ m/^\$\b\w/ );
	my @param = ( $name );

#print (exists $bs->{opt}{-global} )?  "Global" : "Local";
#print $param[0] . "\n";
	exists $bs->{opt}{-global} and push @param, GLOBAL_VAR;
	exists $bs->{opt}{-html}   and push @param, ESCAPE_HTML;
	exists $bs->{opt}{-url}    and push @param, ESCAPE_URL;
	exists $bs->{opt}{-shrug}  and push @param, VAR_SHRUG;
	_push_stack( $gs, $bs->{debug}, OP_VAR, 'JUMP_NEXT', @param );

	return 0;
}

# -------------------------
# if statement
sub _doIf {
	my ( $gs, $bs ) = @_;

	my @elses;
	my $prev   = _push_stack( $gs, $bs->{debug}, OP_STARTBLOCK, 'JUMP_ELSE', BLOCK_IF, _get_test( $bs ) );
	my $newbs  = _process_tokens( $gs );
	push @elses, _push_stack( $gs, $bs->{debug}, OP_ENDBLOCK, 'JUMP_END', BLOCK_IF );

	while ( $newbs->{tag} eq 'elsif' ) {
		my $top = _push_stack( $gs, $bs->{debug}, OP_STARTBLOCK, 'JUMP_ELSE', BLOCK_IF, _get_test( $newbs ) );
		_tidy_jump( $gs, $prev, 'JUMP_ELSE', $top );
		$prev = $top;
		$newbs = _process_tokens( $gs );
		push @elses, _push_stack( $gs, $bs->{debug}, OP_ENDBLOCK, 'JUMP_END', BLOCK_IF );
	}

	if ( $newbs->{tag} eq 'else' ) {
		my $top = _push_stack( $gs, $bs->{debug}, OP_STARTBLOCK, 'JUMP_NEXT', BLOCK_ELSE );
		_tidy_jump( $gs, $prev, 'JUMP_ELSE', $top );
		$newbs = _process_tokens( $gs );
		_push_stack( $gs, $bs->{debug}, OP_ENDBLOCK, 'JUMP_NEXT', BLOCK_ELSE );
	}
	else {
		_tidy_jump( $gs, $prev, 'JUMP_ELSE', 'NEXT' );
	}

	die "Bad end to if block '$newbs->{tag}' " . _debug( $bs )
	 unless ( $newbs->{tag} eq '/if' );

	for ( @elses ) {
		_tidy_jump( $gs, $_, 'JUMP_END', 'NEXT' );
	}
}

# -------------------------
# unless statement
sub _doUnless {
	my ( $gs, $bs ) = @_;
	my @elses;

	my $prev  = _push_stack( $gs, $bs->{debug}, OP_STARTBLOCK, 'JUMP_ELSE', BLOCK_NOTIF, _get_test( $bs ) );
	my $newbs = _process_tokens( $gs );
	push @elses, _push_stack( $gs, $bs->{debug}, OP_ENDBLOCK, 'JUMP_END', BLOCK_NOTIF );
	_tidy_jump( $gs, $prev, 'JUMP_ELSE', 'NEXT' );

	if ( $newbs->{tag} eq 'else' ) {
		_push_stack( $gs, $bs->{debug}, OP_STARTBLOCK, 'JUMP_NEXT', BLOCK_ELSE );
		$newbs = _process_tokens( $gs );
		_push_stack( $gs, $bs->{debug}, OP_ENDBLOCK, 'JUMP_NEXT', BLOCK_ELSE );
	}

	die "Bad end to unless block '$newbs->{tag}' " . _debug( $bs )
	 unless ( $newbs->{tag} eq '/unless' );

	for ( @elses ) {
		_tidy_jump( $gs, $_, 'JUMP_END', 'NEXT' );
	}
}

# -------------------------
# for loop
sub _doLoop {
	my ( $gs, $bs ) = @_;

	die "No Token name in '$bs->{chunk}' " . _debug( $bs )
	  unless scalar @{ $bs->{arg} };

	my $name = shift @{ $bs->{arg} };
	die "Bad variable name '$name' " . _debug( $bs )
	 unless ( $name =~ m/^\$\b\w+/ );

	my $start = _push_stack( $gs, $bs->{debug}, OP_STARTBLOCK, 'JUMP_END', BLOCK_LOOP, $name );
	my $newbs = _process_tokens( $gs );

	die "Bad end to loop block '$newbs->{tag}' " . _debug( $bs )
	 unless ( $newbs->{tag} eq '/loop' );

	my $end   = _push_stack( $gs, $bs->{debug}, OP_ENDBLOCK, 'JUMP_NEXT', BLOCK_LOOP );
	_tidy_jump( $gs, $start, 'JUMP_END', $end + 1);
}

# -------------------------
# loop counter
sub _doCounter {
	my ( $gs, $bs ) = @_;
	_push_stack( $gs, $bs->{debug}, OP_VAR, 'JUMP_NEXT', '$__count__' );
}

# -------------------------
# map
sub _doMap {
	my ( $gs, $bs ) = @_;

	die "No variable name in '$bs->{chunk}' " . _debug( $bs )
	  unless scalar @{ $bs->{arg} };

	my $name = shift @{ $bs->{arg} };
	die "Bad variable name '$name' " . _debug( $bs )
	 unless ( $name =~ m/^\$\b\w+/ );

	my $start = _push_stack( $gs, $bs->{debug}, OP_STARTBLOCK, 'JUMP_END', BLOCK_MAP, $name );
	my $newbs = _process_tokens( $gs );
	die "Bad 'map', no closing tag? " . _debug( $bs )
	 if ( $newbs == 0 );

	die "Bad end to map block '$newbs->{tag}' " . _debug( $bs )
	 unless ( $newbs->{tag} eq '/map' );

	my $end   = _push_stack( $gs, $bs->{debug}, OP_ENDBLOCK, 'JUMP_NEXT', BLOCK_MAP );
	_tidy_jump( $gs, $start, 'JUMP_END', $end );
}

# -------------------------
sub _doSwitch {
	my ( $gs, $bs ) = @_;
	my @elses;

	die "No variable name in '$bs->{chunk}' " . _debug( $bs )
	  unless scalar @{ $bs->{arg} } == 1;

	my $name = shift @{ $bs->{arg} };
	die "Bad variable name '$name' " . _debug( $bs )
	 unless ( $name =~ m/^\$\b\w+/ );

	my $newbs = _process_tokens( $gs );

	my $prev = -1;
	while ( $newbs->{tag} eq 'when' ) {                                 # FIXME move to test
		if ( scalar @{ $newbs->{arg} } == 1 ) {
			$newbs->{arg} = [ $name, '=', $newbs->{arg}[0] ];
		}
		elsif ( scalar @{ $newbs->{arg} } == 2 ) {
			$newbs->{arg} = [ $name, @{ $newbs->{arg} } ];
		}
		else {
			die "Unknown args to 'when' in '$newbs->{chunk} " . _debug( $bs )
		}

		my $top = _push_stack( $gs, $bs->{debug}, OP_STARTBLOCK, 'JUMP_ELSE', BLOCK_IF, _get_test( $newbs ) );
		$prev != -1 and _tidy_jump( $gs, $prev, 'JUMP_ELSE', $top );
		$prev = $top;
		$newbs = _process_tokens( $gs );
		push @elses, _push_stack( $gs, $bs->{debug}, OP_ENDBLOCK, 'JUMP_END', BLOCK_IF );
	}

	if ( $newbs->{tag} eq 'else' ) {
		my $top = _push_stack( $gs, $bs->{debug}, OP_STARTBLOCK, 'JUMP_NEXT', BLOCK_ELSE );
		$prev != -1 and _tidy_jump( $gs, $prev, 'JUMP_ELSE', $top );
		$prev = $top;
		$newbs = _process_tokens( $gs );
		_push_stack( $gs, $bs->{debug}, OP_ENDBLOCK, 'JUMP_NEXT', BLOCK_ELSE );
	}
	else {
		$prev != -1 and _tidy_jump( $gs, $prev, 'JUMP_ELSE', 'NEXT' );
	}

	die "Bad end to switch block '$newbs->{tag}' " . _debug( $bs )
	 unless ( $newbs->{tag} eq '/switch' );

	for ( @elses ) {
		_tidy_jump( $gs, $_, 'JUMP_END', 'NEXT' );
	}
}

# -------------------------
sub _doCall {
	my ( $gs, $bs ) = @_;

	die "No call name in '$bs->{chunk}' " . _debug( $bs )
	  unless scalar @{ $bs->{arg} };
	my $call = shift @{ $bs->{arg} };

	_push_stack( $gs, $bs->{debug}, OP_CALL, 'JUMP_NEXT', $call, @{ $bs->{arg} } );
}

# -------------------------
sub _doPrintf {
	my ( $gs, $bs ) = @_;

	die "No printf format in '$bs->{chunk}' " . _debug( $bs )
	  unless scalar @{ $bs->{arg} };

	my $format = shift @{ $bs->{arg} };
	# join quoted block - may need to be abstracted out and used widely
	if ( $format =~ m/^([\'\"])/ ) {
		my $quote = $1;
		if ( $format !~ m/$quote$/ ) {
			# look thru' args till we find a matching quote closing
			# FIXME - not the best solution
			while (1) {
				die "Unbalanced quoted printf format in '$bs->{chunk}' " . _debug( $bs )
				 unless scalar @{ $bs->{arg} };
				$format .= ' ' .  shift @{ $bs->{arg} };
				last if $format =~ m/$quote$/;
			}
			die "No printf variables in '$bs->{chunk}' " . _debug( $bs )
			 unless scalar @{ $bs->{arg} };
		}
		$format =~ s/^$quote//;
		$format =~ s/$quote$//;
	}
	# FIXME - should printf formats always use quotes?

	die "Bad printf format in'$format' " . _debug( $bs )
	 unless ( $format =~ m/\%/ );

	_push_stack( $gs, $bs->{debug}, OP_PRINTF, 'JUMP_NEXT', $format, @{ $bs->{arg} } );
}

# -------------------------
sub _doIgnore {
	my ( $gs, $bs ) = @_;

	while ( $gs->{chunks}[0] !~ m/^<%\s+\[\d+\:\d+\]\s+\/ignore\s+%>$/ ) {	
		shift @{ $gs->{chunks} };
	}
	shift @{ $gs->{chunks} };
}

# -------------------------
sub _doFormat {
	my ( $gs, $bs ) = @_;

	die "No Format name in '$bs->{chunk}' " . _debug( $bs )
	  unless scalar @{ $bs->{arg} };

	my $format = shift @{ $bs->{arg} };

	# check format types
	die "Bad format '$format' " . _debug( $bs )
	 unless ( $format =~ m/^\w+$/ );

	my $start = _push_stack( $gs, $bs->{debug}, OP_STARTBLOCK, 'JUMP_END', BLOCK_FORMAT, $format );
	my $newbs = _process_tokens( $gs );

	die "Bad end to format block '$newbs->{tag}' " . _debug( $bs )
	 unless ( $newbs->{tag} eq '/format' );

	my $end   = _push_stack( $gs, $bs->{debug}, OP_ENDBLOCK, 'JUMP_NEXT', BLOCK_FORMAT );
	_tidy_jump( $gs, $start, 'JUMP_END', $end );
}

# -------------------------
sub _doState {
	my ( $gs, $bs ) = @_;

	die "No State name in '$bs->{chunk}' " . _debug( $bs )
	  unless scalar @{ $bs->{arg} };
	my $state = shift @{ $bs->{arg} };
	die "Bad state '$state' in '$bs->{chunk}' " . _debug( $bs )
	 unless ( $state =~ m/^\w+$/ );

	die "No match in '$bs->{chunk}' " . _debug( $bs )
	  unless scalar @{ $bs->{arg} };
	my $val = shift @{ $bs->{arg} };

	my $regex = _make_match( $val )
	 or die "Bad match '$val' in '$bs->{chunk}' " . _debug( $bs );
	my $start = _push_stack( $gs, $bs->{debug}, OP_STARTBLOCK, 'JUMP_END', BLOCK_STATE, $state, $regex );
	my $newbs = _process_tokens( $gs );

	die "Bad end to state block '$newbs->{tag}' " . _debug( $bs )
	 unless ( $newbs->{tag} eq '/state' );

	my $end = _push_stack( $gs, $bs->{debug}, OP_ENDBLOCK, 'JUMP_NEXT', BLOCK_STATE );
	_tidy_jump( $gs, $start, 'JUMP_END', 'NEXT' );
}

# -------------------------
sub _doFinish {
	my ( $gs, $bs ) = @_;
	_push_stack( $gs, $bs->{debug}, OP_FINISH, -1 );
}

# ===================================================================

# -------------------------
sub _get_test {
	my $bs = shift;

	die "No args for conditional in '$bs->{chunk}' " . _debug( $bs )
	 unless ( scalar @{ $bs->{arg} } );

	# simple if defined test
	if ( scalar @{ $bs->{arg} } == 1 ) {
		my $var = $bs->{arg}[0];

		if ( $var =~ m/^(0|1)$/ ) {
			return ( TEST_EQUALS, '1', $var );	
		}

		die "Unknown variable name '$var' in '$bs->{chunk}' " . _debug( $bs )
		 unless ( $var =~ m/^\$\b\w+$/ );
		return ( TEST_DEFINED, $var );	
	}

	# simple comparison
	elsif ( scalar @{ $bs->{arg} } == 3 ) {
		my ( $var1, $test, $var2 ) = @{ $bs->{arg} };

		$test = '==' if ( $test eq '=' );
		my ( $state, $Not ) = ( 0, 0 );
		for ( $test ) {
			m/^==$/  and $state = TEST_EQUALS and last;
			m/^!=$/  and $state = TEST_EQUALS and $Not = 1 and last;
			m/^>$/   and $state = TEST_GT     and last;
			m/^>=$/  and $state = TEST_GTE    and last;
			m/^<$/   and $state = TEST_LT     and last;
			m/^<=$/  and $state = TEST_LTE    and last;
			die "Unknown test '$_' in '$bs->{chunk}' " . _debug( $bs )
		}

		my @params;
		$Not == 1 and ( push @params, TEST_NOT );
		push @params, $state;

		unless ( defined $var2 ) {
			die "var2 not defined in '$bs->{chunk} " . _debug( $bs )
		}

		if ( $var2 =~ m/^\"(.*?)\"$/ ) { # double quoted
			# FIXME - interpolate vars?..
			$var2 = $1;
		}
		if ( $var2 =~ m/^\'(.*?)\'$/ ) { # single quoted
			$var2 = $1;
		}

		push @params, ( $var1, $var2 );
		return @params;
	}
	else {
		die "Unknown conditional '"
		 . join( ' ', @{ $bs->{arg} } )
		 . "' in '$bs->{chunk}' " . _debug( $bs );
	}


# FIXME
#	# quoted vars ( or done in &_trim ? )
#	my $qvar = '';
#	if ( $bs->{chunk} =~ s/(=\s+)'(.*?)'$/$1/
#	 or $bs->{chunk} =~ s/(=\s+)"(.*?)"$/$1/ ) {
#		$qvar = $2;
#	}
#	push( @{ $bs->{arg} }, $qvar ) if $qvar;

}

# -------------------
sub _include {
	my ( $s, $file, $option, $db ) = @_;

	unless ( defined $db ) { # it's the initial include
		$db = '[0:0]';
	}
    my $bs = { gs => $s, debug => $db };

##	my $debug = $s->_debug( $db );
##print "_include : $db\n";
	defined $file
	 or die "Undefined include file name, " . _debug( $bs );

	return \$s->{_FILE_CACHE}{$file}
	 if ( exists $s->{_FILE_CACHE}{$file} );

	my $shrug = ( defined $option and $option eq '-shrug' ) ? 1 : 0;

	my $fname = $s->_find_file( $file );
	unless ( $fname ) {
		if ( $shrug == 1 ) {
			push @{ $s->{_INCLUDE_FILES} }, "\#$file";
			$s->{_FILE_CACHE}{$file} = '';
			return \'';
		}

		die "Unable to find file ($db) '$file' " . _debug( $bs )
		 . "\n in PATH...\n"
		 . join( "\n", @{ $s->{CONFIG}{path} } )
		 . "\n";
	}
	$fname =~ s{//}{/}g;
	push @{ $s->{_INCLUDE_FILES} }, $fname;

	my $fh;
	unless ( open( $fh, '<', $fname ) ) {
		if ( $shrug == 1 ) {
			$s->{_FILE_CACHE}{$file} = '';
			return \'';
		}

		die "Unable to open include file '$fname' " . _debug( $bs ) . ":$!\n";
	}

	sysread( $fh, my $buf, -s $fname )
	 or die "Unable to sysread file '$fname' " . _debug( $bs ) . ":$!";
	close $fh;

	# FIXME - use refs more - esp in $s->{_FILE_CACHE}
	$s->{_FILE_CACHE}{$file} = _add_debug_data( $buf, $#{ $s->{_INCLUDE_FILES} } );

	return \$s->{_FILE_CACHE}{$file};
}

# -------------------
sub _add_debug_data {
	my ( $data, $fid ) = @_;

	my $delim = DELIMITER;
	my ( $buf, $c );
	for ( split "\n", $data ) {
		$c++;
		s/$delim//g;
		s/(\<\%[-+]?\s)/$1\[$fid\:$c\] /g;
		$buf .= "$_\n";
	}
	chomp  $buf;
	return $buf;
}

# -------------------------
sub _debug {
	my ( $bs ) = @_;

#my ( $p, $fi, $l ) = caller;
#print "DEBUG($bs->{debug}) called by $l\n";

	$bs->{debug} =~ m/^\[(\d+)\:(\d+)\]$/
	 or die "Bad debug info '$bs->{debug}'";

	my $f = ( exists $bs->{gs}{_INCLUDE_FILES} ) ?
	 $bs->{gs}{_INCLUDE_FILES}[$1] : $bs->{gs}{CONFIG}{filename};

	return "$f:$2";
}

# -------------------------
# dumps to file
sub _dump {
	my $s = shift;

	my @buf;
	push @buf, OP_CONFIG . ",cache,$s->{CONFIG}{cache}";
	push @buf, OP_CONFIG . ",filename,$s->{CONFIG}{filename}";

	for ( qw{ no_includes die_on_bad_params remake max_depth
	 allow_absolute_path allow_relative_path } ) {
		push @buf, OP_CONFIG . ",config,$_,$s->{CONFIG}{$_}";
	}

	for ( @{ $s->{_INCLUDE_FILES} } ) {
		push @buf, OP_CONFIG . ",includes,$_";
	}
	for ( @{ $s->{CONFIG}{path} } ) {
		push @buf, OP_CONFIG . ",path,$_";
	}

	# Stack
	for my $f ( @{ $s->{_STACK} } ) {
		push @buf, join ',', @$f;
	}

	open( my $fh, '>', Compost::Template::Misc::safe_file( $s->{CONFIG}{cache} ) )
	 or die "Unable to open Template Cache '$s->{CONFIG}{cache}' for writing:$!";
	print $fh join( DELIMITER, @buf );
	close $fh;
}

# thankyouverymuchgoodnight
1;

