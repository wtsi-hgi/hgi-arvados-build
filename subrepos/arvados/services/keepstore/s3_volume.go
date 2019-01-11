// Copyright (C) The Arvados Authors. All rights reserved.
//
// SPDX-License-Identifier: AGPL-3.0

package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/hex"
	"flag"
	"fmt"
	"io"
	"io/ioutil"
	"net/http"
	"os"
	"regexp"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"git.curoverse.com/arvados.git/sdk/go/arvados"
	"github.com/AdRoll/goamz/aws"
	"github.com/AdRoll/goamz/s3"
)

const (
	s3DefaultReadTimeout    = arvados.Duration(10 * time.Minute)
	s3DefaultConnectTimeout = arvados.Duration(time.Minute)
)

var (
	// ErrS3TrashDisabled is returned by Trash if that operation
	// is impossible with the current config.
	ErrS3TrashDisabled = fmt.Errorf("trash function is disabled because -trash-lifetime=0 and -s3-unsafe-delete=false")

	s3AccessKeyFile string
	s3SecretKeyFile string
	s3RegionName    string
	s3Endpoint      string
	s3Replication   int
	s3UnsafeDelete  bool
	s3RaceWindow    time.Duration

	s3ACL = s3.Private

	zeroTime time.Time
)

const (
	maxClockSkew  = 600 * time.Second
	nearlyRFC1123 = "Mon, 2 Jan 2006 15:04:05 GMT"
)

type s3VolumeAdder struct {
	*Config
}

// String implements flag.Value
func (s *s3VolumeAdder) String() string {
	return "-"
}

func (s *s3VolumeAdder) Set(bucketName string) error {
	if bucketName == "" {
		return fmt.Errorf("no container name given")
	}
	if s3AccessKeyFile == "" || s3SecretKeyFile == "" {
		return fmt.Errorf("-s3-access-key-file and -s3-secret-key-file arguments must given before -s3-bucket-volume")
	}
	if deprecated.flagSerializeIO {
		log.Print("Notice: -serialize is not supported by s3-bucket volumes.")
	}
	s.Config.Volumes = append(s.Config.Volumes, &S3Volume{
		Bucket:        bucketName,
		AccessKeyFile: s3AccessKeyFile,
		SecretKeyFile: s3SecretKeyFile,
		Endpoint:      s3Endpoint,
		Region:        s3RegionName,
		RaceWindow:    arvados.Duration(s3RaceWindow),
		S3Replication: s3Replication,
		UnsafeDelete:  s3UnsafeDelete,
		ReadOnly:      deprecated.flagReadonly,
		IndexPageSize: 1000,
	})
	return nil
}

func s3regions() (okList []string) {
	for r := range aws.Regions {
		okList = append(okList, r)
	}
	return
}

func init() {
	VolumeTypes = append(VolumeTypes, func() VolumeWithExamples { return &S3Volume{} })

	flag.Var(&s3VolumeAdder{theConfig},
		"s3-bucket-volume",
		"Use the given bucket as a storage volume. Can be given multiple times.")
	flag.StringVar(
		&s3RegionName,
		"s3-region",
		"",
		fmt.Sprintf("AWS region used for subsequent -s3-bucket-volume arguments. Allowed values are %+q.", s3regions()))
	flag.StringVar(
		&s3Endpoint,
		"s3-endpoint",
		"",
		"Endpoint URL used for subsequent -s3-bucket-volume arguments. If blank, use the AWS endpoint corresponding to the -s3-region argument. For Google Storage, use \"https://storage.googleapis.com\".")
	flag.StringVar(
		&s3AccessKeyFile,
		"s3-access-key-file",
		"",
		"`File` containing the access key used for subsequent -s3-bucket-volume arguments.")
	flag.StringVar(
		&s3SecretKeyFile,
		"s3-secret-key-file",
		"",
		"`File` containing the secret key used for subsequent -s3-bucket-volume arguments.")
	flag.DurationVar(
		&s3RaceWindow,
		"s3-race-window",
		24*time.Hour,
		"Maximum eventual consistency latency for subsequent -s3-bucket-volume arguments.")
	flag.IntVar(
		&s3Replication,
		"s3-replication",
		2,
		"Replication level reported to clients for subsequent -s3-bucket-volume arguments.")
	flag.BoolVar(
		&s3UnsafeDelete,
		"s3-unsafe-delete",
		false,
		"EXPERIMENTAL. Enable deletion (garbage collection) even when trash lifetime is zero, even though there are known race conditions that can cause data loss.")
}

