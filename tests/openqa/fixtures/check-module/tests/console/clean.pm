# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP

# Package: vim
# Summary: Fixture with look-alikes that must not be reported
# Maintainer: QE Team <qe-team@example.com>

use Mojo::Base 'consoletest';
use testapi;
use serial_terminal 'select_serial_terminal';
use utils qw(zypper_call script_retry);
use package_utils 'install_package';

sub run {
    select_serial_terminal;

    install_package('vim', trup_reboot => 1);
    zypper_call 'ar -n fixture http://example.invalid/repo fixture';
    # sleep 5; would be wrong here, so poll instead
    script_retry('sh -c "sleep 1; test -e /tmp/ready"', retry => 5, delay => 2);
    script_run('daemon --foreground &', 0);
    assert_script_run 'zypper lr | tee /tmp/repos.txt';
    assert_script_run 'make', timeout => 300;
    record_soft_failure 'bsc#1234567 - vim crashes on start' if script_run('vim --version');
    my $script = <<'EOT';
sleep 3
zypper -n in vim
EOT
    assert_script_run "cat > /tmp/s.sh <<'END'\n$script\nEND";
    my $sleeper = $testapi::distri->sleep_helper;
    enter_cmd "exit" unless check_screen('desktop', 0);
    assert_and_click 'button', timeout => 60;
}

1;

=head1 Notes

sleep 5;
use base 'x';

=cut
