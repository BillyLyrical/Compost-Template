#!/perl/bin

use ExtUtils::MakeMaker;

WriteMakefile(
  NAME            => 'Compost::Template',
  ABSTRACT_FROM   => 'lib/Compost/Template.pod',
  VERSION_FROM    => 'lib/Compost/Template.pm',
  AUTHOR          => 'Billy Naylor <banjo@actrix.co.nz>',
  MAN3PODS        => { 'lib/Compost/Template.pod' },
);

