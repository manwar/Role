package TestClass::Requires::Fail;
# This file is intentionally designed to fail compilation/init
# It will be loaded inside an eval block in the test script.
use Role;
with 'TestRole::Requires';
1;
