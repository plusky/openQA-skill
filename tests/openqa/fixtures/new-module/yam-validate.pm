# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP

# Package: my-tool my-tool-data
# Summary: Check that my-tool starts
# Maintainer: QE Team <qe-team@example.com>

use Mojo::Base 'consoletest';
use scheduler 'get_test_suite_data';
use testapi;

sub run {
    select_console 'root-console';

    my $expected = get_test_suite_data()->{my_tool};
    assert_script_run "grep -q '$expected->{value}' /etc/os-release";
}

1;