// S3Volume implements Volume using an S3 bucket.
type S3Volume struct {
	AccessKeyFile      string
	SecretKeyFile      string
	Endpoint           string
	Region             string
	Bucket             string
	LocationConstraint bool
	IndexPageSize      int
	S3Replication      int
	ConnectTimeout     arvados.Duration
	ReadTimeout        arvados.Duration
	RaceWindow         arvados.Duration
	ReadOnly           bool
	UnsafeDelete       bool
	StorageClasses     []string

	bucket *s3bucket

	startOnce sync.Once
}

// Examples implements VolumeWithExamples.
func (*S3Volume) Examples() []Volume {
	return []Volume{
		&S3Volume{
			AccessKeyFile:  "/etc/aws_s3_access_key.txt",
			SecretKeyFile:  "/etc/aws_s3_secret_key.txt",
			Endpoint:       "",
			Region:         "us-east-1",
			Bucket:         "example-bucket-name",
			IndexPageSize:  1000,
			S3Replication:  2,
			RaceWindow:     arvados.Duration(24 * time.Hour),
			ConnectTimeout: arvados.Duration(time.Minute),
			ReadTimeout:    arvados.Duration(5 * time.Minute),
		},
		&S3Volume{
			AccessKeyFile:  "/etc/gce_s3_access_key.txt",
			SecretKeyFile:  "/etc/gce_s3_secret_key.txt",
			Endpoint:       "https://storage.googleapis.com",
			Region:         "",
			Bucket:         "example-bucket-name",
			IndexPageSize:  1000,
			S3Replication:  2,
			RaceWindow:     arvados.Duration(24 * time.Hour),
			ConnectTimeout: arvados.Duration(time.Minute),
			ReadTimeout:    arvados.Duration(5 * time.Minute),
		},
	}
}

// Type implements Volume.
func (*S3Volume) Type() string {
	return "S3"
}

// Start populates private fields and verifies the configuration is
// valid.
func (v *S3Volume) Start() error {
	region, ok := aws.Regions[v.Region]
	if v.Endpoint == "" {
		if !ok {
			return fmt.Errorf("unrecognized region %+q; try specifying -s3-endpoint instead", v.Region)
		}
	} else if ok {
		return fmt.Errorf("refusing to use AWS region name %+q with endpoint %+q; "+
			"specify empty endpoint (\"-s3-endpoint=\") or use a different region name", v.Region, v.Endpoint)
	} else {
		region = aws.Region{
			Name:                 v.Region,
			S3Endpoint:           v.Endpoint,
			S3LocationConstraint: v.LocationConstraint,
		}
	}

	var err error
	var auth aws.Auth
	auth.AccessKey, err = readKeyFromFile(v.AccessKeyFile)
	if err != nil {
		return err
	}
	auth.SecretKey, err = readKeyFromFile(v.SecretKeyFile)
	if err != nil {
		return err
	}

	// Zero timeouts mean "wait forever", which is a bad
	// default. Default to long timeouts instead.
	if v.ConnectTimeout == 0 {
		v.ConnectTimeout = s3DefaultConnectTimeout
	}
	if v.ReadTimeout == 0 {
		v.ReadTimeout = s3DefaultReadTimeout
	}

	client := s3.New(auth, region)
	client.ConnectTimeout = time.Duration(v.ConnectTimeout)
	client.ReadTimeout = time.Duration(v.ReadTimeout)
	v.bucket = &s3bucket{
		Bucket: &s3.Bucket{
			S3:   client,
			Name: v.Bucket,
		},
	}
	return nil
}

// DeviceID returns a globally unique ID for the storage bucket.
func (v *S3Volume) DeviceID() string {
	return "s3://" + v.Endpoint + "/" + v.Bucket
}

func (v *S3Volume) getReaderWithContext(ctx context.Context, loc string) (rdr io.ReadCloser, err error) {
	ready := make(chan bool)
	go func() {
		rdr, err = v.getReader(loc)
		close(ready)
	}()
	select {
	case <-ready:
		return
	case <-ctx.Done():
		theConfig.debugLogf("s3: abandoning getReader(): %s", ctx.Err())
		go func() {
			<-ready
			if err == nil {
				rdr.Close()
			}
		}()
		return nil, ctx.Err()
	}
}

