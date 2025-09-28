package Role;

$Role::VERSION    = '0.02';
$Role::AUTHORITY = 'cpan:MANWAR';

=head1 NAME

Role - A lightweight role composition system for Perl

=head1 VERSION

Version 0.02

=cut

use strict;
use warnings;

my %REQUIRED_METHODS;
my %IS_ROLE;
my %EXCLUDED_ROLES;
my %APPLIED_ROLES;
# Store method aliases for applied roles: $METHOD_ALIASES{Class}{Role} = { original_method => alias_method, ... }
my %METHOD_ALIASES;

=head1 SYNOPSIS

Quick role definition and consumption:

    # Define a role
    package Loggable {
        use Role;

        requires 'get_id';  # Consuming classes must implement this

        sub log {
            my ($self, $message) = @_;
            print "[" . localtime() . "] " . $self->get_id() . ": $message\n";
        }
    }

    # Use the role in a class
    package User {
        use Role 'Loggable';

        sub new {
            my ($class, $id, $name) = @_;
            bless { id => $id, name => $name }, $class;
        }

        sub get_id { $_[0]->{id} }  # Satisfies Loggable's requirement
    }

    # Usage
    my $user = User->new(123, 'Alice');
    $user->log('User logged in');  # Works!

Alternative syntax with C<with> and **Method Aliasing** for conflict resolution:

    package Product {
        use Role;
        with 'Loggable',
            {
                role => 'ConflictingRole',
                alias => { common_method => 'product_method' }
            };

        sub get_id { $_[0]->{sku} }
    }

Runtime role application:

    Role::apply_role($object, 'DebugRole');

=head1 DESCRIPTION

C<Role> provides a lightweight, pragmatic role composition system for Perl.
Roles are reusable units of behavior that can be composed into classes without
creating deep inheritance hierarchies. Unlike traditional inheritance, roles
allow for horizontal code reuse across unrelated classes.

This implementation focuses on simplicity and practicality, providing essential
role composition features without the complexity of larger object systems.

=head1 FEATURES

=head2 Supported Features

=over 4

=item * Basic Role Composition

Roles can provide methods that get copied into consuming classes:

    package Flyable {
        use Role;
        sub fly { "I'm flying!" }
    }

=item * Method Requirements

Roles can require consuming classes to implement specific methods:

    package Serializable {
        use Role;
        requires 'to_hash';

        sub serialize {
            my $self = shift;
            return JSON::encode_json($self->to_hash);
        }
    }

=item * Role Exclusion

Roles can declare incompatible roles:

    package RoleA {
        use Role;
        excludes 'RoleB';  # Cannot be composed with RoleB
    }

=item * Method Conflict Detection **(Automatic Resolution)**

Automatic detection and **resolution** of method naming conflicts. When a method
is composed, if the consuming class or any previously composed role already
provides a method with the same name, the **existing method takes precedence**
and the role method is silently discarded.

=item * **Method Aliasing / Renaming**

Methods from a role can be renamed during composition to resolve conflicts that would otherwise be resolved automatically by precedence. Use this if you need to retain the functionality of a lower-precedence role method. Pass a hashref to C<use Role> or C<with> instead of the role name:

    # Example: Rename 'run' from WorkerRole to 'worker_run'
    use Role { role => 'WorkerRole', alias => { run => 'worker_run' } };

=item * Runtime Role Application

Apply roles at runtime to classes or instances:

    Role::apply_role('MyClass', 'NewRole');
    Role::apply_role($object, 'DebugRole');

=item * Role Introspection

Check role relationships and applied roles:

    if ($object->does('Loggable')) {
        $object->log('Action performed');
    }

    my @roles = Role::get_applied_roles($object);
    if (Role::is_role('SomePackage')) { ... }

=item * Multiple Application Syntaxes

Use either direct application or C<with> syntax:

    # Direct
    package MyClass {
        use Role 'Role1', 'Role2';
    }

    # With syntax
    package MyClass {
        use Role;
        with 'Role1', 'Role2';
    }

=back

=head2 Missing Features

This module intentionally keeps a small footprint. The following features are
I<not> implemented:

=over 4

=item * Attribute Composition

Only method composition is supported; role attributes are not handled.

=item * Method Modifiers

No C<before>, C<after>, or C<around> method modifiers.

=item * Role Versioning

No support for role versions or compatibility checking.

=item * Advanced Role Algebra

No role unions, intersections, or other advanced compositions.

=item * Parameterized Roles

Roles cannot accept parameters during composition.

=back

=head1 EXPORTED FUNCTIONS

