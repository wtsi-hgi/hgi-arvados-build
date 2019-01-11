// Copyright (C) The Arvados Authors. All rights reserved.
//
// SPDX-License-Identifier: AGPL-3.0

package main

import (
	"io"
)

func NewCountingWriter(w io.Writer, f func(uint64)) io.WriteCloser {
	return &countingReadWriter{
		writer:  w,
		counter: f,
	}
}

func NewCountingReader(r io.Reader, f func(uint64)) io.ReadCloser {
	return &countingReadWriter{
		reader:  r,
		counter: f,
	}
}

type countingReadWriter struct {
	reader  io.Reader
	writer  io.Writer
	counter func(uint64)
}

func (crw *countingReadWriter) Read(buf []byte) (int, error) {
	n, err := crw.reader.Read(buf)
	crw.counter(uint64(n))
	return n, err
}

func (crw *countingReadWriter) Write(buf []byte) (int, error) {
	n, err := crw.writer.Write(buf)
	crw.counter(uint64(n))
	return n, err
}

func (crw *countingReadWriter) Close() error {
	if c, ok := crw.writer.(io.Closer); ok {
		return c.Close()
	}
	return nil
}
