package TestClass::Conflict::Fatal;
use Role;
with 'TestRole::Basic', 'TestRole::Conflicting'; # Conflict on common_method

sub new { bless {}, shift }

1;