=head2 In Roles

The following functions are exported into packages that C<use Role;> (role definitions):

=head3 requires

    requires 'method1', 'method2';

Specifies methods that consuming classes must implement.

=head3 excludes

    excludes 'IncompatibleRole';

Declares roles that cannot be composed with this role.

=head2 In Classes

The following function is exported into packages that consume roles:

=head3 with

    with 'Role1',
        {
            role => 'Role2',
            alias => { old_name => 'new_name' }
        };

Alternative syntax for applying multiple roles, supporting method aliasing for conflict resolution.

=head1 CLASS METHODS

=head2 apply_role

    Role::apply_role($class_or_object, @roles);

Apply one or more roles to a class or object at runtime. Supports aliasing by passing a hashref for the role argument:

    Role::apply_role('MyClass', { role => 'Conflicting', alias => { run => 'conflicting_run' } });

=head2 get_applied_roles

    my @roles = Role::get_applied_roles($class_or_object);

Returns list of roles applied to a class or object.

=head2 is_role

    if (Role::is_role('SomePackage')) { ... }

Returns true if the given package is a role.

=head1 UNIVERSAL METHODS

=head2 does

    if ($obj->does('RoleName')) { ... }
    if (Class->does('RoleName')) { ... }

Returns true if the object or class consumes the specified role.

Also available as C<UNIVERSAL::does($obj, 'RoleName')>.

=cut

sub import {
    my ($class, @args) = @_;
    my $caller = caller;
    no strict 'refs';

    if (@args == 0) {
        $IS_ROLE{$caller} = 1;
        $REQUIRED_METHODS{$caller} = [];
        *{"${caller}::requires"} = \&requires;
        *{"${caller}::excludes"} = \&excludes;
    } else {
        _setup_role_application($caller, @args);
    }

    _export_with($caller);
}

sub _export_with {
    my $caller = shift;
    no strict 'refs';
    *{"${caller}::with"} = \&with unless (defined &{"${caller}::with"});
}

# Updated to support a list of roles or a hashref for roles with aliases
sub with {
    my (@roles) = @_;

    my $caller    = caller;

    # Process roles into a clean list of role names and a structure for aliases
    my ($clean_roles_ref, $aliases_by_role) = _process_role_arguments(@roles);

    # Store aliases for later use during composition
    $METHOD_ALIASES{$caller} = $aliases_by_role;

    my $roles_str = join ', ', map { "'$_'" } @$clean_roles_ref;

    my $init_code = qq{
        package $caller;

        # CRITICAL FIX: Using BEGIN to ensure composition runs before methods are called.
        BEGIN { Role::_apply_roles('$caller', $roles_str); }
        1;
    };

    eval $init_code or die "Failed to set up role application: $@";
}

# Updated to support a list of roles or a hashref for roles with aliases
sub _setup_role_application {
    my ($caller, @roles) = @_;

    my ($clean_roles_ref, $aliases_by_role) = _process_role_arguments(@roles);

    $METHOD_ALIASES{$caller} = $aliases_by_role;

    my $roles_str = join ', ', map { "'$_'" } @$clean_roles_ref;

    my $init_code = qq{
        package $caller;

        # CRITICAL FIX: Using BEGIN to ensure composition runs before methods are called.
        BEGIN { Role::_apply_roles('$caller', $roles_str); }
        1;
    };
    eval $init_code or die "Failed to set up role application: $@";
}

# Helper to process role arguments (accepts role names or { role => 'Name', alias => { ... } })
sub _process_role_arguments {
    my (@args) = @_;
    my @roles;
    my %aliases_by_role;

    foreach my $arg (@args) {
        if (ref $arg eq 'HASH' && $arg->{role}) {
            my $role = $arg->{role};
            push @roles, $role;
            if ($arg->{alias} && ref $arg->{alias} eq 'HASH') {
                $aliases_by_role{$role} = $arg->{alias};
            }
        } else {
            push @roles, $arg;
        }
    }

    return \@roles, \%aliases_by_role;
}

sub requires {
    my (@methods) = @_;
    my $caller = caller;

    $REQUIRED_METHODS{$caller} = [] unless exists $REQUIRED_METHODS{$caller};
    push @{$REQUIRED_METHODS{$caller}}, @methods;
}

sub excludes {
    my (@excluded_roles) = @_;
    my $caller = caller;

    $EXCLUDED_ROLES{$caller} = [] unless exists $EXCLUDED_ROLES{$caller};
    push @{$EXCLUDED_ROLES{$caller}}, @excluded_roles;
}

