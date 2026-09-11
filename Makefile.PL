#!/perl/bin

use ExtUtils::MakeMaker;

use 5.014;

WriteMakefile(
  NAME            => 'Compost::Template',
  ABSTRACT        => 'Simple templating engine compiled to bytecode',
  VERSION_FROM    => 'lib/Compost/Template.pm',
  AUTHOR          => 'Billy Lyrical <billy.lyrical@gmail.com>',
  MAN3PODS        => {},
  PREREQ_PM       => {
    'File::Spec'  => 0,
    'Path::Tiny'  => 0,
    'Test::More'  => 0,
  },
);
