use strictures 1;
use Test::More;
use FindBin;

use lib "$FindBin::Bin/lib";

use Object::Remote;

my $user = $ENV{TEST_SUDOUSER}
    or plan skip_all => q{Requires TEST_SUDOUSER to be set};

my $remote = TestFindUser->new::on($user . '@');
my $remote_user = $remote->user;
like $remote_user, qr/^\d+$/, 'returned an int';
isnt $remote_user, $<, 'ran as different user';

done_testing;