sub _apply_roles {
    my ($class, @roles) = @_;

    _apply_role($class, $_) for @roles;
    _add_does_method($class);
}

sub _apply_role {
    my ($class, $role) = @_;

    # Load the role if not already loaded
    unless ($IS_ROLE{$role}) {
        eval "require $role";
        unless ($IS_ROLE{$role}) {
            die "Failed to load role '$role': $@\n" .
                "Make sure $role package uses 'use Role;' and is properly defined";
        }
    }

    # Check if role is already applied
    if ($APPLIED_ROLES{$class} && grep { $_ eq $role } @{$APPLIED_ROLES{$class}}) {
        warn "Role '$role' is already applied to class '$class'";
        return;
    }

    # Check role exclusions
    if (my $excluded = $EXCLUDED_ROLES{$role}) {
        my @violated = grep { _class_does_role($class, $_) } @$excluded;
        if (@violated) {
            die "Role '$role' cannot be composed with role(s): @violated\n" .
                "Check the excludes declaration in $role";
        }
    }

    # Validate required methods
    my @missing;
    my $required = $REQUIRED_METHODS{$role} || [];
    foreach my $method (@$required) {
        unless ($class->can($method)) {
            push @missing, $method;
        }
    }

    if (@missing) {
        die "Role '$role' requires method(s) that are missing in class '$class': " .
            join(', ', @missing) . "\n" .
            "Implement these methods in $class to use role $role";
    }

    # Get aliases for this role in this class
    my $aliases_for_role = $METHOD_ALIASES{$class}->{$role} || {};
    # Reverse aliases are not strictly needed here, but kept for clarity/debugging.
    # my %reverse_aliases = reverse %$aliases_for_role;

    # Detect method conflicts (excluding special Role package methods)
    no strict 'refs';
    my $role_stash = \%{"${role}::"};
    my @conflicts;

    # We now only detect and die on a FATAL CONFLICT:
    # Attempting to alias a method to an existing name.
    # Standard name conflicts are resolved automatically below.

    foreach my $name (keys %$role_stash) {
        # Skip internal methods
        next if $name =~ /^(BEGIN|END|import|DESTROY|new|requires|excludes|IS_ROLE|with)$/;
        next if $name eq 'does';

        my $glob = $role_stash->{$name};

        # Only check for code subs
        next unless defined *{$glob}{CODE};

        # Find the method name that will be installed (either original or alias)
        my $install_name = $aliases_for_role->{$name} || $name;

        # Check for FATAL ALIAS CONFLICT:
        # If an alias is defined AND the target name already exists (and is not from this role itself).
        if ($install_name ne $name && $class->can($install_name)) {
            my $origin = _find_method_origin($class, $install_name);

            # If the alias target exists and didn't come from this role, it's a fatal conflict.
            if ($origin ne $role) {
                 push @conflicts, {
                    method => $name,
                    alias => $install_name,
                    from_role => $origin,
                    to_role => $role,
                    aliased => 1,
                };
            }
        }
    }

    if (@conflicts) {
        my $conflict_list = join "\n", map {
            my $msg = "$_->{method}";
            $msg .= " (aliased to $_->{alias})" if $_->{aliased};
            $msg .= " conflicts with $_->{from_role} when composing $_->{to_role}";
            $msg
        } @conflicts;
        die "Method conflict(s) when applying role '$role' to class '$class':\n$conflict_list\n" .
            "Resolve by using role exclusion or providing a different alias.";
    }

    # Apply the role methods (including AUTOMATIC CONFLICT RESOLUTION)
    foreach my $name (keys %$role_stash) {
        # Skip Role package internal methods
        next if $name =~ /^(BEGIN|END|import|DESTROY|new|requires|excludes|IS_ROLE|with)$/;
        next if $name eq 'does';

        my $glob = $role_stash->{$name};

        # Only apply code subs
        next unless defined *{$glob}{CODE};

        my $install_name = $aliases_for_role->{$name} || $name;

        # --- AUTOMATIC CONFLICT RESOLUTION ---
        # If the class already has this method name AND we are NOT aliasing it,
        # then an existing method (class or prior role) has precedence. SKIP IT.
        if ($class->can($install_name) && $install_name eq $name) {
            next;
        }
        # --- END RESOLUTION LOGIC ---

        no warnings 'redefine';
        *{"${class}::${install_name}"} = *{$glob}{CODE};
    }

    # Add to inheritance chain if not already there
    push @{"${class}::ISA"}, $role
        unless (grep { $_ eq $role } @{"${class}::ISA"});

    # Track applied roles
    $APPLIED_ROLES{$class} = [] unless exists $APPLIED_ROLES{$class};
    push @{$APPLIED_ROLES{$class}}, $role;
}

