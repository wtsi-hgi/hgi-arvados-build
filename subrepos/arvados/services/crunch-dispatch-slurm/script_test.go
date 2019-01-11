// Copyright (C) The Arvados Authors. All rights reserved.
//
// SPDX-License-Identifier: AGPL-3.0

package main

import (
	. "gopkg.in/check.v1"
)

var _ = Suite(&ScriptSuite{})

type ScriptSuite struct{}

func (s *ScriptSuite) TestExecScript(c *C) {
	for _, test := range []struct {
		args   []string
		script string
	}{
		{nil, `exec`},
		{[]string{`foo`}, `exec 'foo'`},
		{[]string{`foo`, `bar baz`}, `exec 'foo' 'bar baz'`},
		{[]string{`foo"`, "'waz 'qux\n"}, `exec 'foo"' ''\''waz '\''qux` + "\n" + `'`},
	} {
		c.Logf("%+v -> %+v", test.args, test.script)
		c.Check(execScript(test.args), Equals, "#!/bin/sh\n"+test.script+"\n")
	}
}
