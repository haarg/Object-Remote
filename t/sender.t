use strictures 1;
use Test::More;

use Object::Remote::Connector::Local;
use Object::Remote;
use Object::Remote::ModuleSender;

$ENV{PERL5LIB} = join(
  ':', ($ENV{PERL5LIB} ? $ENV{PERL5LIB} : ()), qw(lib)
);

my $mod_content = do {
  open my $fh, '<', 't/lib/ORTestClass.pm'
    or die "can't read ORTestClass.pm: $!";
  local $/;
  <$fh>
};
my $modules = {
  'ORTestClass.pm' => $mod_content,
};

sub TestModuleProvider::INC {
  my ($self, $module) = @_;
  if (my $data = $self->{modules}{$module}) {
    open my $fh, '<', \$data
      or die "welp $!";
    return $fh;
  }
  return;
}

my %sources = (
  basic => [ 't/lib' ],
  sub => [ sub {
    if (my $data = $modules->{$_[1]}) {
      open my $fh, '<', \$data
        or die "welp $!";
      return $fh;
    }
    return;
  } ],
  dynamic_array => [ [ sub {
    my $mods = $_[0][1];
    if (my $data = $mods->{$_[1]}) {
      open my $fh, '<', \$data
        or die "welp $!";
      return $fh;
    }
    return;
  }, $modules ] ],
  object => [ bless { modules => $modules }, 'TestModuleProvider' ],
);

for my $source (sort keys %sources) {
  my $ms = Object::Remote::ModuleSender->new(
    dir_list => $sources{$source},
  );
  my $connection = Object::Remote::Connector::Local->new(
                  module_sender => $ms,
                  )->connect;

  my $counter = Object::Remote->new(
    connection => $connection,
    class => 'ORTestClass'
  );

  isnt($$, $counter->pid, "$source sender: Different pid on the other side");

  is($counter->counter, 0, "$source sender: Counter at 0");

  is($counter->increment, 1, "$source sender: Increment to 1");

  is($counter->counter, 1, "$source sender: Counter at 1");
}

done_testing;
