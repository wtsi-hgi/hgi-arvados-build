# Copyright (C) The Arvados Authors. All rights reserved.
#
# SPDX-License-Identifier: Apache-2.0

# Use the "profiled" decorator on a test to get profiling data.
#
# Usage:
#   from performance_profiler import profiled
#
#   # See report in tmp/profile/foobar
#   @profiled
#   def foobar():
#       baz = 1
#
#   See "test_a_sample.py" for a working example.
#
# Performance tests run as part of regular test suite.
# You can also run only the performance tests using one of the following:
#     python -m unittest discover tests.performance
#     ./run-tests.sh WORKSPACE=~/arvados --only sdk/python sdk/python_test="--test-suite=tests.performance"

import functools
import os
import pstats
import sys
import unittest
try:
    import cProfile as profile
except ImportError:
    import profile

output_dir = os.path.abspath(os.path.join('tmp', 'profile'))
if not os.path.exists(output_dir):
    os.makedirs(output_dir)

def profiled(function):
    @functools.wraps(function)
    def profiled_function(*args, **kwargs):
        outfile = open(os.path.join(output_dir, function.__name__), "w")
        caught = None
        pr = profile.Profile()
        pr.enable()
        try:
            return function(*args, **kwargs)
        finally:
            pr.disable()
            ps = pstats.Stats(pr, stream=outfile)
            ps.sort_stats('time').print_stats()
    return profiled_function