// getReader wraps (Bucket)GetReader.
//
// In situations where (Bucket)GetReader would fail because the block
// disappeared in a Trash race, getReader calls fixRace to recover the
// data, and tries again.
func (v *S3Volume) getReader(loc string) (rdr io.ReadCloser, err error) {
	rdr, err = v.bucket.GetReader(loc)
	err = v.translateError(err)
	if err == nil || !os.IsNotExist(err) {
		return
	}

	_, err = v.bucket.Head("recent/"+loc, nil)
	err = v.translateError(err)
	if err != nil {
		// If we can't read recent/X, there's no point in
		// trying fixRace. Give up.
		return
	}
	if !v.fixRace(loc) {
		err = os.ErrNotExist
		return
	}

	rdr, err = v.bucket.GetReader(loc)
	if err != nil {
		log.Printf("warning: reading %s after successful fixRace: %s", loc, err)
		err = v.translateError(err)
	}
	return
}

// Get a block: copy the block data into buf, and return the number of
// bytes copied.
func (v *S3Volume) Get(ctx context.Context, loc string, buf []byte) (int, error) {
	rdr, err := v.getReaderWithContext(ctx, loc)
	if err != nil {
		return 0, err
	}

	var n int
	ready := make(chan bool)
	go func() {
		defer close(ready)

		defer rdr.Close()
		n, err = io.ReadFull(rdr, buf)

		switch err {
		case nil, io.EOF, io.ErrUnexpectedEOF:
			err = nil
		default:
			err = v.translateError(err)
		}
	}()
	select {
	case <-ctx.Done():
		theConfig.debugLogf("s3: interrupting ReadFull() with Close() because %s", ctx.Err())
		rdr.Close()
		// Must wait for ReadFull to return, to ensure it
		// doesn't write to buf after we return.
		theConfig.debugLogf("s3: waiting for ReadFull() to fail")
		<-ready
		return 0, ctx.Err()
	case <-ready:
		return n, err
	}
}

// Compare the given data with the stored data.
func (v *S3Volume) Compare(ctx context.Context, loc string, expect []byte) error {
	errChan := make(chan error, 1)
	go func() {
		_, err := v.bucket.Head("recent/"+loc, nil)
		errChan <- err
	}()
	var err error
	select {
	case <-ctx.Done():
		return ctx.Err()
	case err = <-errChan:
	}
	if err != nil {
		// Checking for "loc" itself here would interfere with
		// future GET requests.
		//
		// On AWS, if X doesn't exist, a HEAD or GET request
		// for X causes X's non-existence to be cached. Thus,
		// if we test for X, then create X and return a
		// signature to our client, the client might still get
		// 404 from all keepstores when trying to read it.
		//
		// To avoid this, we avoid doing HEAD X or GET X until
		// we know X has been written.
		//
		// Note that X might exist even though recent/X
		// doesn't: for example, the response to HEAD recent/X
		// might itself come from a stale cache. In such
		// cases, we will return a false negative and
		// PutHandler might needlessly create another replica
		// on a different volume. That's not ideal, but it's
		// better than passing the eventually-consistent
		// problem on to our clients.
		return v.translateError(err)
	}
	rdr, err := v.getReaderWithContext(ctx, loc)
	if err != nil {
		return err
	}
	defer rdr.Close()
	return v.translateError(compareReaderWithBuf(ctx, rdr, expect, loc[:32]))
}

