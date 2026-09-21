# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP

# Package: my-tool my-tool-data
# Summary: Check that my-tool starts
# Maintainer: QE Team <qe-team@example.com>

use Mojo::Base 'consoletest';
use testapi;
use transactional;

sub run {
    select_console 'root-console';

    trup_call('pkg install my-tool my-tool-data');
    check_reboot_changes;
    assert_script_run 'rpm -q my-tool my-tool-data';
}

1;
