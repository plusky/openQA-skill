# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP

# Package: my-tool my-tool-data
# Summary: Check that my-tool starts
# Maintainer: QE Team <qe-team@example.com>

use Mojo::Base 'x11test';
use testapi;

sub run {
    select_console 'x11';
    ensure_installed('my-tool my-tool-data', timeout => 300);
    x11_start_program('my-tool');
    send_key_until_needlematch 'generic-desktop', 'alt-f4', 6, 5;
}

1;