// Put writes a block.
func (v *S3Volume) Put(ctx context.Context, loc string, block []byte) error {
	if v.ReadOnly {
		return MethodDisabledError
	}
	var opts s3.Options
	size := len(block)
	if size > 0 {
		md5, err := hex.DecodeString(loc)
		if err != nil {
			return err
		}
		opts.ContentMD5 = base64.StdEncoding.EncodeToString(md5)
	}

	// Send the block data through a pipe, so that (if we need to)
	// we can close the pipe early and abandon our PutReader()
	// goroutine, without worrying about PutReader() accessing our
	// block buffer after we release it.
	bufr, bufw := io.Pipe()
	go func() {
		io.Copy(bufw, bytes.NewReader(block))
		bufw.Close()
	}()

	var err error
	ready := make(chan bool)
	go func() {
		defer func() {
			if ctx.Err() != nil {
				theConfig.debugLogf("%s: abandoned PutReader goroutine finished with err: %s", v, err)
			}
		}()
		defer close(ready)
		err = v.bucket.PutReader(loc, bufr, int64(size), "application/octet-stream", s3ACL, opts)
		if err != nil {
			return
		}
		err = v.bucket.PutReader("recent/"+loc, nil, 0, "application/octet-stream", s3ACL, s3.Options{})
	}()
	select {
	case <-ctx.Done():
		theConfig.debugLogf("%s: taking PutReader's input away: %s", v, ctx.Err())
		// Our pipe might be stuck in Write(), waiting for
		// PutReader() to read. If so, un-stick it. This means
		// PutReader will get corrupt data, but that's OK: the
		// size and MD5 won't match, so the write will fail.
		go io.Copy(ioutil.Discard, bufr)
		// CloseWithError() will return once pending I/O is done.
		bufw.CloseWithError(ctx.Err())
		theConfig.debugLogf("%s: abandoning PutReader goroutine", v)
		return ctx.Err()
	case <-ready:
		// Unblock pipe in case PutReader did not consume it.
		io.Copy(ioutil.Discard, bufr)
		return v.translateError(err)
	}
}

// Touch sets the timestamp for the given locator to the current time.
func (v *S3Volume) Touch(loc string) error {
	if v.ReadOnly {
		return MethodDisabledError
	}
	_, err := v.bucket.Head(loc, nil)
	err = v.translateError(err)
	if os.IsNotExist(err) && v.fixRace(loc) {
		// The data object got trashed in a race, but fixRace
		// rescued it.
	} else if err != nil {
		return err
	}
	err = v.bucket.PutReader("recent/"+loc, nil, 0, "application/octet-stream", s3ACL, s3.Options{})
	return v.translateError(err)
}

// Mtime returns the stored timestamp for the given locator.
func (v *S3Volume) Mtime(loc string) (time.Time, error) {
	_, err := v.bucket.Head(loc, nil)
	if err != nil {
		return zeroTime, v.translateError(err)
	}
	resp, err := v.bucket.Head("recent/"+loc, nil)
	err = v.translateError(err)
	if os.IsNotExist(err) {
		// The data object X exists, but recent/X is missing.
		err = v.bucket.PutReader("recent/"+loc, nil, 0, "application/octet-stream", s3ACL, s3.Options{})
		if err != nil {
			log.Printf("error: creating %q: %s", "recent/"+loc, err)
			return zeroTime, v.translateError(err)
		}
		log.Printf("info: created %q to migrate existing block to new storage scheme", "recent/"+loc)
		resp, err = v.bucket.Head("recent/"+loc, nil)
		if err != nil {
			log.Printf("error: created %q but HEAD failed: %s", "recent/"+loc, err)
			return zeroTime, v.translateError(err)
		}
	} else if err != nil {
		// HEAD recent/X failed for some other reason.
		return zeroTime, err
	}
	return v.lastModified(resp)
}

// IndexTo writes a complete list of locators with the given prefix
// for which Get() can retrieve data.
func (v *S3Volume) IndexTo(prefix string, writer io.Writer) error {
	// Use a merge sort to find matching sets of X and recent/X.
	dataL := s3Lister{
		Bucket:   v.bucket.Bucket,
		Prefix:   prefix,
		PageSize: v.IndexPageSize,
	}
	recentL := s3Lister{
		Bucket:   v.bucket.Bucket,
		Prefix:   "recent/" + prefix,
		PageSize: v.IndexPageSize,
	}
	v.bucket.stats.Tick(&v.bucket.stats.Ops, &v.bucket.stats.ListOps)
	v.bucket.stats.Tick(&v.bucket.stats.Ops, &v.bucket.stats.ListOps)
	for data, recent := dataL.First(), recentL.First(); data != nil; data = dataL.Next() {
		v.bucket.stats.Tick(&v.bucket.stats.Ops, &v.bucket.stats.ListOps)
		if data.Key >= "g" {
			// Conveniently, "recent/*" and "trash/*" are
			// lexically greater than all hex-encoded data
			// hashes, so stopping here avoids iterating
			// over all of them needlessly with dataL.
			break
		}
		if !v.isKeepBlock(data.Key) {
			continue
		}

		// stamp is the list entry we should use to report the
		// last-modified time for this data block: it will be
		// the recent/X entry if one exists, otherwise the
		// entry for the data block itself.
		stamp := data

		// Advance to the corresponding recent/X marker, if any
		for recent != nil {
			if cmp := strings.Compare(recent.Key[7:], data.Key); cmp < 0 {
				recent = recentL.Next()
				v.bucket.stats.Tick(&v.bucket.stats.Ops, &v.bucket.stats.ListOps)
				continue
			} else if cmp == 0 {
				stamp = recent
				recent = recentL.Next()
				v.bucket.stats.Tick(&v.bucket.stats.Ops, &v.bucket.stats.ListOps)
				break
			} else {
				// recent/X marker is missing: we'll
				// use the timestamp on the data
				// object.
				break
			}
		}
		t, err := time.Parse(time.RFC3339, stamp.LastModified)
		if err != nil {
			return err
		}
		fmt.Fprintf(writer, "%s+%d %d\n", data.Key, data.Size, t.UnixNano())
	}
	return nil
}

