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
use package_utils qw(install_package uninstall_package);
use utils 'systemctl';

sub run {
    select_serial_terminal;

    install_package('my-tool my-tool-data', trup_reboot => 1);
    systemctl('enable --now my-tool');
    systemctl('is-active my-tool');
}

sub cleanup {
    systemctl('disable --now my-tool', ignore_failure => 1);
    uninstall_package('my-tool my-tool-data', trup_reboot => 1);
}

sub post_fail_hook {
    my ($self) = @_;
    $self->SUPER::post_fail_hook;
    cleanup();
}

sub post_run_hook {
    my ($self) = @_;
    cleanup();
    $self->SUPER::post_run_hook;
}

1;