sub _find_method_origin {
    my ($class, $method) = @_;
    no strict 'refs';

    # Check if method comes from any applied role
    if ($APPLIED_ROLES{$class}) {
        foreach my $role (@{$APPLIED_ROLES{$class}}) {
            # Need to check if $method is the original name OR an alias name for this role
            my $aliases = $METHOD_ALIASES{$class}->{$role} || {};
            my %reverse_aliases = reverse %$aliases;

            my $original_name = $reverse_aliases{$method} || $method;

            # Check if the role defines the *original* method name or if the method
            # is the *alias* we installed from this role.
            if ($role->can($original_name) || exists $reverse_aliases{$method}) {
                return $role;
            }
        }
    }

    # Check inheritance chain
    for my $parent (@{"${class}::ISA"}) {
        return $parent if $parent->can($method);
    }

    return $class;  # Method defined in the class itself
}

sub _class_does_role {
    my ($class, $role) = @_;
    return 0 unless $IS_ROLE{$role};

    # Check if role is in inheritance chain
    no strict 'refs';
    return 1 if grep { $_ eq $role } @{"${class}::ISA"};

    # Check applied roles tracking
    return 1 if ($APPLIED_ROLES{$class} && grep { $_ eq $role } @{$APPLIED_ROLES{$class}});

    return 0;
}

sub _add_does_method {
    my ($class) = @_;

    no strict 'refs';
    no warnings 'redefine';

    *{"${class}::does"} = sub {
        my ($self, $role) = @_;
        return _class_does_role(ref($self) || $self, $role);
    };
}

sub UNIVERSAL::does {
    my ($self, $role) = @_;
    return _class_does_role(ref($self) || $self, $role);
}

# Runtime role application helper
sub apply_role {
    my ($class, @roles) = @_;

    # Handle both class names and instances
    my $target_class = ref($class) ? ref($class) : $class;

    my ($clean_roles_ref, $aliases_by_role) = _process_role_arguments(@roles);

    # Merge or overwrite existing aliases
    $METHOD_ALIASES{$target_class} = {
        %{$METHOD_ALIASES{$target_class} || {}},
        %$aliases_by_role
    };

    foreach my $role (@$clean_roles_ref) {
        _apply_role($target_class, $role);
    }
    _add_does_method($target_class);

    return 1;
}

# Get all roles applied to a class
sub get_applied_roles {
    my ($class) = @_;
    my $target_class = ref($class) ? ref($class) : $class;

    return @{$APPLIED_ROLES{$target_class} || []};
}

# Check if a package is a role
sub is_role {
    my ($package) = @_;
    return $IS_ROLE{$package};
}

=head1 EXAMPLES

=head2 Complete Example: E-commerce Domain

    package Shippable {
        use Role;
        requires 'get_weight', 'get_dimensions';

        sub calculate_shipping {
            my ($self, $destination) = @_;
            # Calculate shipping logic
            return $shipping_cost;
        }
    }

    package Taxable {
        use Role;
        requires 'get_price';

        sub calculate_tax {
            my ($self, $tax_rate) = @_;
            return $self->get_price() * $tax_rate;
        }
    }

    package Product {
        use Role 'Shippable', 'Taxable';

        sub new {
            my ($class, %attrs) = @_;
            bless \%attrs, $class;
        }

        sub get_weight { $_[0]->{weight} }
        sub get_dimensions { $_[0]->{dimensions} }
        sub get_price { $_[0]->{price} }
    }

    my $product = Product->new(
        weight => 2.5,
        dimensions => [10, 5, 3],
        price => 29.99
    );

    my $shipping = $product->calculate_shipping('US');
    my $tax = $product->calculate_tax(0.08);

=head2 Advanced: Role Exclusion

    package MemoryCache {
        use Role;
        excludes 'DiskCache';

        sub cache_get { ... }
        sub cache_set { ... }
    }

    package DiskCache {
        use Role;
        excludes 'MemoryCache';

        sub cache_get { ... }
        sub cache_set { ... }
    }

    # This will die with exclusion error:
    package BadCache {
        use Role 'MemoryCache', 'DiskCache';  # ERROR!
    }

