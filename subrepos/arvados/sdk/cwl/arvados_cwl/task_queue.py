# Copyright (C) The Arvados Authors. All rights reserved.
#
# SPDX-License-Identifier: Apache-2.0

import Queue
import threading
import logging

logger = logging.getLogger('arvados.cwl-runner')

class TaskQueue(object):
    def __init__(self, lock, thread_count):
        self.thread_count = thread_count
        self.task_queue = Queue.Queue()
        self.task_queue_threads = []
        self.lock = lock
        self.in_flight = 0
        self.error = None

        for r in xrange(0, self.thread_count):
            t = threading.Thread(target=self.task_queue_func)
            self.task_queue_threads.append(t)
            t.start()

    def task_queue_func(self):

            while True:
                task = self.task_queue.get()
                if task is None:
                    return
                try:
                    task()
                except Exception as e:
                    logger.exception("Unhandled exception running task")
                    self.error = e

                with self.lock:
                    self.in_flight -= 1

    def add(self, task):
        with self.lock:
            if self.thread_count > 1:
                self.in_flight += 1
                self.task_queue.put(task)
            else:
                task()

    def drain(self):
        try:
            # Drain queue
            while not self.task_queue.empty():
                self.task_queue.get(True, .1)
        except Queue.Empty:
            pass

    def join(self):
        for t in self.task_queue_threads:
            self.task_queue.put(None)
        for t in self.task_queue_threads:
            t.join()
