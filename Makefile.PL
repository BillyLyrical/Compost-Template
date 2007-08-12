#!/perl/bin

use ExtUtils::MakeMaker;

require 5.005;

WriteMakefile(
  NAME            => 'Compost::Template',
  ABSTRACT_FROM   => 'lib/Compost/Template.pod',
  VERSION_FROM    => 'lib/Compost/Template.pm',
  AUTHOR          => 'Billy Naylor <banjo@actrix.co.nz>',
  MAN3PODS        => {},
  PREREQ_PM       => {
    File::Spec => 0,
    Test::More => 0,
  },
);