=head2 Runtime Role Application

    package Debuggable {
        use Role;
        sub debug_info {
            my $self = shift;
            return "Instance of " . ref($self);
        }
    }

    package Customer {
        sub new { bless {}, shift }
    }

    # Apply role at runtime
    my $customer = Customer->new();
    Role::apply_role($customer, 'Debuggable');
    print $customer->debug_info();  # Now works!

=head1 DIAGNOSTICS

=head2 Error Messages

=over 4

=item * C<Role '%s' requires method(s) that are missing in class '%s': %s>

The class doesn't implement all methods required by the role.

=item * C<Method conflict(s) when applying role '%s' to class '%s': %s>

**Fatal Conflict:** This only occurs when attempting to **alias a method to a name that already exists** in the class or a previously applied role. Standard method name conflicts are resolved automatically by precedence.

=item * C<Role '%s' cannot be composed with role(s): %s>

Role exclusion violation detected.

=item * C<Role '%s' is already applied to class '%s'>

Warning when attempting to apply the same role multiple times.

=item * C<Failed to load role '%s': %s>

The role package couldn't be loaded or doesn't use C<Role>.

=back

=head2 Common Issues

=over 4

=item * Forgetting C<use Role;> in role definitions

Role packages must include C<use Role;> to be recognized as roles.

=item * Method name conflicts with UNIVERSAL

Avoid using method names like C<can>, C<isa>, etc., which may conflict with UNIVERSAL methods.

=item * Circular dependencies

Use role exclusion to prevent circular composition attempts.

=back

=head1 CAVEATS AND LIMITATIONS

=over 4

=item * Inheritance vs Composition

Roles are added to C<@ISA>, which affects method resolution order. This is simpler but less sophisticated than other role systems.

=item * Global State

Role metadata is stored in package variables. This works well for typical use cases but may have limitations in complex environments.

=item * No Namespacing

All roles share the same global namespace for requirements and exclusions.

=item * Development Focus

This module prioritizes simplicity and ease of use over comprehensive feature sets.

=back

=head1 SEE ALSO

=over 4

=item * L<Moo::Role> - More feature-complete role system for Moo

=item * L<Moose::Role> - Full-featured role system for Moose

=item * L<Role::Tiny> - Minimalist role composition

=item * L<Class::Role> - Another role implementation

=back

=head1 LIMITATIONS

Please report any bugs or feature requests through the GitHub repository at:
L<https://github.com/yourusername/Role>

Known limitations include:

=over 4

=item * No Windows support testing (but should work)

=item * Limited performance testing on large role systems

=item * Documentation examples are basic

=back

=head1 AUTHOR

Mohammad Sajid Anwar, C<< <mohammad.anwar at yahoo.com> >>

=head1 REPOSITORY

L<https://github.com/manwar/Role>

=head1 BUGS

Please report any bugs or feature requests through the web interface at L<https://github.com/manwar/Role/issues>.
I will  be notified and then you'll automatically be notified of progress on your
bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Role

You can also look for information at:

=over 4

=item * BUG Report

L<https://github.com/manwar/Role/issues>

=back

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2025 Mohammad Sajid Anwar.

This program  is  free software; you can redistribute it and / or modify it under
the  terms  of the the Artistic License (2.0). You may obtain a  copy of the full
license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any  use,  modification, and distribution of the Standard or Modified Versions is
governed by this Artistic License.By using, modifying or distributing the Package,
you accept this license. Do not use, modify, or distribute the Package, if you do
not accept this license.

If your Modified Version has been derived from a Modified Version made by someone
other than you,you are nevertheless required to ensure that your Modified Version
 complies with the requirements of this license.

This  license  does  not grant you the right to use any trademark,  service mark,
tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge patent license
to make,  have made, use,  offer to sell, sell, import and otherwise transfer the
Package with respect to any patent claims licensable by the Copyright Holder that
are  necessarily  infringed  by  the  Package. If you institute patent litigation
(including  a  cross-claim  or  counterclaim) against any party alleging that the
Package constitutes direct or contributory patent infringement,then this Artistic
License to you shall terminate on the date that such litigation is filed.

Disclaimer  of  Warranty:  THE  PACKAGE  IS  PROVIDED BY THE COPYRIGHT HOLDER AND
CONTRIBUTORS  "AS IS'  AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES. THE IMPLIED
WARRANTIES    OF    MERCHANTABILITY,   FITNESS   FOR   A   PARTICULAR  PURPOSE, OR
NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY YOUR LOCAL LAW. UNLESS
REQUIRED BY LAW, NO COPYRIGHT HOLDER OR CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT,
INDIRECT, INCIDENTAL,  OR CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE
OF THE PACKAGE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut

1; # End of Role
