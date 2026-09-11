#!/usr/bin/env perl

use strict;
use warnings;
use 5.014;
use autodie;
use Getopt::Long;

use Path::Tiny;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Compost::Template;
use Compost::Template::Format;
use Compost::Template::Constants qw(:all);

my $opt_path     = '';
my $opt_help     = 0;
my $opt_verbose  = 0;

GetOptions(
	'path=s'    => \$opt_path,
	'help'      => \$opt_help,
	'verbose'   => \$opt_verbose,
) or usage(1);

usage(0) if $opt_help;

my @files = @ARGV;
usage(1) unless @files;

# --- main ---
my ( $errors, $warnings ) = ( 0, 0 );

for my $file ( @files ) {
	my ( $e, $w ) = lint_file( $file );
	$errors   += $e;
	$warnings += $w;
}

print "\n" if $errors || $warnings;
printf "%d error%s, %d warning%s\n",
	$errors,   $errors   == 1 ? '' : 's',
	$warnings, $warnings == 1 ? '' : 's';

exit( $errors ? 1 : 0 );

# ==============================

sub lint_file {
	my $file = shift;

	my ( $ok, @err ) = try_compile( $file );

	if ( !$ok ) {
		for my $err ( @err ) {
			error( $file, $err );
		}
		return ( scalar @err, 0 );
	}

	my ( $stack, $self ) = @$ok;
	my $warns = 0;

	# Undefined filters
	for my $entry ( @$stack ) {
		next unless $entry->[1] == OP_VAR;
		my @filters = get_filters( $entry );
		for my $f ( @filters ) {
			unless ( Compost::Template::Format->isKnown( $f ) ) {
				warning( $file, $entry->[0], "undefined filter '$f'" );
				$warns++;
			}
		}
	}

	# Undefined macros
	my %defined = map { $_ => 1 } keys %{ $self->{_MACROS} // {} };
	for my $entry ( @$stack ) {
		next unless $entry->[1] == OP_CALL;
		my $name = $entry->[3] // '';
		if ( $name and !exists $defined{$name} ) {
			warning( $file, $entry->[0], "undefined macro '$name'" );
			$warns++;
		}
	}

	# Unused macros
	if ( $opt_verbose ) {
		my %called;
		for my $entry ( @$stack ) {
			next unless $entry->[1] == OP_CALL;
			$called{ $entry->[3] } = 1 if defined $entry->[3];
		}
		for my $name ( keys %defined ) {
			unless ( $called{$name} ) {
				warning( $file, undef, "macro '$name' is defined but never called" );
				$warns++;
			}
		}
	}

	return ( 0, $warns );
}

# ==============================

sub try_compile {
	my $file = shift;

	my $buf;
	if ( $file eq '-' ) {
		$buf = do { local $/; <STDIN> };
	} else {
		$buf = path( $file )->slurp;
	}
	my @err;

	my %cfg = ( path => $opt_path ) x !!$opt_path;

	my $self = eval {
		Compost::Template->new(
			template          => $buf,
			die_on_bad_params => 0,
			%cfg,
		);
	};

	if ( $@ ) {
		my $msg = $@;
		chomp $msg;
		# Clean up the error message
		$msg =~ s/ at .*? line \d+.*$//;
		push @err, $msg;
	}

	# Parser may have accumulated warnings in _INCLUDE_FILES
	# (e.g. -shrug includes that were missing)
	if ( $self and exists $self->{_INCLUDE_FILES} ) {
		for my $inc ( @{ $self->{_INCLUDE_FILES} } ) {
			if ( $inc =~ m/^#/ ) {
				( my $missing = $inc ) =~ s/^#//;
				push @err, "included file '$missing' not found";
			}
		}
	}

	return ( [ $self->{_STACK}, $self ], @err ) if !@err;
	return ( undef, @err );
}

# ==============================
# bytecode helpers

sub get_filters {
	my $entry = shift;

	my @args  = @$entry;
	my $path_count = $args[4] // 0;
	my $c = 5 + $path_count;

	# skip option integers (SCOPE_*, ESCAPE_*, etc.) — all small numbers
	while ( $c < scalar @args and $args[$c] =~ m/^\d+$/ and $args[$c] <= SCOPE_PARENT ) {
		$c++;
	}

	# sentinel 256 marks start of filter section
	return () unless $c < scalar @args and $args[$c] == 256;
	$c++;  # skip sentinel

	my $count = $args[$c++];
	return @args[ $c .. $c + $count - 1 ];
}

# ==============================
# output helpers

sub error {
	my ( $file, $msg ) = @_;
	$file //= '(input)';
	if ( $msg =~ m/\[(\d+):(\d+)\]/ ) {
		my ( $f, $l ) = ( $1, $2 );
		$msg =~ s/\[\d+:\d+\]/$file:$l/;
	} else {
		$msg = "$file: $msg";
	}
	print STDERR "ERROR: $msg\n";
}

sub warning {
	my ( $file, $debug, $msg ) = @_;
	$file //= '(input)';
	if ( $debug and $debug =~ m/\[(\d+):(\d+)\]/ ) {
		$msg = "$file:$2: $msg";
	} else {
		$msg = "$file: $msg";
	}
	print STDERR "WARN:  $msg\n";
}

sub usage {
	my $exit = shift;
	print STDERR <<'USAGE';
Usage: compost-lint.pl [options] <file.tmpl> [file2.tmpl ...]

Options:
  --path <dir>    Template include path (can be repeated)
  --verbose       Also report unused macros
  --help          Show this message

Examples:
  compost-lint.pl templates/*.tmpl
  compost-lint.pl --path views templates/page.tmpl
  cat page.tmpl | compost-lint.pl -
USAGE
	exit $exit;
}
