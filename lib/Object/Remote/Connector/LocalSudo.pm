package Object::Remote::Connector::LocalSudo;

use Symbol qw(gensym);
use Module::Runtime qw(use_module);
use IPC::Open3;
use Moo;

extends 'Object::Remote::Connector::Local';

has target_user => (is => 'ro', required => 1);

has password_callback => (is => 'lazy');

sub _build_password_callback {
  my ($self) = @_;
  my $pw_prompt = use_module('Object::Remote::Prompt')->can('prompt_pw');
  my $user = $self->target_user;
  return sub {
    $pw_prompt->("sudo password for ${user}", undef, { cache => 1 })
  }
}

sub _sudo_perl_command {
  my ($self) = @_;
  return
    'sudo', '-S', '-u', $self->target_user, '-p', "[sudo] password please\n",
    'perl', '-MPOSIX=dup2',
            '-e', 'print STDERR "GO\n"; exec(@ARGV);',
    $self->_perl_command($self->target_user);
}

sub _start_perl {
  my $self = shift;
  my $sudo_stderr = gensym;
  my $pid = open3(
    my $foreign_stdin,
    my $foreign_stdout,
    $sudo_stderr,
    $self->_sudo_perl_command(@_)
  ) or die "open3 failed: $!";
  chomp(my $line = <$sudo_stderr>);
  if ($line eq "GO") {
    # started already, we're good
  } elsif ($line =~ /\[sudo\]/) {
    my $cb = $self->password_callback;
    die "sudo sent ${line} but we have no password callback"
      unless $cb;
    print $foreign_stdin $cb->($line, @_), "\n";
    chomp($line = <$sudo_stderr>);
    if ($line and $line ne 'GO') {
      die "sent password and expected newline from sudo, got ${line}";
    }
    elsif (not $line) {
      chomp($line = <$sudo_stderr>);
      die "sent password but next line was ${line}"
        unless $line eq "GO";
    }
  } else {
    die "Got inexplicable line ${line} trying to sudo";
  };
  Object::Remote->current_loop
                ->watch_io(
                    handle => $sudo_stderr,
                    on_read_ready => sub {
                      if (sysread($sudo_stderr, my $buf, 1024) > 0) {
                        print STDERR $buf;
                      } else {
                        Object::Remote->current_loop
                                      ->unwatch_io(
                                          handle => $sudo_stderr,
                                          on_read_ready => 1
                                        );
                      }
                    }
                  );
  return ($foreign_stdin, $foreign_stdout, $pid);
};

no warnings 'once';

push @Object::Remote::Connection::Guess, sub {
  for ($_[0]) {
    # username followed by @
    if (defined and !ref and /^ ([^\@]*?) \@ $/x) {
      return __PACKAGE__->new(target_user => $1)->connect;
    }
  }
  return;
};

1;
