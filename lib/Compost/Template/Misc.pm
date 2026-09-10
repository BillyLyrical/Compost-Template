package Compost::Template::Misc;

use strict;
use warnings;
use 5.014;
use autodie;

use Path::Tiny;
use File::Spec;

our $VERSION = '0.1.0';

# -----------------------------------------
# utility subs

sub url_encode {
	my ($s) = @_;
	return '' if !defined $s;
	$s =~ s/([^-_.a-zA-Z0-9])/"\%".unpack("H2",$1)/egs;
	return $s;
}

sub htmlize {
	my ($s) = @_;
	return '' if !defined $s;
	$s =~ s/&/&amp;/gs;
	$s =~ s/>/&gt;/gs;
	$s =~ s/</&lt;/gs;
	$s =~ s/"/&quot;/gs;
	return $s;
}

sub dehtmlize {
	my ($s) = @_;
	return '' if !defined $s;
	$s =~ s/&gt;/>/gs;
	$s =~ s/&lt;/</gs;
	$s =~ s/&quot;/"/gs;
	$s =~ s/&amp;/&/gs;
	return $s;
}

# -----------------------------------------
# safe_file - validates and sanitizes file paths

sub safe_file {
	my $file = shift;

	die "No filename passed?"
	 unless ( defined $file and $file ne '' );

	my ( undef, $directory, $filename ) = File::Spec->splitpath( $file );
	my @directory_elements = File::Spec->splitdir( $directory );
	my @filtered = File::Spec->no_upwards( @directory_elements );

	# validate each directory element
	my @safe_dirs;
	for my $dir_element ( @filtered ) {
		next if $dir_element eq '';
		if ( $dir_element =~ m/^([-_a-zA-Z0-9.]{1,127})$/s ) {
			push @safe_dirs, $1;
		}
		else {
			die "Unsafe filename '$file' contains unallowed characters "
			 . "in path element '$dir_element'";
		}
	}

	# validate filename
	my ( $safe_filename ) = $filename =~ m/^([-_a-zA-Z0-9.]{1,127})$/s;
	unless ( defined $safe_filename ) {
		die "Unsafe filename '$file' contains unallowed characters";
	}

	# rebuild absolute path
	my $partial_path = File::Spec->catdir( @safe_dirs );
	my $safe_file = File::Spec->catfile( File::Spec->rootdir(), $partial_path, $safe_filename );

	return $safe_file;
}

1;
