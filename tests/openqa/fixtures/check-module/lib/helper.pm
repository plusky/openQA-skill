# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP

package helper;
use strict;
use warnings;
use base 'Exporter';
use testapi;

sub wait_a_bit {
    sleep 1;
}

1;
