use strict;
use warnings;
use Test::More;

# Set up the class path for test roles and classes
use FindBin qw($Bin);
use lib "$Bin/../lib";
use lib "$Bin/";

# ----------------------------------------------------------------------
# 1. Basic Role Application
# ----------------------------------------------------------------------
eval { require TestClass::Basic; };
is($@, '', 'SUCCESS: TestClass::Basic loaded successfully with role');

my $basic_obj = TestClass::Basic->new;

isa_ok($basic_obj, 'TestClass::Basic', 'TestClass::Basic object created');
can_ok('TestClass::Basic', 'common_method');
is($basic_obj->common_method, 'Basic', 'Role method returns correct value');
is($basic_obj->class_method, 'Class', 'Class method is intact');
ok($basic_obj->does('TestRole::Basic'), 'TestClass::Basic does TestRole::Basic');


# ----------------------------------------------------------------------
# 2. Required Methods Check (Should fail - TestClass::Requires::Fail)
# ----------------------------------------------------------------------
eval { require TestClass::Requires::Fail; };
like($@, qr/Role 'TestRole::Requires' requires method\(s\) that are missing.*mandatory_method/,
    'FAIL: Applying role with missing required methods dies with correct error');


# Required Methods Check (Should succeed - TestClass::Requires::Success)
eval { require TestClass::Requires::Success; };
is($@, '', 'SUCCESS: TestClass::Requires::Success loaded with all required methods implemented');
can_ok('TestClass::Requires::Success', 'required_method_body');


# ----------------------------------------------------------------------
# 3. Exclusion Conflict Check (Should fail)
# ----------------------------------------------------------------------
eval { require TestClass::Excludes::Fail; };
like($@, qr/Role 'TestRole::Excludes' cannot be composed with role\(s\): TestRole::Basic/,
    'FAIL: Applying excluded role dies with correct error');


# ----------------------------------------------------------------------
# 4. Method Conflict Check (Now Automatic Resolution)
# ----------------------------------------------------------------------
# This test must now check for SUCCESS and PRECEDENCE, not FAILURE.
# Assuming TestClass::Conflict::Fatal uses TestRole::Basic then TestRole::Conflicting.

my $conflict_loaded = 0;
local $@; # Isolate error variable
eval { require TestClass::Conflict::Fatal; $conflict_loaded = 1; };

is($@, '', 'SUCCESS: Automatic conflict resolution succeeds and class loads');

if ($conflict_loaded) {
    # Check precedence: First role (TestRole::Basic) should win.
    my $conflict_obj = TestClass::Conflict::Fatal->new;
    is($conflict_obj->common_method, 'Basic',
        'Precedence check: First applied role (Basic) wins the conflict');
} else {
    # If loading failed for some reason, ensure we don't crash
    fail('Precedence check: TestClass::Conflict::Fatal failed to load for unknown reason.');
    fail('Precedence check: TestClass::Conflict::Fatal failed to load for unknown reason.');
}


# ----------------------------------------------------------------------
# 5. Method Aliasing (Should succeed)
# ----------------------------------------------------------------------
eval { require TestClass::Conflict::Aliased; };
is($@, '', 'SUCCESS: Method conflict resolved with aliasing and class loaded');

my $aliased_obj = TestClass::Conflict::Aliased->new;
is($aliased_obj->common_method, 'Basic', 'Aliased role: Original method from first role is retained');
can_ok('TestClass::Conflict::Aliased', 'conflicting_method_aliased');
is($aliased_obj->conflicting_method_aliased, 'Conflicting', 'Aliased role: Conflicting method is installed under alias');


# ----------------------------------------------------------------------
# 6. Alias Conflict (Should fail if alias target already exists)
# ----------------------------------------------------------------------
eval { require TestClass::Alias::Conflict; };
# FIX: Added (?s:...) for multiline match
like($@, qr/(?s:Method conflict.*exclusive_method \(aliased to common_method\).*TestRole::Basic.*TestRole::Conflicting)/,
    'FATAL: Alias target conflict dies with correct error');


# ----------------------------------------------------------------------
# 7. Runtime apply_role and does()
# ----------------------------------------------------------------------
{
    package Class::Runtime;
    use Role;
    sub new { bless {}, shift }
}

ok(!Class::Runtime->new->does('TestRole::Basic'), 'does() returns false before runtime application');

eval {
    Role::apply_role('Class::Runtime', 'TestRole::Basic');
};
is($@, '', 'SUCCESS: Runtime role application works');

my $runtime_obj = Class::Runtime->new;
ok($runtime_obj->does('TestRole::Basic'), 'does() returns true after runtime application');
can_ok('Class::Runtime', 'common_method');


# ----------------------------------------------------------------------
# Final count
# ----------------------------------------------------------------------
done_testing();
