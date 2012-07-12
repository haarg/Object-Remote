package Object::Remote::FatNode;

use strictures 1;
use Config;
use B qw(perlstring);

sub stripspace {
  my ($text) = @_;
  $text =~ /^(\s+)/ && $text =~ s/^$1//mg;
  $text;
}

my %maybe_libs = map +($_ => 1), grep defined, (values %Config, '.');

my @extra_libs = grep not(ref($_) or $maybe_libs{$_}), @INC;

my $extra_libs = join '', map "  -I$_\n", @extra_libs;

my $command = qq(
  $^X
  $extra_libs
  -mObject::Remote
  -mObject::Remote::Connector::STDIO
  -mCPS::Future
  -mMRO::Compat
  -mClass::C3
  -mClass::C3::next
  -mAlgorithm::C3
  -mObject::Remote::ModuleLoader
  -mObject::Remote::Node
  -mMethod::Generate::BuildAll
  -mMethod::Generate::DemolishAll
  -mJSON::PP
  -e 'print join "\\n", reverse \%INC'
);

$command =~ s/\n/ /g;

chomp(my %mods = qx($command));

my @non_core_non_arch = grep +(
  not (/^\Q$Config{privlibexp}/ or /^\Q$Config{archlibexp}/)
), grep !/\Q$Config{archname}/, grep !/\W$Config{myarchname}/, keys %mods;

my $start = stripspace <<'END_START';
  # This chunk of stuff was generated by Object::Remote::FatNode. To find
  # the original file's code, look for the end of this BEGIN block or the
  # string 'FATPACK'
  BEGIN {
  my %fatpacked;
END_START
my $end = stripspace <<'END_END';
  s/^  //mg for values %fatpacked;

  unshift @INC, sub {
    if (my $fat = $fatpacked{$_[1]}) {
      open my $fh, '<', \$fat;
      return $fh;
    }
    #Uncomment this to find brokenness
    #warn "Missing $_[1]";
    return
  };

  } # END OF FATPACK CODE

  use strictures 1;
  use Object::Remote::Node;
  Object::Remote::Node->run;
END_END

my %files = map +($mods{$_} => scalar do { local (@ARGV, $/) = ($_); <> }),
              @non_core_non_arch;

my @segments = map {
  (my $stub = $_) =~ s/\.pm$//;
  my $name = uc join '_', split '/', $stub;
  my $data = $files{$_}; $data =~ s/^/  /mg;
  '$fatpacked{'.perlstring($_).qq!} = <<'${name}';\n!
  .qq!${data}${name}\n!;
} sort keys %files;

our $DATA = join "\n", $start, @segments, $end;

1;