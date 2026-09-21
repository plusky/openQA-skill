# Summary: Python fixture
# Maintainer: QE Team <qe-team@example.com>

import time
from testapi import *


def run(self):
    time.sleep(5)
    if check_var("ARCH", "s390x"):
        assert_script_run('true')
