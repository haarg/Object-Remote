package Object::Remote::FatNode;

use strictures 1;
use Config;
use B qw(perlstring);

my @exclude_mods = qw(XSLoader.pm DynaLoader.pm);

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
  -e 'print join "\\n", \%INC'
);

$command =~ s/\n/ /g;

chomp(my @inc = qx($command));

my %exclude = map { $_ => 1 } @exclude_mods; 
my %mods = reverse @inc;

foreach(keys(%mods)) {
  if ($exclude{ $mods{$_} }) {
    delete($mods{$_});    
  }
}

sub filter_not_core {
  not (
    /^\Q$Config{privlibexp}/ or /^\Q$Config{archlibexp}/
  )        
}

my @file_names = keys %mods;
my @before_inc = grep { filter_not_core() } @file_names;
my @after_inc;

my $start = stripspace <<'END_START';
  # This chunk of stuff was generated by Object::Remote::FatNode. To find
  # the original file's code, look for the end of this BEGIN block or the
  # string 'FATPACK'
  BEGIN {
  my (%fatpacked,%fatpacked_extra);
END_START

$start .= 'my %exclude = map { $_ => 1 } (\'' . join("','", @exclude_mods) . "');\n";

my $end = stripspace <<'END_END';
  s/^  //mg for values %fatpacked, values %fatpacked_extra;

  sub load_from_hash {
    if (my $fat = $_[0]->{$_[1]}) {
      if ($exclude{$_[1]}) {
        warn "Will not pre-load '$_[1]'";
        return undef; 
      }
 
      #warn "Handling $_[1]";
      open my $fh, '<', \$fat;
      return $fh;
    }
    
    #Uncomment this to find brokenness
    #warn "Missing $_[1]";
    return;
  }

  unshift @INC, sub { load_from_hash(\%fatpacked, $_[1]) };
  push @INC, sub { load_from_hash(\%fatpacked_extra, $_[1]) };

  } # END OF FATPACK CODE

  use strictures 1;
  use Object::Remote::Node;
  Object::Remote::Node->run;
END_END

my %files = map +($mods{$_} => scalar do { local (@ARGV, $/) = ($_); <> }),
              @before_inc, @after_inc;

sub generate_fatpack_hash {
  my ($hash_name, $orig) = @_;
  (my $stub = $orig) =~ s/\.pm$//;
  my $name = uc join '_', split '/', $stub;
  my $data = $files{$orig} or die $orig; $data =~ s/^/  /mg;
  return '$'.$hash_name.'{'.perlstring($orig).qq!} = <<'${name}';\n!
  .qq!${data}${name}\n!;
}

my @segments = (
  map(generate_fatpack_hash('fatpacked', $_), sort map $mods{$_}, @before_inc),
  map(generate_fatpack_hash('fatpacked_extra', $_), sort map $mods{$_}, @after_inc),
);

our $DATA = join "\n", $start, @segments, $end;

1;
