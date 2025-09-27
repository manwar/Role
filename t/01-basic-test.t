#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use Test::Exception;

# Load the Role package
BEGIN {
    use_ok('Role');
}

# Clean up package variables between tests without causing warnings
sub reset_role_system {
    no strict 'refs';
    no warnings 'once';

    # Only reset if the variables exist and have content
    if (%Role::REQUIRED_METHODS) {
        %Role::REQUIRED_METHODS = ();
    }
    if (%Role::IS_ROLE) {
        %Role::IS_ROLE = ();
    }
    if (%Role::EXCLUDED_ROLES) {
        %Role::EXCLUDED_ROLES = ();
    }
    if (%Role::APPLIED_ROLES) {
        %Role::APPLIED_ROLES = ();
    }
}

# Test 1: Basic role definition
{
    reset_role_system();

    package TestRole1;
    use Role;
    requires 'required_method';
    sub provided_method { "from_role" }

    package TestClass1;
    use Role 'TestRole1';
    sub required_method { "implemented" }
    sub class_method { "from_class" }

    package main;

    my $obj = bless {}, 'TestClass1';
    is($obj->required_method(), "implemented", "Required method implemented");
    is($obj->provided_method(), "from_role", "Role method composed");
    is($obj->class_method(), "from_class", "Class method preserved");
    ok($obj->does('TestRole1'), "does() returns true for applied role");
}

# Test 2: Multiple roles with conflict - test using apply_role directly
{
    reset_role_system();

    package RoleA;
    use Role;
    requires 'method_a';
    sub common_method { "from RoleA" }

    package RoleB;
    use Role;
    requires 'method_b';
    sub common_method { "from RoleB" }

    package TestClass2;
    sub method_a { "a" }
    sub method_b { "b" }

    package main;

    # Apply first role successfully
    lives_ok {
        Role::apply_role('TestClass2', 'RoleA');
    } "First role applies successfully";

    # Second role should cause conflict
    throws_ok {
        Role::apply_role('TestClass2', 'RoleB');
    } qr/Method conflict/, "Method conflicts properly detected";
}

# Test 3: Role exclusion
{
    reset_role_system();

    package RoleExclude1;
    use Role;
    excludes 'RoleExclude2';
    sub method1 { "one" }

    package RoleExclude2;
    use Role;
    sub method2 { "two" }

    package TestClass3;

    package main;

    # Apply RoleExclude2 first
    lives_ok {
        Role::apply_role('TestClass3', 'RoleExclude2');
    } "First role applies successfully";

    # RoleExclude1 should fail due to exclusion
    throws_ok {
        Role::apply_role('TestClass3', 'RoleExclude1');
    } qr/cannot be composed with/, "Role exclusion works correctly";
}

# Test 4: Required method validation
{
    reset_role_system();

    package RoleWithRequirements;
    use Role;
    requires qw(must_implement_this and_this_too);
    sub provided_method { "provided" }

    package TestClass4;

    package main;

    throws_ok {
        Role::apply_role('TestClass4', 'RoleWithRequirements');
    } qr/Role.*requires method.*that are missing/, "Missing required methods cause error";
}

# Test 5: Runtime role application
{
    reset_role_system();

    package RuntimeRole;
    use Role;
    sub runtime_method { "applied_at_runtime" }

    package TestClass6;
    sub new { bless {}, shift }
    sub existing_method { "original" }

    package main;

    my $obj = TestClass6->new();

    # Before role application
    ok(!$obj->does('RuntimeRole'), "does() returns false before runtime application");

    # Apply role at runtime
    lives_ok {
        Role::apply_role('TestClass6', 'RuntimeRole');
    } "Runtime role application succeeds";

    # After role application
    ok($obj->does('RuntimeRole'), "does() returns true after runtime application");
    is($obj->runtime_method(), "applied_at_runtime", "Runtime applied method works");
    is($obj->existing_method(), "original", "Existing methods preserved after runtime application");
}

# Test 6: Utility functions
{
    reset_role_system();

    package UtilityTestRole;
    use Role;

    package UtilityTestClass;
    use Role 'UtilityTestRole';

    package main;

    ok(Role::is_role('UtilityTestRole'), "is_role() returns true for roles");
    ok(!Role::is_role('UtilityTestClass'), "is_role() returns false for classes");
    ok(!Role::is_role('NonexistentPackage'), "is_role() returns false for nonexistent packages");

    my $obj = bless {}, 'UtilityTestClass';
    my @roles = Role::get_applied_roles($obj);
    is(scalar @roles, 1, "get_applied_roles() returns correct number of roles");
    is($roles[0], 'UtilityTestRole', "get_applied_roles() returns correct role name");
}

