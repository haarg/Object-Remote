package Object::Remote::Logging::Logger;

use Moo;
use Scalar::Util qw(weaken);

has level_names => ( is => 'ro', required => 1 );
has min_level => ( is => 'ro', required => 1 );
has max_level => ( is => 'ro' );
has _level_active => ( is => 'lazy' );

sub BUILD {
  my ($self) = @_;
  our $METHODS_INSTALLED; 
  $self->_install_methods unless $METHODS_INSTALLED;
}

sub _build__level_active {
  my ($self) = @_; 
  my $should_log = 0;
  my $min_level = $self->min_level;
  my $max_level = $self->max_level;
  my %active;
    
  foreach my $level (@{$self->level_names}) {
    if($level eq $min_level) {
      $should_log = 1; 
    }

    $active{$level} = $should_log;
        
    if (defined $max_level && $level eq $max_level) {
      $should_log = 0;
    }
  }

  return \%active;
}

sub _install_methods {
  my ($self) = @_;
  my $should_log = 0;
  our $METHODS_INSTALLED = 1;
    
  no strict 'refs';
    
  foreach my $level (@{$self->level_names}) {
    *{"is_$level"} = sub { shift(@_)->_level_active->{$level} };
    *{$level} = sub { shift(@_)->_log($level, @_) };
  }
}

sub _log {
  my ($self, $level, $content, $metadata_in) = @_;
  #TODO this stinks but is backwards compatible with the original logger api
  my %metadata = %$metadata_in;
  my $rendered = $self->_render($level, \%metadata, @$content);
  $self->_output($rendered);
}

sub _render {
  my ($self, $level, $metadata, @content) = @_;
  my $rendered = "[$level] ";
  my $remote_info = $metadata->{object_remote};

  if ($remote_info) {
    $rendered .= "[connection #$remote_info->{connection_id}] ";
  } else {
    $rendered .= "[local] ";
  }
    
  $rendered .= join('', @content);
  $rendered .= "\n" unless substr($rendered, -1) eq "\n";
  return $rendered;
}

sub _output {
  my ($self, $content) = @_;
  print STDERR $content;
}


1;
