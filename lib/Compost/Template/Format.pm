package Compost::Template::Format;

# see Compost::Template.pod

use strict;
use warnings;
use 5.014;
use autodie;

use Compost::Template::Misc;

our $VERSION = '0.5.0';

my %formats = (
	uppercase  => \&_formatUppercase,
	upper      => \&_formatUppercase,
	capitalize => \&_formatCapitalize,
	lowercase  => \&_formatLowercase,
	lower      => \&_formatLowercase,
	truncate   => \&_formatTruncate,
	trim       => \&_formatTrim,
	wordwrap   => \&_formatWordwrap,
	text2html  => \&_formatText2html,
	html       => \&_formatText2html,
	ucfirst    => \&_formatUcfirst,
	lcfirst    => \&_formatLcfirst,
	reverse    => \&_formatReverse,
	repeat     => \&_formatRepeat,
	center     => \&_formatCenter,
	slugify    => \&_formatSlugify,
	strip_tags => \&_formatStripTags,
	truncate_words => \&_formatTruncateWords,
);

sub isKnown {
	my ( $class, $name ) = @_;
	return ( exists $formats{$name} ) ? 1 : 0;
}

sub format {
	my ( $class, $text, $name, @args ) = @_;

	die "Unknown Format '$name'"
	 unless ( exists $formats{$name} );

	return &{ $formats{$name} }( $text, @args );
}

sub add {
	my ( $class, $name, $callback ) = @_;

	$formats{$name} = $callback;
}

# ======================================================

sub _formatUppercase {
	my $text = shift;
	return uc $text;
}

sub _formatCapitalize {
	my $text = shift;
	$text =~ s/(\b\w+\b)/\u\L$1/g;
	return $text;
}

sub _formatLowercase {
	my $text = shift;
	return lc $text;
}

sub _formatUcfirst {
	my $text = shift;
	return ucfirst $text;
}

sub _formatLcfirst {
	my $text = shift;
	return lcfirst $text;
}

sub _formatReverse {
	my $text = shift;
	return scalar reverse $text;
}

sub _formatRepeat {
	my ( $text, $count ) = @_;
	$count //= 1;
	return $text x $count;
}

sub _formatCenter {
	my ( $text, $width ) = @_;
	$width //= 72;
	my $pad = $width - length($text);
	return $text if $pad <= 0;
	my $left = int( $pad / 2 );
	return ' ' x $left . $text . ' ' x ( $pad - $left );
}

sub _formatSlugify {
	my $text = shift;
	$text = lc $text;
	$text =~ s/[^\w\s-]//g;
	$text =~ s/[\s_]+/-/g;
	$text =~ s/^-+|-+$//g;
	return $text;
}

sub _formatStripTags {
	my $text = shift;
	$text =~ s/<[^>]+>//g;
	return $text;
}

sub _formatTruncateWords {
	my ( $text, $count ) = @_;
	$count //= 10;
	my @words = split /\s+/, $text;
	return join( ' ', @words[0 .. $count - 1] ) if scalar @words > $count;
	return $text;
}

sub _formatTruncate {
	my ( $text, $length ) = @_;
	$length //= 0;
	return substr( $text, 0, $length );
}

sub _formatTrim {
	my $text = shift;
	$text =~ s/^\s+//;
	$text =~ s/\s+$//;
	$text =~ s/ +/ /;
	return $text;
}

sub _formatWordwrap {
	my ( $text, $width ) = @_;
	$width //= 78;
	$text =~ s/([^\n]{0,$width}[\.\,\;]?)\b\s*/$1\n/mg;
	return $text;
}

sub _formatText2html {
	my $text = shift;

	$text = Compost::Template::Misc::htmlize( $text );

	my $buf;
	for ( split /\n/, $text ) {
		if (/^\s/) {
			s{(.*)$}               {<pre>\n$1</pre>\n}s;
		}
		else {
			s{^(>.*)}              {$1<br>}gm;
			s{<URL:(.*?)>}         {<a href="$1">$1</a>}gs
			 ||
			s{((ftp|https?):/\S+)} {<a href="$1">$1</a>}gs;
			s{\*(\S+)\*}           {<b>$1</b>}g;
			s{\b_(\S+)\_\b}        {<i>$1</i>}g;
			s{^}                   {<p>\n};
		}
		$buf .= $_;
	}

	return $buf;
}

1;