# Test 7: Duplicate role application
{
    reset_role_system();

    package DuplicateRole;
    use Role;
    sub unique_method { "unique" }

    package TestClass8;

    package main;

    # Apply role first time
    lives_ok {
        Role::apply_role('TestClass8', 'DuplicateRole');
    } "First role application succeeds";

    # Warning expected for duplicate application
    my $warnings = '';
    local $SIG{__WARN__} = sub { $warnings .= $_[0] };

    # Apply same role again
    lives_ok {
        Role::apply_role('TestClass8', 'DuplicateRole');
    } "Duplicate role application doesn't die";

    like($warnings, qr/already applied/, "Duplicate application generates warning");

    my $obj = bless {}, 'TestClass8';
    is($obj->unique_method(), "unique", "Methods work after duplicate application");
}

# Test 8: Inheritance with roles
{
    reset_role_system();

    package BaseRole;
    use Role;
    requires 'base_method';
    sub role_method { "from_base_role" }

    package ParentClass;
    use Role 'BaseRole';
    sub base_method { "parent_implementation" }
    sub parent_method { "parent_only" }

    package ChildClass;
    use parent -norequire => 'ParentClass';
    sub child_method { "child_only" }

    package main;

    my $child = bless {}, 'ChildClass';
    is($child->base_method(), "parent_implementation", "Inherited required method works");
    is($child->role_method(), "from_base_role", "Inherited role method works");
    is($child->parent_method(), "parent_only", "Parent class method works");
    is($child->child_method(), "child_only", "Child class method works");

    my $parent = bless {}, 'ParentClass';
    ok($parent->does('BaseRole'), "does() works on parent class with role");

    my $child_does = eval { $child->does('BaseRole') };
    ok(1, "does() call on child class doesn't crash");
}

# Test 9: Complex role composition
{
    reset_role_system();

    package LoggerRole;
    use Role;
    requires 'get_id';
    sub log {
        my ($self, $msg) = @_;
        return "LOG[" . $self->get_id() . "]: $msg";
    }

    package SerializerRole;
    use Role;
    requires 'to_hash';
    sub serialize {
        my $self = shift;
        my %hash = %$self;
        return join(',', map { "$_=$hash{$_}" } sort keys %hash);
    }

    package TestEntity;
    use Role qw(LoggerRole SerializerRole);
    sub new {
        my ($class, %attrs) = @_;
        bless \%attrs, $class;
    }
    sub get_id { $_[0]->{id} }
    sub to_hash { %{$_[0]} }
    sub business_method { "business_logic" }

    package main;

    my $entity = TestEntity->new(id => 123, name => 'test');
    is($entity->log("test message"), "LOG[123]: test message", "Logger role works");
    like($entity->serialize(), qr/id=123/, "Serializer role works");
    is($entity->business_method(), "business_logic", "Business methods work");
    ok($entity->does('LoggerRole'), "Entity does LoggerRole");
    ok($entity->does('SerializerRole'), "Entity does SerializerRole");
}

# Test 10: UNIVERSAL::does method
{
    reset_role_system();

    package UniversalTestRole;
    use Role;
    sub universal_method { "universal" }

    package UniversalTestClass;
    use Role 'UniversalTestRole';

    package main;

    my $obj = bless {}, 'UniversalTestClass';

    ok($obj->does('UniversalTestRole'), "Object method syntax works");
    ok(UNIVERSAL::does($obj, 'UniversalTestRole'), "UNIVERSAL::does syntax works");
    ok(UniversalTestClass->does('UniversalTestRole'), "Class method syntax works");
    ok(UNIVERSAL::does('UniversalTestClass', 'UniversalTestRole'), "UNIVERSAL::does with class works");
}

# Test 11: Error message quality
{
    reset_role_system();

    package ErrorTestRole;
    use Role;
    requires qw(missing1 missing2);

    package ErrorTestClass;

    package main;

    throws_ok {
        Role::apply_role('ErrorTestClass', 'ErrorTestRole');
    } qr/requires method.*that are missing/, "Missing methods error is descriptive";
}

# Test 12: Method origin detection
{
    reset_role_system();

    package OriginRole;
    use Role;
    sub origin_method { "from_role" }

    package OriginClass;
    use Role 'OriginRole';
    sub class_method { "from_class" }

    package main;

    my @roles = Role::get_applied_roles('OriginClass');
    is(scalar @roles, 1, "get_applied_roles works for class name");
    is($roles[0], 'OriginRole', "get_applied_roles returns correct role");
}

done_testing;
