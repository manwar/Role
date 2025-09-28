package TestClass::Requires::Success;
use Role;
with 'TestRole::Requires';

sub new { bless {}, shift }
sub implemented_method { "Implemented" }
sub mandatory_method { "Mandatory" } # Required by TestRole::Requires

1;
