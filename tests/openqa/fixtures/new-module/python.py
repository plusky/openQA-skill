# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP

# Package: my-tool my-tool-data
# Summary: Check that my-tool starts
# Maintainer: QE Team <qe-team@example.com>

from testapi import *


def run(self):
    perl.require('serial_terminal')
    perl.serial_terminal.select_serial_terminal()
    assert_script_run('my-tool --version', 'timeout', 120)
