# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP

# Package: my-tool my-tool-data
# Summary: Check that my-tool starts
# Maintainer: QE Team <qe-team@example.com>

use Mojo::Base 'consoletest';
use testapi;
use serial_terminal 'select_serial_terminal';
use package_utils 'install_package';

sub run {
    select_serial_terminal;

    install_package('my-tool my-tool-data', trup_apply => 1) if script_run('rpm -q my-tool my-tool-data');
    record_info('Version', script_output('rpm -q my-tool my-tool-data'));
    assert_script_run 'my-tool --version';
}

1;
