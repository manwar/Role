package TestClass::Alias::Conflict;
use Role;
with
    'TestRole::Basic', # Provides common_method
    {
        role => 'TestRole::Conflicting',
        alias => { exclusive_method => 'common_method' } # Tries to alias to an existing method
    };

sub new { bless {}, shift }

1;
