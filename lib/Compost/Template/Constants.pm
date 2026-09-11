package Compost::Template::Constants;

use strict;
use warnings;
use 5.014;

use Exporter 'import';

our $VERSION = '0.4.0';

my @op_names    = qw{ OP_CONFIG OP_DATA OP_VAR OP_PRINTF OP_CALL OP_STARTBLOCK OP_ENDBLOCK OP_FINISH OP_EXTENDS };
my @block_names = qw{ BLOCK_NOTIF BLOCK_IF BLOCK_ELSE BLOCK_LOOP BLOCK_INSERT BLOCK_PREFIX
                      BLOCK_MAP BLOCK_FORMAT BLOCK_STATE BLOCK_RANDOM BLOCK_DICE BLOCK_BLOCK };
my @test_names  = qw{ TEST_NOT TEST_DEFINED TEST_EQUALS TEST_GT TEST_GTE TEST_LT TEST_LTE };
my @var_names   = qw{ GLOBAL_VAR ESCAPE_HTML ESCAPE_URL VAR_SHRUG };
my @cache_names = qw{ CACHE_VERSION };

our @EXPORT_OK = ( @op_names, @block_names, @test_names, @var_names, @cache_names );
our %EXPORT_TAGS = (
	op    => \@op_names,
	block => \@block_names,
	test  => \@test_names,
	var   => \@var_names,
	cache => \@cache_names,
	all   => [ @op_names, @block_names, @test_names, @var_names, @cache_names ],
);

use constant {
	CACHE_VERSION  => 2,

	OP_CONFIG      => 0,
	OP_DATA        => 1,
	OP_VAR         => 2,
	OP_PRINTF      => 3,
	OP_CALL        => 4,
	OP_STARTBLOCK  => 5,
	OP_ENDBLOCK    => 6,
	OP_FINISH      => 7,
	OP_EXTENDS     => 8,

	BLOCK_NOTIF    => 0,
	BLOCK_IF       => 1,
	BLOCK_ELSE     => 2,
	BLOCK_LOOP     => 3,
	BLOCK_INSERT   => 4,
	BLOCK_PREFIX   => 5,
	BLOCK_MAP      => 6,
	BLOCK_FORMAT   => 7,
	BLOCK_STATE    => 8,
	BLOCK_RANDOM   => 9,
	BLOCK_DICE     => 10,
	BLOCK_BLOCK    => 11,

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
};

1;
