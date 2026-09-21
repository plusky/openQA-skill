# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: Python fixture without findings
# Maintainer: QE Team <qe-team@example.com>

from testapi import *


def run(self):
    perl.require('serial_terminal')
    perl.serial_terminal.select_serial_terminal()
    assert_script_run('true', 'timeout', 120)
