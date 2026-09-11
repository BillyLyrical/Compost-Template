# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl Compost-Template.t'

#########################
use lib 'lib/';

use Test::More tests => 79;
BEGIN {
    use_ok('Compost::Template');
    use_ok('Compost::Template::Runtime');
    use_ok('Compost::Template::Parser');
};

#########################

# clear the cache
unlink <./t/cache/*>;

# ------------------------------------------------
my $factory = Compost::Template::Factory->create(
	path                => './t/data',
	cache_dir           => './t/cache',
	params => {
		foo => 'FOOO',
		bar => 'BARR',
	}
);

# ------------------------------------------------
# test whether multiple calls to factory keep params

my $t1 = $factory->new( 'template2.tmpl' );
my $reply = $t1->run();
is( $reply, 'FOOO and BARR',    '1 template' );

my $t2 = $factory->new( 'template2.tmpl' );
$reply = $t2->run();
is( $reply, 'FOOO and BARR',    '2 template' );

my $t3 = $factory->new( 'template2.tmpl' );
$reply = $t3->run();
is( $reply, 'FOOO and BARR',    '3 template' );

# ------------------------------------------------
undef $factory;
$factory = Compost::Template::Factory->create(
	path                => './t/data',
	cache_dir           => './t/cache',
);

ok( defined $factory );
ok( $factory->isa( 'Compost::Template::Factory' ), 'Made a Factory' );

my $template = $factory->new( 'whitespace.tmpl' );
ok( defined $template );
ok( $template->isa( 'Compost::Template' ), 'got new Template' );
$template->set_state( 'Main' => 'main.foo.bar.test' );
ok( $template->match( 'Main', 'main.foo.bar.test' ), 'match 1' );
ok( $template->match( 'Main', '*.test' ),    'match 2' );
ok( $template->match( 'Main', 'main.*.test' ),    'match 3' );
ok( $template->match( 'Main', '!main.*.BAD' ),    'match 4' );
ok( $template->match( 'Main', 'main.foo.?.test' ),    'match 5' );
$template->set_state( 'Test' => 'test' );
is( $template->match( 'Test', 'test' ) , '1',    'match 6' );

# ------------------------------------------------
# general whitespace test
$template
 ->param(
	'h'     => 'H',
	'ello'  => 'ello',
	'world' => 'World',
	'bang'  => '!', 
);
$reply = $template->run();
is( $reply, 'Hello World! Hello World!',    'whitespace & interpolation' );

# ------------------------------------------------
# test delimiter
$template = $factory->new( 'bad_delimiter.tmpl' );
$reply = $template->run();
is( $reply, 'Yes it works',    'bad delimiter' );

# ------------------------------------------------
# test includes
$template = $factory->new( 'include1.tmpl' );
$reply = $template->run();
is( $reply, 'Includes works!',    'includes' );

# ------------------------------------------------
# test if/elsif/else
$template = $factory->new( 'elsif.tmpl' );
$reply = $template->param( x => 2 )->run();
is( $reply, 'IF works ok Good',    'if' );
$reply = $template->param( x => 3 )->run();
is( $reply, 'ELSIF works ok Good',  'elsif' );
$reply = $template->param( x => 4 )->run();
is( $reply, 'ELSE works ok Good',  'else' );
$reply = $template->param( x => 5 )->run();
is( $reply, 'UNLESS works ok Good',  'unless' );

# ------------------------------------------------
# test loops

$template = $factory->new( 'loop1.tmpl' );
$reply = $template->param(  digits => [
 { num => 0 }, { num => 1 }, { num => 2 }, { num => 3 }, { num => 4 }, { num => 5 }
])->run();
is( $reply, ' 0 1 2 3 4 5 OK',    'simple loop' );

$template = $factory->new( 'loop.tmpl' );
$reply = $template->param( test => 1, digits => [
 { num => 1 }, { num => 2 }, { num => 3 }, { num => 4 }, { num => 5 }
])->run();
is( $reply, ' 1 2 3 4 5 OK',    'loop' );
$reply = $template->param( test => 2, digits => [
 { num => 1 }, { num => 2 }, { num => 3 }, { num => 4 }, { num => 5 }
])->run();
is( $reply, ' 1 2 3 4 5 OK',    'loop counter' );

# ------------------------------------------------
# test switch
$template = $factory->new( 'switch.tmpl' );
$reply = $template->param( digits => [
 { num => 1 }, { num => 2 }, { num => 3 }, { num => 4 }, { num => 5 }
])->run();
is( $reply, ' 5 4 3 2 1',    'switch' );

# ------------------------------------------------
# test mode
$template = $factory->new( 'mode.tmpl' );
$reply = $template->set_state( Mode => 'Foo.Bar' )->run();
is( $reply, 'Mode1',    'mode 1' );
$reply = $template->set_state( Mode => 'BAZ.2' )->run();
is( $reply, 'Mode2',    'mode 2' );
$reply = $template->set_state( Mode => 'BAZ.3' )->run();
is( $reply, 'Mode3',    'mode 3' );

# ------------------------------------------------
# test map
$template = $factory->new( 'map.tmpl' );
$reply = $template->param( test => 1, foo => { bar => {
 'map' => 'Map', 'works' => 'works', 'ok' => 'OK'
} } )->run();
is( $reply, 'Map works OK OK',    'map 1' );
$reply = $template->param( test => 2, foo => [
qw{ OK works bad Map bad }
] )->run();
is( $reply, 'Map works OK OK',    'map 2' );
$reply = $template->param( test => 3, foo => [
	{ word => 'Map'}, { word => 'works' }, { word => 'OK' }
] )->run();
is( $reply, 'Map works OK OK',    'map 3' );

{
	my @tarray;
	for ( 0..4 ) {
		my $g = {};
		$g->{num} = $_;
		$g->{word} = 'yaya';
		push @tarray, $g;
	}
	$template = $factory->new( 'map2.tmpl' );
	$reply = $template->param( child => \@tarray )->run();
	is( $reply, ' 0 1 2 3 4 OK',    'map loop' );
}

# ------------------------------------------------
# deep mapping
$template = $factory->new( 'map_deep.tmpl' );
$reply = $template->param(
	foo => [
		{ bar => {
			'map' => 'Map', 'works' => 'works', 'ok' => { ok => 'OK' }
			}
		}
	]
)->run();
is( $reply, 'Map works OK',    'map deep' );

# ------------------------------------------------
# test random
$template = Compost::Template->new(
    template => '<% random $list %><% $_ %><% /random %>',
);
$reply = $template->param( list => [qw{ alpha bravo charlie delta echo }] )->run();
ok( grep { $_ eq $reply } qw{ alpha bravo charlie delta echo }, 'random pick' );

$template = Compost::Template->new(
    template => '<% random $list %><% $__index__ %><% /random %>',
);
$reply = $template->param( list => [qw{ alpha bravo charlie delta echo }] )->run();
ok( $reply >= 0 && $reply <= 4, 'random index' );

# ------------------------------------------------
# test dice
$template = Compost::Template->new(
    template => '<% dice 1d6 %>',
);
$reply = $template->run();
ok( $reply >= 1 && $reply <= 6, 'dice 1d6' );

$template = Compost::Template->new(
    template => '<% dice 2d6+1 %>',
);
$reply = $template->run();
ok( $reply >= 3 && $reply <= 13, 'dice 2d6+1' );

$template = Compost::Template->new(
    template => '<% dice 3d8-2 %>',
);
$reply = $template->run();
ok( $reply >= 1 && $reply <= 22, 'dice 3d8-2' );

# ------------------------------------------------
# test printf
$template = $factory->new( 'printf.tmpl' );
$reply = $template->param( test => 1, var => 34 )->run();
is( $reply, '00000034',    'printf 1' );
$reply = $template->param( test =>2, var => 34 )->run();
is( $reply, 'Hey 00000034',    'printf 2' );

# ------------------------------------------------
# test ignore
$template = $factory->new( 'ignore.tmpl' );
$reply = $template->run();
is( $reply, 'This is ok',    'ignore' );

# ------------------------------------------------
# test globals
$template = $factory->new( 'global.tmpl' );
$reply = $template->param( test => 5, down => {
  test => 7 }
)->run();
is( $reply, ' 7 5 ',  'globals' );

# ------------------------------------------------
# test formats
$template = $factory->new( 'format.tmpl' );
$reply = $template->param( test => 'this is a test' )->run();
is( $reply, 'THIS IS A TEST',    'format -uc' );

$template = Compost::Template->new(
    template => '<% format ucfirst %><% $test %><% /format %>',
);
$reply = $template->param( test => 'hello world' )->run();
is( $reply, 'Hello world', 'format ucfirst' );

$template = Compost::Template->new(
    template => '<% format lcfirst %><% $test %><% /format %>',
);
$reply = $template->param( test => 'HELLO WORLD' )->run();
is( $reply, 'hELLO WORLD', 'format lcfirst' );

$template = Compost::Template->new(
    template => '<% format reverse %><% $test %><% /format %>',
);
$reply = $template->param( test => 'hello' )->run();
is( $reply, 'olleh', 'format reverse' );

$template = Compost::Template->new(
    template => '<% format repeat 3 %><% $test %><% /format %>',
);
$reply = $template->param( test => 'ab' )->run();
is( $reply, 'ababab', 'format repeat' );

$template = Compost::Template->new(
    template => '<% format center 10 %><% $test %><% /format %>',
);
$reply = $template->param( test => 'hi' )->run();
is( $reply, '    hi    ', 'format center' );

$template = Compost::Template->new(
    template => '<% format slugify %><% $test %><% /format %>',
);
$reply = $template->param( test => 'Hello World! How are you?' )->run();
is( $reply, 'hello-world-how-are-you', 'format slugify' );

$template = Compost::Template->new(
    template => '<% format strip_tags %><% $test %><% /format %>',
);
$reply = $template->param( test => '<b>bold</b> and <i>italic</i>' )->run();
is( $reply, 'bold and italic', 'format strip_tags' );

$template = Compost::Template->new(
    template => '<% format truncate_words 3 %><% $test %><% /format %>',
);
$reply = $template->param( test => 'the quick brown fox jumps' )->run();
is( $reply, 'the quick brown', 'format truncate_words' );

# ------------------------------------------------
# dynamic templates
$template = Compost::Template->new(
	template => 'Yes <% include include1.tmpl %>',
	path     => './t/data',
);
$reply = $template->run();
is( $reply, 'Yes Includes works!', 'dynamic template' );

# ------------------------------------------------
# test if what happens if a var isn't defined
$template = Compost::Template->new(
  die_on_bad_params => 0,
  filename => 'badvar.tmpl',
	path   => './t/data',
);
$reply = $template->run();
is( $reply, '1 .', 'bad var' );

# ------------------------------------------------
# allow_absolute_path
# - not sure how to test for error being thrown
#   when allow_absolute_path => 0
$template = Compost::Template->new(
  allow_absolute_path => 1,
  filename => File::Spec->rel2abs('./t/data/absolute'),
);
$reply = $template->run();
is( $reply, 'absolute', 'allow_absolute_path' );

# ------------------------------------------------
# call
$template = Compost::Template->new(
	template => '<% call test hello $name %>',
);
$template->set_call( 'test',
  sub { return join ' ', @_ }
);
$reply = $template->param( name => 'world' )->run();
is( $reply, 'hello world', 'call' );

# ------------------------------------------------
# anonymous array vars
$template = Compost::Template->new(
    template => '<% loop $array %> <% $_ %><% /loop %>',
);
$reply = $template->param( array => [ 1, 3, \5, 7, ] )->run();
is( $reply, ' 1 3 5 7', 'anon array' );

# ------------------------------------------------
# <% $var -shrug %>  - need to be able to stack -opts
$template = Compost::Template->new(
    template => 'hey <% $novar -shrug -%> ho',
);
$reply = $template->param( foo => 44 )->run();
is( $reply, 'hey ho', 'var shrug' );

# ------------------------------------------------
# one argument if/unless/elsif
$template = Compost::Template->new(
    template => '<% if $var %>Yes<% else %>No<% /if %>',
);
$reply = $template->param( var => 1  )->run();
is( $reply, 'Yes', 'one argument if' );

$template = Compost::Template->new(
    template => '<% if $var %>Yes<% else %>No<% /if %>',
);
$reply = $template->param( var1 => 0  )->run();
is( $reply, 'No', 'one argument else' );

$template = Compost::Template->new(
    template => '<% if $var -shrug %>Yes<% else %>No<% /if %>',
);
$reply = $template->param( novar => 0  )->run();
is( $reply, 'No', 'one argument if -shrug' );

$template = Compost::Template->new(
    template => '<% if $var1 %>No<% elsif $var2 %>Yes<% /if %>',
);
$reply = $template->param( var2 => 1  )->run();
is( $reply, 'Yes', 'one argument elsif' );

$template = Compost::Template->new(
    template => '<% unless $var %>Yes<% else %>No<% /unless %>',
);
$reply = $template->param( var => 0  )->run();
is( $reply, 'Yes', 'one argument unless' );

# ------------------------------------------------
# test loops: __count__, __inner__, __outer__, __even__, __odd__, __first__, __last__
$template = Compost::Template->new(
    template => '<% loop $var %><% $__count__ %><% /loop %>',
);
$reply = $template->param( var => [ 23, 12, 53 ]  )->run();
is( $reply, '123', 'loop __count__' );

$template = Compost::Template->new(
    template => '<% loop $var %><% $__index__ %><% /loop %>',
);
$reply = $template->param( var => [ 23, 12, 53 ]  )->run();
is( $reply, '012', 'loop __index__' );

$template = Compost::Template->new(
    template => '<% loop $var %><% $__total__ %><% /loop %>',
);
$reply = $template->param( var => [ 23, 12, 53 ]  )->run();
is( $reply, '333', 'loop __total__' );

$template = Compost::Template->new(
    template => '<% loop $var %><% if $__inner__ %><% $_ %><% /if %><% /loop %>',
);
$reply = $template->param( var => [qw{ a b c d e  }]  )->run();
is( $reply, 'bcd', 'loop __inner__' );

$template = Compost::Template->new(
    template => '<% loop $var %><% if $__outer__ %><% $_ %><% /if %><% /loop %>',
);
$reply = $template->param( var => [ 23, 12, 53 ]  )->run();
is( $reply, '2353', 'loop __outer__' );

$template = Compost::Template->new(
    template => '<% loop $var %><% if $__even__ %><% $_ %><% /if %><% /loop %>',
);
$reply = $template->param( var => [qw{ a b c d e }]  )->run();
is( $reply, 'bd', 'loop __even__' );

$template = Compost::Template->new(
    template => '<% loop $var %><% if $__odd__ %><% $_ %><% /if %><% /loop %>',
);
$reply = $template->param( var => [qw{ a b c d e }]  )->run();
is( $reply, 'ace', 'loop __odd__' );

$template = Compost::Template->new(
    template => '<% loop $var %><% if $__first__ %><% $_ %><% elsif $__last__ %><% $_ %><% /if %><% /loop %>',
);
$reply = $template->param( var => [qw{ a b c d e }]  )->run();
is( $reply, 'ae', 'loop __first__ & __last__' );

# ------------------------------------------------
# interpolated insertion
$template = Compost::Template->new(
    template => '<% "1 $var1 3 $var2 5" %>',
);
$reply = $template->param( var1 => 2, var2 => 4  )->run();
is( $reply, '1 2 3 4 5', 'interpolated insertion' );

# ------------------------------------------------
# or vars
$template = Compost::Template->new(
    template => '<% $var1 or $var2 or "hmmm" %>',
);
$reply = $template->param( var1 => 1  )->run();
is( $reply, '1', 'or vars 1' );

$reply = $template->param( var2 => 2  )->run();
is( $reply, '2', 'or vars 2' );

$reply = $template->param( var1 => 0  )->run();
is( $reply, 'hmmm', 'or vars 3' );

# ------------------------------------------------
# magic variables: __line__, __file__
$template = Compost::Template->new(
    template => '<% $__line__ %>',
);
$reply = $template->run();
is( $reply, '1', '__line__ line 1' );

$template = Compost::Template->new(
    template => "line1\n<% \$__line__ %>",
);
$reply = $template->run();
is( $reply, "line1\n2", '__line__ line 2' );

$template = Compost::Template->new(
    template => '<% $__file__ %>',
    path     => './t/data',
);
$reply = $template->run();
is( $reply, '(template)', '__file__ returns (template) for inline' );



# ------------------------------------------------
# Wanna Test
#  allow_relative_path
# <% fetch SOMEURL %>
# <% $var or 'foo' %>
# <% warn %> ... <% /warn %>
# <% die  %> ... <% /die %>
# <% date CONFIG %>
# <% time CONFIG %>
# <% uid %> <% gid %> <% pid %>
# <% random ?? %> <% dice 2d10+1 %>
# <% any ARRAY ref %>
# add format 'quotemeta' (see perldoc -f quotemeta )
# options for loop ( reverse, shuffle, first 10, last 2...)
# loop over keys & values for hashes
# check out perl6 formats
# insert sql!!! 
# prepend/append: stuff  at start of end of lines

# clear the chache again
unlink <./t/cache/*>;

