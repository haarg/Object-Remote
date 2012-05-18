package Object::Remote::Connector::Local;

use IPC::Open2;
use Moo;

with 'Object::Remote::Role::Connector';

sub _open2_for {
  my $open_this = (
    -d 't' && -e 'bin/object-remote-node'
      ? 'bin/object-remote-node'
      : 'object-remote-node'
  );
  my $pid = open2(my $its_stdout, my $its_stdin, 'bin/object-remote-node')
    or die "Couldn't start local node: $!";
  return ($its_stdin, $its_stdout, $pid);
}

push @Object::Remote::Connection::Guess, sub {
  if (($_[0]||'') eq '-') { __PACKAGE__->new->connect }
};

1;