// Trash a Keep block.
func (v *S3Volume) Trash(loc string) error {
	if v.ReadOnly {
		return MethodDisabledError
	}
	if t, err := v.Mtime(loc); err != nil {
		return err
	} else if time.Since(t) < theConfig.BlobSignatureTTL.Duration() {
		return nil
	}
	if theConfig.TrashLifetime == 0 {
		if !s3UnsafeDelete {
			return ErrS3TrashDisabled
		}
		return v.translateError(v.bucket.Del(loc))
	}
	err := v.checkRaceWindow(loc)
	if err != nil {
		return err
	}
	err = v.safeCopy("trash/"+loc, loc)
	if err != nil {
		return err
	}
	return v.translateError(v.bucket.Del(loc))
}

// checkRaceWindow returns a non-nil error if trash/loc is, or might
// be, in the race window (i.e., it's not safe to trash loc).
func (v *S3Volume) checkRaceWindow(loc string) error {
	resp, err := v.bucket.Head("trash/"+loc, nil)
	err = v.translateError(err)
	if os.IsNotExist(err) {
		// OK, trash/X doesn't exist so we're not in the race
		// window
		return nil
	} else if err != nil {
		// Error looking up trash/X. We don't know whether
		// we're in the race window
		return err
	}
	t, err := v.lastModified(resp)
	if err != nil {
		// Can't parse timestamp
		return err
	}
	safeWindow := t.Add(theConfig.TrashLifetime.Duration()).Sub(time.Now().Add(time.Duration(v.RaceWindow)))
	if safeWindow <= 0 {
		// We can't count on "touch trash/X" to prolong
		// trash/X's lifetime. The new timestamp might not
		// become visible until now+raceWindow, and EmptyTrash
		// is allowed to delete trash/X before then.
		return fmt.Errorf("same block is already in trash, and safe window ended %s ago", -safeWindow)
	}
	// trash/X exists, but it won't be eligible for deletion until
	// after now+raceWindow, so it's safe to overwrite it.
	return nil
}

// safeCopy calls PutCopy, and checks the response to make sure the
// copy succeeded and updated the timestamp on the destination object
// (PutCopy returns 200 OK if the request was received, even if the
// copy failed).
func (v *S3Volume) safeCopy(dst, src string) error {
	resp, err := v.bucket.PutCopy(dst, s3ACL, s3.CopyOptions{
		ContentType:       "application/octet-stream",
		MetadataDirective: "REPLACE",
	}, v.bucket.Name+"/"+src)
	err = v.translateError(err)
	if err != nil {
		return err
	}
	if t, err := time.Parse(time.RFC3339Nano, resp.LastModified); err != nil {
		return fmt.Errorf("PutCopy succeeded but did not return a timestamp: %q: %s", resp.LastModified, err)
	} else if time.Now().Sub(t) > maxClockSkew {
		return fmt.Errorf("PutCopy succeeded but returned an old timestamp: %q: %s", resp.LastModified, t)
	}
	return nil
}

// Get the LastModified header from resp, and parse it as RFC1123 or
// -- if it isn't valid RFC1123 -- as Amazon's variant of RFC1123.
func (v *S3Volume) lastModified(resp *http.Response) (t time.Time, err error) {
	s := resp.Header.Get("Last-Modified")
	t, err = time.Parse(time.RFC1123, s)
	if err != nil && s != "" {
		// AWS example is "Sun, 1 Jan 2006 12:00:00 GMT",
		// which isn't quite "Sun, 01 Jan 2006 12:00:00 GMT"
		// as required by HTTP spec. If it's not a valid HTTP
		// header value, it's probably AWS (or s3test) giving
		// us a nearly-RFC1123 timestamp.
		t, err = time.Parse(nearlyRFC1123, s)
	}
	return
}

