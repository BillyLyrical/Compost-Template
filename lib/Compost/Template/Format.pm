package Compost::Template::Format;

# see Compost::Template.pod

use strict;
use Compost::Template::Misc;

our $VERSION = '0.06';

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
#	wiki       => \&_formatcwWiki,
);

sub isKnown {
	my ( $class, $name ) = @_;
	return ( exists $formats{$name} ) ? 1 : 0;
}

sub format {
	my ( $class, $text, $name, @args ) = @_;

	die "Unkown Format '$name'"
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

sub _formatTruncate {
	my ( $text, $length ) = @_;
	# FIXME - complain/die if $length not a number
	$length ||= 0;
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
	# FIXME - complain/die if $width not a number
	$width ||= 78;
	# FIXME - should linebreaks be honoured?
	$text =~ s/([^\n]{0,$width}[\.\,\;]?)\b\s*/$1\n/mg;
	return $text;
}

sub _formatText2html {
	my $text = shift;

	$text = Compost::Template::Misc::htmlize( '', $text );

	# from perl cookbook - FIXME - can be improved heaps!!
	my $buf;
	for ( split /\n/, $text ) {
		if (/^\s/) {
			# Paragraphs beginning with whitespace are wrapped in <PRE> 
			s{(.*)$}               {<pre>\n$1</pre>\n}s;       # indented verbatim
		}
		else {
			s{^(>.*)}              {$1<br>}gm;                 # quoted text
			s{<URL:(.*?)>}         {<a href="$1">$1</a>}gs     # embedded URL  (good)
			 ||
			s{((ftp|https?):/\S+)} {<a href="$1">$1</a>}gs;    # guessed URL   (bad)
			s{\*(\S+)\*}           {<b>$1</b>}g;               # this is *bold* here
			s{\b_(\S+)\_\b}        {<i>$1</i>}g;               # this is _italics_ here
			s{^}                   {<p>\n};                    # add paragraph tag
		}
		$buf .= $_;
	}

	return $buf;
}

#sub _formatWiki {
#	my $text = shift;
#	require Compost::Wiki;
#	return Compost::Wiki::parse( $text );
#}

# thankyouverymuchgoodnight
1;

