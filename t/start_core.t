use strictures 1;
use Test::More;
use Object::Remote;
use File::Spec;

{
  package S1S;

  use Moo;

  sub get_s2 {
    S2S->new
  }
}

{
  package S1F;

  use Object::Remote::Future;
  use Moo;

  our $C;

  sub get_s2 {
    future {
      my $f = shift;
      $C = sub { $f->done(S2F->new); undef($f); undef($C); };
      $f;
    }
  }
}

{
  package S2S;

  use Moo;

  sub get_s3 { 'S3' }
}

{
  package S2F;

  use Object::Remote::Future;
  use Moo;

  our $C;

  sub get_s3 {
    future {
      my $f = shift;
      $C = sub { $f->done('S3'); undef($f); undef($C); };
      $f;
    }
  }
}

my $res;

S1S->start::get_s2->then::get_s3->on_ready(sub { ($res) = $_[0]->get });

is($res, 'S3', 'Synchronous code ok');

undef($res);

S1F->start::get_s2->then::get_s3->on_ready(sub { ($res) = $_[0]->get });

ok(!$S2F::C, 'Second future not yet constructed');

$S1F::C->();

ok($S2F::C, 'Second future constructed after first future completed');

ok(!$res, 'Nothing happened yet');

$S2F::C->();

is($res, 'S3', 'Asynchronous code ok');

is(S1S->get_s2->get_s3, 'S3', 'Sync without start');

open my $fh, '<', File::Spec->devnull;

Object::Remote->current_loop->watch_io(
  handle => $fh,
  on_read_ready => sub {
    $S1F::C->() if defined $S1F::C;
    $S2F::C->() if defined $S2F::C;
  }
);

is(S1F->get_s2->get_s3, 'S3', 'Async without start');

done_testing;