// Untrash moves block from trash back into store
func (v *S3Volume) Untrash(loc string) error {
	err := v.safeCopy(loc, "trash/"+loc)
	if err != nil {
		return err
	}
	err = v.bucket.PutReader("recent/"+loc, nil, 0, "application/octet-stream", s3ACL, s3.Options{})
	return v.translateError(err)
}

// Status returns a *VolumeStatus representing the current in-use
// storage capacity and a fake available capacity that doesn't make
// the volume seem full or nearly-full.
func (v *S3Volume) Status() *VolumeStatus {
	return &VolumeStatus{
		DeviceNum: 1,
		BytesFree: BlockSize * 1000,
		BytesUsed: 1,
	}
}

// InternalStats returns bucket I/O and API call counters.
func (v *S3Volume) InternalStats() interface{} {
	return &v.bucket.stats
}

// String implements fmt.Stringer.
func (v *S3Volume) String() string {
	return fmt.Sprintf("s3-bucket:%+q", v.Bucket)
}

// Writable returns false if all future Put, Mtime, and Delete calls
// are expected to fail.
func (v *S3Volume) Writable() bool {
	return !v.ReadOnly
}

// Replication returns the storage redundancy of the underlying
// device. Configured via command line flag.
func (v *S3Volume) Replication() int {
	return v.S3Replication
}

// GetStorageClasses implements Volume
func (v *S3Volume) GetStorageClasses() []string {
	return v.StorageClasses
}

var s3KeepBlockRegexp = regexp.MustCompile(`^[0-9a-f]{32}$`)

func (v *S3Volume) isKeepBlock(s string) bool {
	return s3KeepBlockRegexp.MatchString(s)
}

// fixRace(X) is called when "recent/X" exists but "X" doesn't
// exist. If the timestamps on "recent/"+loc and "trash/"+loc indicate
// there was a race between Put and Trash, fixRace recovers from the
// race by Untrashing the block.
func (v *S3Volume) fixRace(loc string) bool {
	trash, err := v.bucket.Head("trash/"+loc, nil)
	if err != nil {
		if !os.IsNotExist(v.translateError(err)) {
			log.Printf("error: fixRace: HEAD %q: %s", "trash/"+loc, err)
		}
		return false
	}
	trashTime, err := v.lastModified(trash)
	if err != nil {
		log.Printf("error: fixRace: parse %q: %s", trash.Header.Get("Last-Modified"), err)
		return false
	}

	recent, err := v.bucket.Head("recent/"+loc, nil)
	if err != nil {
		log.Printf("error: fixRace: HEAD %q: %s", "recent/"+loc, err)
		return false
	}
	recentTime, err := v.lastModified(recent)
	if err != nil {
		log.Printf("error: fixRace: parse %q: %s", recent.Header.Get("Last-Modified"), err)
		return false
	}

	ageWhenTrashed := trashTime.Sub(recentTime)
	if ageWhenTrashed >= theConfig.BlobSignatureTTL.Duration() {
		// No evidence of a race: block hasn't been written
		// since it became eligible for Trash. No fix needed.
		return false
	}

	log.Printf("notice: fixRace: %q: trashed at %s but touched at %s (age when trashed = %s < %s)", loc, trashTime, recentTime, ageWhenTrashed, theConfig.BlobSignatureTTL)
	log.Printf("notice: fixRace: copying %q to %q to recover from race between Put/Touch and Trash", "recent/"+loc, loc)
	err = v.safeCopy(loc, "trash/"+loc)
	if err != nil {
		log.Printf("error: fixRace: %s", err)
		return false
	}
	return true
}

func (v *S3Volume) translateError(err error) error {
	switch err := err.(type) {
	case *s3.Error:
		if (err.StatusCode == http.StatusNotFound && err.Code == "NoSuchKey") ||
			strings.Contains(err.Error(), "Not Found") {
			return os.ErrNotExist
		}
		// Other 404 errors like NoSuchVersion and
		// NoSuchBucket are different problems which should
		// get called out downstream, so we don't convert them
		// to os.ErrNotExist.
	}
	return err
}

