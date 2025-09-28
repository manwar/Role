package TestClass::Excludes::Fail;
use Role;
with 'TestRole::Basic', 'TestRole::Excludes'; # Conflict here!

sub new { bless {}, shift }

1;
