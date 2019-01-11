// Copyright (C) The Arvados Authors. All rights reserved.
//
// SPDX-License-Identifier: AGPL-3.0

package main

import (
	"bytes"
	"context"
)

// A TestableVolumeManagerFactory creates a volume manager with at least two TestableVolume instances.
// The factory function, and the TestableVolume instances it returns, can use "t" to write
// logs, fail the current test, etc.
type TestableVolumeManagerFactory func(t TB) (*RRVolumeManager, []TestableVolume)

// DoHandlersWithGenericVolumeTests runs a set of handler tests with a
// Volume Manager comprised of TestableVolume instances.
// It calls factory to create a volume manager with TestableVolume
// instances for each test case, to avoid leaking state between tests.
func DoHandlersWithGenericVolumeTests(t TB, factory TestableVolumeManagerFactory) {
	testGetBlock(t, factory, TestHash, TestBlock)
	testGetBlock(t, factory, EmptyHash, EmptyBlock)
	testPutRawBadDataGetBlock(t, factory, TestHash, TestBlock, []byte("baddata"))
	testPutRawBadDataGetBlock(t, factory, EmptyHash, EmptyBlock, []byte("baddata"))
	testPutBlock(t, factory, TestHash, TestBlock)
	testPutBlock(t, factory, EmptyHash, EmptyBlock)
	testPutBlockCorrupt(t, factory, TestHash, TestBlock, []byte("baddata"))
	testPutBlockCorrupt(t, factory, EmptyHash, EmptyBlock, []byte("baddata"))
}

// Setup RRVolumeManager with TestableVolumes
func setupHandlersWithGenericVolumeTest(t TB, factory TestableVolumeManagerFactory) []TestableVolume {
	vm, testableVolumes := factory(t)
	KeepVM = vm

	for _, v := range testableVolumes {
		defer v.Teardown()
	}
	defer KeepVM.Close()

	return testableVolumes
}

// Put a block using PutRaw in just one volume and Get it using GetBlock
func testGetBlock(t TB, factory TestableVolumeManagerFactory, testHash string, testBlock []byte) {
	testableVolumes := setupHandlersWithGenericVolumeTest(t, factory)

	// Put testBlock in one volume
	testableVolumes[1].PutRaw(testHash, testBlock)

	// Get should pass
	buf := make([]byte, len(testBlock))
	n, err := GetBlock(context.Background(), testHash, buf, nil)
	if err != nil {
		t.Fatalf("Error while getting block %s", err)
	}
	if bytes.Compare(buf[:n], testBlock) != 0 {
		t.Errorf("Put succeeded but Get returned %+v, expected %+v", buf[:n], testBlock)
	}
}

// Put a bad block using PutRaw and get it.
func testPutRawBadDataGetBlock(t TB, factory TestableVolumeManagerFactory,
	testHash string, testBlock []byte, badData []byte) {
	testableVolumes := setupHandlersWithGenericVolumeTest(t, factory)

	// Put bad data for testHash in both volumes
	testableVolumes[0].PutRaw(testHash, badData)
	testableVolumes[1].PutRaw(testHash, badData)

	// Get should fail
	buf := make([]byte, BlockSize)
	size, err := GetBlock(context.Background(), testHash, buf, nil)
	if err == nil {
		t.Fatalf("Got %+q, expected error while getting corrupt block %v", buf[:size], testHash)
	}
}

// Invoke PutBlock twice to ensure CompareAndTouch path is tested.
func testPutBlock(t TB, factory TestableVolumeManagerFactory, testHash string, testBlock []byte) {
	setupHandlersWithGenericVolumeTest(t, factory)

	// PutBlock
	if _, err := PutBlock(context.Background(), testBlock, testHash); err != nil {
		t.Fatalf("Error during PutBlock: %s", err)
	}

	// Check that PutBlock succeeds again even after CompareAndTouch
	if _, err := PutBlock(context.Background(), testBlock, testHash); err != nil {
		t.Fatalf("Error during PutBlock: %s", err)
	}

	// Check that PutBlock stored the data as expected
	buf := make([]byte, BlockSize)
	size, err := GetBlock(context.Background(), testHash, buf, nil)
	if err != nil {
		t.Fatalf("Error during GetBlock for %q: %s", testHash, err)
	} else if bytes.Compare(buf[:size], testBlock) != 0 {
		t.Errorf("Get response incorrect. Expected %q; found %q", testBlock, buf[:size])
	}
}

// Put a bad block using PutRaw, overwrite it using PutBlock and get it.
func testPutBlockCorrupt(t TB, factory TestableVolumeManagerFactory,
	testHash string, testBlock []byte, badData []byte) {
	testableVolumes := setupHandlersWithGenericVolumeTest(t, factory)

	// Put bad data for testHash in both volumes
	testableVolumes[0].PutRaw(testHash, badData)
	testableVolumes[1].PutRaw(testHash, badData)

	// Check that PutBlock with good data succeeds
	if _, err := PutBlock(context.Background(), testBlock, testHash); err != nil {
		t.Fatalf("Error during PutBlock for %q: %s", testHash, err)
	}

	// Put succeeded and overwrote the badData in one volume,
	// and Get should return the testBlock now, ignoring the bad data.
	buf := make([]byte, BlockSize)
	size, err := GetBlock(context.Background(), testHash, buf, nil)
	if err != nil {
		t.Fatalf("Error during GetBlock for %q: %s", testHash, err)
	} else if bytes.Compare(buf[:size], testBlock) != 0 {
		t.Errorf("Get response incorrect. Expected %q; found %q", testBlock, buf[:size])
	}
}
