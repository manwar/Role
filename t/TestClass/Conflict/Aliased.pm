package TestClass::Conflict::Aliased;
use Role;
with
    'TestRole::Basic',
    {
        role => 'TestRole::Conflicting',
        alias => { common_method => 'conflicting_method_aliased' }
    };

sub new { bless {}, shift }

1;
