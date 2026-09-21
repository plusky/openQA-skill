# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP

# Package: my-tool my-tool-data
# Summary: Check that my-tool starts
# Maintainer: QE Team <qe-team@example.com>

use Mojo::Base 'containers::basetest';
use testapi;
use serial_terminal 'select_serial_terminal';
use utils 'script_retry';

my $engine;

sub run {
    my ($self, $args) = @_;
    my $runtime = $args->{runtime};

    select_serial_terminal;
    $engine = $self->containers_factory($runtime);

    my $image = get_var('CONTAINER_IMAGE_TO_TEST', 'registry.opensuse.org/opensuse/tumbleweed:latest');
    script_retry("$runtime pull $image", timeout => 300, delay => 60, retry => 3);
    validate_script_output "$runtime run --rm $image cat /etc/os-release", qr/ID=/;
}

sub cleanup {
    $engine->cleanup_system_host();
}

sub post_fail_hook {
    my ($self) = @_;
    cleanup();
    $self->SUPER::post_fail_hook;
}

sub post_run_hook {
    my ($self) = @_;
    cleanup();
    $self->SUPER::post_run_hook;
}

sub test_flags {
    return {fatal => 0};
}

1;