// EmptyTrash looks for trashed blocks that exceeded TrashLifetime
// and deletes them from the volume.
func (v *S3Volume) EmptyTrash() {
	var bytesInTrash, blocksInTrash, bytesDeleted, blocksDeleted int64

	// Define "ready to delete" as "...when EmptyTrash started".
	startT := time.Now()

	emptyOneKey := func(trash *s3.Key) {
		loc := trash.Key[6:]
		if !v.isKeepBlock(loc) {
			return
		}
		atomic.AddInt64(&bytesInTrash, trash.Size)
		atomic.AddInt64(&blocksInTrash, 1)

		trashT, err := time.Parse(time.RFC3339, trash.LastModified)
		if err != nil {
			log.Printf("warning: %s: EmptyTrash: %q: parse %q: %s", v, trash.Key, trash.LastModified, err)
			return
		}
		recent, err := v.bucket.Head("recent/"+loc, nil)
		if err != nil && os.IsNotExist(v.translateError(err)) {
			log.Printf("warning: %s: EmptyTrash: found trash marker %q but no %q (%s); calling Untrash", v, trash.Key, "recent/"+loc, err)
			err = v.Untrash(loc)
			if err != nil {
				log.Printf("error: %s: EmptyTrash: Untrash(%q): %s", v, loc, err)
			}
			return
		} else if err != nil {
			log.Printf("warning: %s: EmptyTrash: HEAD %q: %s", v, "recent/"+loc, err)
			return
		}
		recentT, err := v.lastModified(recent)
		if err != nil {
			log.Printf("warning: %s: EmptyTrash: %q: parse %q: %s", v, "recent/"+loc, recent.Header.Get("Last-Modified"), err)
			return
		}
		if trashT.Sub(recentT) < theConfig.BlobSignatureTTL.Duration() {
			if age := startT.Sub(recentT); age >= theConfig.BlobSignatureTTL.Duration()-time.Duration(v.RaceWindow) {
				// recent/loc is too old to protect
				// loc from being Trashed again during
				// the raceWindow that starts if we
				// delete trash/X now.
				//
				// Note this means (TrashCheckInterval
				// < BlobSignatureTTL - raceWindow) is
				// necessary to avoid starvation.
				log.Printf("notice: %s: EmptyTrash: detected old race for %q, calling fixRace + Touch", v, loc)
				v.fixRace(loc)
				v.Touch(loc)
				return
			}
			_, err := v.bucket.Head(loc, nil)
			if os.IsNotExist(err) {
				log.Printf("notice: %s: EmptyTrash: detected recent race for %q, calling fixRace", v, loc)
				v.fixRace(loc)
				return
			} else if err != nil {
				log.Printf("warning: %s: EmptyTrash: HEAD %q: %s", v, loc, err)
				return
			}
		}
		if startT.Sub(trashT) < theConfig.TrashLifetime.Duration() {
			return
		}
		err = v.bucket.Del(trash.Key)
		if err != nil {
			log.Printf("warning: %s: EmptyTrash: deleting %q: %s", v, trash.Key, err)
			return
		}
		atomic.AddInt64(&bytesDeleted, trash.Size)
		atomic.AddInt64(&blocksDeleted, 1)

		_, err = v.bucket.Head(loc, nil)
		if err == nil {
			log.Printf("warning: %s: EmptyTrash: HEAD %q succeeded immediately after deleting %q", v, loc, loc)
			return
		}
		if !os.IsNotExist(v.translateError(err)) {
			log.Printf("warning: %s: EmptyTrash: HEAD %q: %s", v, loc, err)
			return
		}
		err = v.bucket.Del("recent/" + loc)
		if err != nil {
			log.Printf("warning: %s: EmptyTrash: deleting %q: %s", v, "recent/"+loc, err)
		}
	}

	var wg sync.WaitGroup
	todo := make(chan *s3.Key, theConfig.EmptyTrashWorkers)
	for i := 0; i < 1 || i < theConfig.EmptyTrashWorkers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for key := range todo {
				emptyOneKey(key)
			}
		}()
	}

	trashL := s3Lister{
		Bucket:   v.bucket.Bucket,
		Prefix:   "trash/",
		PageSize: v.IndexPageSize,
	}
	for trash := trashL.First(); trash != nil; trash = trashL.Next() {
		todo <- trash
	}
	close(todo)
	wg.Wait()

	if err := trashL.Error(); err != nil {
		log.Printf("error: %s: EmptyTrash: lister: %s", v, err)
	}
	log.Printf("EmptyTrash stats for %v: Deleted %v bytes in %v blocks. Remaining in trash: %v bytes in %v blocks.", v.String(), bytesDeleted, blocksDeleted, bytesInTrash-bytesDeleted, blocksInTrash-blocksDeleted)
}

