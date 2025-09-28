package TestClass::Basic;
use Role;

with 'TestRole::Basic';

sub new { bless {}, shift } # Add simple constructor
sub class_method { "Class" }

1;
