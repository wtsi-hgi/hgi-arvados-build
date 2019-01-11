// Copyright (C) The Arvados Authors. All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0

package arvadostest

import (
	"bufio"
	"bytes"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"os/exec"
	"path"
	"strconv"
	"strings"
)

var authSettings = make(map[string]string)

// ResetEnv resets test env
func ResetEnv() {
	for k, v := range authSettings {
		os.Setenv(k, v)
	}
}

// APIHost returns the address:port of the current test server.
func APIHost() string {
	h := authSettings["ARVADOS_API_HOST"]
	if h == "" {
		log.Fatal("arvadostest.APIHost() was called but authSettings is not populated")
	}
	return h
}

// ParseAuthSettings parses auth settings from given input
func ParseAuthSettings(authScript []byte) {
	scanner := bufio.NewScanner(bytes.NewReader(authScript))
	for scanner.Scan() {
		line := scanner.Text()
		if 0 != strings.Index(line, "export ") {
			log.Printf("Ignoring: %v", line)
			continue
		}
		toks := strings.SplitN(strings.Replace(line, "export ", "", 1), "=", 2)
		if len(toks) == 2 {
			authSettings[toks[0]] = toks[1]
		} else {
			log.Fatalf("Could not parse: %v", line)
		}
	}
	log.Printf("authSettings: %v", authSettings)
}

var pythonTestDir string

func chdirToPythonTests() {
	if pythonTestDir != "" {
		if err := os.Chdir(pythonTestDir); err != nil {
			log.Fatalf("chdir %s: %s", pythonTestDir, err)
		}
		return
	}
	for {
		if err := os.Chdir("sdk/python/tests"); err == nil {
			pythonTestDir, err = os.Getwd()
			if err != nil {
				log.Fatal(err)
			}
			return
		}
		if parent, err := os.Getwd(); err != nil || parent == "/" {
			log.Fatalf("sdk/python/tests/ not found in any ancestor")
		}
		if err := os.Chdir(".."); err != nil {
			log.Fatal(err)
		}
	}
}

// StartAPI starts test API server
func StartAPI() {
	cwd, _ := os.Getwd()
	defer os.Chdir(cwd)
	chdirToPythonTests()

	cmd := exec.Command("python", "run_test_server.py", "start", "--auth", "admin")
	cmd.Stdin = nil
	cmd.Stderr = os.Stderr

	authScript, err := cmd.Output()
	if err != nil {
		log.Fatalf("%+v: %s", cmd.Args, err)
	}
	ParseAuthSettings(authScript)
	ResetEnv()
}

// StopAPI stops test API server
func StopAPI() {
	cwd, _ := os.Getwd()
	defer os.Chdir(cwd)
	chdirToPythonTests()

	cmd := exec.Command("python", "run_test_server.py", "stop")
	bgRun(cmd)
	// Without Wait, "go test" in go1.10.1 tends to hang. https://github.com/golang/go/issues/24050
	cmd.Wait()
}

// StartKeep starts the given number of keep servers,
// optionally with -enforce-permissions enabled.
// Use numKeepServers = 2 and enforcePermissions = false under all normal circumstances.
func StartKeep(numKeepServers int, enforcePermissions bool) {
	cwd, _ := os.Getwd()
	defer os.Chdir(cwd)
	chdirToPythonTests()

	cmdArgs := []string{"run_test_server.py", "start_keep", "--num-keep-servers", strconv.Itoa(numKeepServers)}
	if enforcePermissions {
		cmdArgs = append(cmdArgs, "--keep-enforce-permissions")
	}

	bgRun(exec.Command("python", cmdArgs...))
}

// StopKeep stops keep servers that were started with StartKeep.
// numkeepServers should be the same value that was passed to StartKeep,
// which is 2 under all normal circumstances.
func StopKeep(numKeepServers int) {
	cwd, _ := os.Getwd()
	defer os.Chdir(cwd)
	chdirToPythonTests()

	cmd := exec.Command("python", "run_test_server.py", "stop_keep", "--num-keep-servers", strconv.Itoa(numKeepServers))
	bgRun(cmd)
	// Without Wait, "go test" in go1.10.1 tends to hang. https://github.com/golang/go/issues/24050
	cmd.Wait()
}

// Start cmd, with stderr and stdout redirected to our own
// stderr. Return when the process exits, but do not wait for its
// stderr and stdout to close: any grandchild processes will continue
// writing to our stderr.
func bgRun(cmd *exec.Cmd) {
	cmd.Stdin = nil
	cmd.Stderr = os.Stderr
	cmd.Stdout = os.Stderr
	if err := cmd.Start(); err != nil {
		log.Fatalf("%+v: %s", cmd.Args, err)
	}
	if _, err := cmd.Process.Wait(); err != nil {
		log.Fatalf("%+v: %s", cmd.Args, err)
	}
}

// CreateBadPath creates a tmp dir, appends given string and returns that path
// This will guarantee that the path being returned does not exist
func CreateBadPath() (badpath string, err error) {
	tempdir, err := ioutil.TempDir("", "bad")
	if err != nil {
		return "", fmt.Errorf("Could not create temporary directory for bad path: %v", err)
	}
	badpath = path.Join(tempdir, "bad")
	return badpath, nil
}

// DestroyBadPath deletes the tmp dir created by the previous CreateBadPath call
func DestroyBadPath(badpath string) error {
	tempdir := path.Join(badpath, "..")
	err := os.Remove(tempdir)
	if err != nil {
		return fmt.Errorf("Could not remove bad path temporary directory %v: %v", tempdir, err)
	}
	return nil
}