type s3Lister struct {
	Bucket     *s3.Bucket
	Prefix     string
	PageSize   int
	nextMarker string
	buf        []s3.Key
	err        error
}

// First fetches the first page and returns the first item. It returns
// nil if the response is the empty set or an error occurs.
func (lister *s3Lister) First() *s3.Key {
	lister.getPage()
	return lister.pop()
}

// Next returns the next item, fetching the next page if necessary. It
// returns nil if the last available item has already been fetched, or
// an error occurs.
func (lister *s3Lister) Next() *s3.Key {
	if len(lister.buf) == 0 && lister.nextMarker != "" {
		lister.getPage()
	}
	return lister.pop()
}

// Return the most recent error encountered by First or Next.
func (lister *s3Lister) Error() error {
	return lister.err
}

func (lister *s3Lister) getPage() {
	resp, err := lister.Bucket.List(lister.Prefix, "", lister.nextMarker, lister.PageSize)
	lister.nextMarker = ""
	if err != nil {
		lister.err = err
		return
	}
	if resp.IsTruncated {
		lister.nextMarker = resp.NextMarker
	}
	lister.buf = make([]s3.Key, 0, len(resp.Contents))
	for _, key := range resp.Contents {
		if !strings.HasPrefix(key.Key, lister.Prefix) {
			log.Printf("warning: s3Lister: S3 Bucket.List(prefix=%q) returned key %q", lister.Prefix, key.Key)
			continue
		}
		lister.buf = append(lister.buf, key)
	}
}

func (lister *s3Lister) pop() (k *s3.Key) {
	if len(lister.buf) > 0 {
		k = &lister.buf[0]
		lister.buf = lister.buf[1:]
	}
	return
}

// s3bucket wraps s3.bucket and counts I/O and API usage stats.
type s3bucket struct {
	*s3.Bucket
	stats s3bucketStats
}

func (b *s3bucket) GetReader(path string) (io.ReadCloser, error) {
	rdr, err := b.Bucket.GetReader(path)
	b.stats.Tick(&b.stats.Ops, &b.stats.GetOps)
	b.stats.TickErr(err)
	return NewCountingReader(rdr, b.stats.TickInBytes), err
}

func (b *s3bucket) Head(path string, headers map[string][]string) (*http.Response, error) {
	resp, err := b.Bucket.Head(path, headers)
	b.stats.Tick(&b.stats.Ops, &b.stats.HeadOps)
	b.stats.TickErr(err)
	return resp, err
}

func (b *s3bucket) PutReader(path string, r io.Reader, length int64, contType string, perm s3.ACL, options s3.Options) error {
	if length == 0 {
		// goamz will only send Content-Length: 0 when reader
		// is nil due to net.http.Request.ContentLength
		// behavior.  Otherwise, Content-Length header is
		// omitted which will cause some S3 services
		// (including AWS and Ceph RadosGW) to fail to create
		// empty objects.
		r = nil
	} else {
		r = NewCountingReader(r, b.stats.TickOutBytes)
	}
	err := b.Bucket.PutReader(path, r, length, contType, perm, options)
	b.stats.Tick(&b.stats.Ops, &b.stats.PutOps)
	b.stats.TickErr(err)
	return err
}

func (b *s3bucket) Del(path string) error {
	err := b.Bucket.Del(path)
	b.stats.Tick(&b.stats.Ops, &b.stats.DelOps)
	b.stats.TickErr(err)
	return err
}

type s3bucketStats struct {
	statsTicker
	Ops     uint64
	GetOps  uint64
	PutOps  uint64
	HeadOps uint64
	DelOps  uint64
	ListOps uint64
}

func (s *s3bucketStats) TickErr(err error) {
	if err == nil {
		return
	}
	errType := fmt.Sprintf("%T", err)
	if err, ok := err.(*s3.Error); ok {
		errType = errType + fmt.Sprintf(" %d %s", err.StatusCode, err.Code)
	}
	s.statsTicker.TickErr(err, errType)
}
