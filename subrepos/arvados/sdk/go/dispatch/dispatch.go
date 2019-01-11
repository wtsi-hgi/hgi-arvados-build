// Copyright (C) The Arvados Authors. All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0

// Package dispatch is a helper library for building Arvados container
// dispatchers.
package dispatch

import (
	"context"
	"fmt"
	"log"
	"sync"
	"time"

	"git.curoverse.com/arvados.git/sdk/go/arvados"
	"git.curoverse.com/arvados.git/sdk/go/arvadosclient"
)

const (
	Queued    = arvados.ContainerStateQueued
	Locked    = arvados.ContainerStateLocked
	Running   = arvados.ContainerStateRunning
	Complete  = arvados.ContainerStateComplete
	Cancelled = arvados.ContainerStateCancelled
)

// Dispatcher struct
type Dispatcher struct {
	Arv *arvadosclient.ArvadosClient

	// Queue polling frequency
	PollPeriod time.Duration

	// Time to wait between successive attempts to run the same container
	MinRetryPeriod time.Duration

	// Func that implements the container lifecycle. Must be set
	// to a non-nil DispatchFunc before calling Run().
	RunContainer DispatchFunc

	auth     arvados.APIClientAuthorization
	mtx      sync.Mutex
	trackers map[string]*runTracker
	throttle throttle
}

// A DispatchFunc executes a container (if the container record is
// Locked) or resume monitoring an already-running container, and wait
// until that container exits.
//
// While the container runs, the DispatchFunc should listen for
// updated container records on the provided channel. When the channel
// closes, the DispatchFunc should stop the container if it's still
// running, and return.
//
// The DispatchFunc should not return until the container is finished.
type DispatchFunc func(*Dispatcher, arvados.Container, <-chan arvados.Container)

// Run watches the API server's queue for containers that are either
// ready to run and available to lock, or are already locked by this
// dispatcher's token. When a new one appears, Run calls RunContainer
// in a new goroutine.
func (d *Dispatcher) Run(ctx context.Context) error {
	err := d.Arv.Call("GET", "api_client_authorizations", "", "current", nil, &d.auth)
	if err != nil {
		return fmt.Errorf("error getting my token UUID: %v", err)
	}

	d.throttle.hold = d.MinRetryPeriod

	poll := time.NewTicker(d.PollPeriod)
	defer poll.Stop()

	for {
		select {
		case <-poll.C:
			break
		case <-ctx.Done():
			return ctx.Err()
		}

		todo := make(map[string]*runTracker)
		d.mtx.Lock()
		// Make a copy of trackers
		for uuid, tracker := range d.trackers {
			todo[uuid] = tracker
		}
		d.mtx.Unlock()

		// Containers I currently own (Locked/Running)
		querySuccess := d.checkForUpdates([][]interface{}{
			{"locked_by_uuid", "=", d.auth.UUID}}, todo)

		// Containers I should try to dispatch
		querySuccess = d.checkForUpdates([][]interface{}{
			{"state", "=", Queued},
			{"priority", ">", "0"}}, todo) && querySuccess

		if !querySuccess {
			// There was an error in one of the previous queries,
			// we probably didn't get updates for all the
			// containers we should have.  Don't check them
			// individually because it may be expensive.
			continue
		}

		// Containers I know about but didn't fall into the
		// above two categories (probably Complete/Cancelled)
		var missed []string
		for uuid := range todo {
			missed = append(missed, uuid)
		}

		for len(missed) > 0 {
			var batch []string
			if len(missed) > 20 {
				batch = missed[0:20]
				missed = missed[20:]
			} else {
				batch = missed
				missed = missed[0:0]
			}
			querySuccess = d.checkForUpdates([][]interface{}{
				{"uuid", "in", batch}}, todo) && querySuccess
		}

		if !querySuccess {
			// There was an error in one of the previous queries, we probably
			// didn't see all the containers we should have, so don't shut down
			// the missed containers.
			continue
		}

		// Containers that I know about that didn't show up in any
		// query should be let go.
		for uuid, tracker := range todo {
			log.Printf("Container %q not returned by any query, stopping tracking.", uuid)
			tracker.close()
		}

	}
}

// Start a runner in a new goroutine, and send the initial container
// record to its updates channel.
func (d *Dispatcher) start(c arvados.Container) *runTracker {
	tracker := &runTracker{updates: make(chan arvados.Container, 1)}
	tracker.updates <- c
	go func() {
		d.RunContainer(d, c, tracker.updates)
		// RunContainer blocks for the lifetime of the container.  When
		// it returns, the tracker should delete itself.
		d.mtx.Lock()
		delete(d.trackers, c.UUID)
		d.mtx.Unlock()
	}()
	return tracker
}

func (d *Dispatcher) checkForUpdates(filters [][]interface{}, todo map[string]*runTracker) bool {
	params := arvadosclient.Dict{
		"filters": filters,
		"order":   []string{"priority desc"}}

	var list arvados.ContainerList
	for offset, more := 0, true; more; offset += len(list.Items) {
		params["offset"] = offset
		err := d.Arv.List("containers", params, &list)
		if err != nil {
			log.Printf("Error getting list of containers: %q", err)
			return false
		}
		more = len(list.Items) > 0 && list.ItemsAvailable > len(list.Items)+offset
		d.checkListForUpdates(list.Items, todo)
	}
	return true
}

func (d *Dispatcher) checkListForUpdates(containers []arvados.Container, todo map[string]*runTracker) {
	d.mtx.Lock()
	defer d.mtx.Unlock()
	if d.trackers == nil {
		d.trackers = make(map[string]*runTracker)
	}

	for _, c := range containers {
		tracker, alreadyTracking := d.trackers[c.UUID]
		delete(todo, c.UUID)

		if c.LockedByUUID != "" && c.LockedByUUID != d.auth.UUID {
			log.Printf("debug: ignoring %s locked by %s", c.UUID, c.LockedByUUID)
		} else if alreadyTracking {
			switch c.State {
			case Queued:
				tracker.close()
			case Locked, Running:
				tracker.update(c)
			case Cancelled, Complete:
				tracker.close()
			}
		} else {
			switch c.State {
			case Queued:
				if !d.throttle.Check(c.UUID) {
					break
				}
				err := d.lock(c.UUID)
				if err != nil {
					log.Printf("debug: error locking container %s: %s", c.UUID, err)
					break
				}
				c.State = Locked
				d.trackers[c.UUID] = d.start(c)
			case Locked, Running:
				if !d.throttle.Check(c.UUID) {
					break
				}
				d.trackers[c.UUID] = d.start(c)
			case Cancelled, Complete:
				// no-op (we already stopped monitoring)
			}
		}
	}
}

// UpdateState makes an API call to change the state of a container.
func (d *Dispatcher) UpdateState(uuid string, state arvados.ContainerState) error {
	err := d.Arv.Update("containers", uuid,
		arvadosclient.Dict{
			"container": arvadosclient.Dict{"state": state},
		}, nil)
	if err != nil {
		log.Printf("Error updating container %s to state %q: %s", uuid, state, err)
	}
	return err
}

// Lock makes the lock API call which updates the state of a container to Locked.
func (d *Dispatcher) lock(uuid string) error {
	return d.Arv.Call("POST", "containers", uuid, "lock", nil, nil)
}

// Unlock makes the unlock API call which updates the state of a container to Queued.
func (d *Dispatcher) Unlock(uuid string) error {
	return d.Arv.Call("POST", "containers", uuid, "unlock", nil, nil)
}

// TrackContainer ensures a tracker is running for the given UUID,
// regardless of the current state of the container (except: if the
// container is locked by a different dispatcher, a tracker will not
// be started). If the container is not in Locked or Running state,
// the new tracker will close down immediately.
//
// This allows the dispatcher to put its own RunContainer func into a
// cleanup phase (for example, to kill local processes created by a
// prevous dispatch process that are still running even though the
// container state is final) without the risk of having multiple
// goroutines monitoring the same UUID.
func (d *Dispatcher) TrackContainer(uuid string) error {
	var cntr arvados.Container
	err := d.Arv.Call("GET", "containers", uuid, "", nil, &cntr)
	if err != nil {
		return err
	}
	if cntr.LockedByUUID != "" && cntr.LockedByUUID != d.auth.UUID {
		return nil
	}

	d.mtx.Lock()
	defer d.mtx.Unlock()
	if _, alreadyTracking := d.trackers[uuid]; alreadyTracking {
		return nil
	}
	if d.trackers == nil {
		d.trackers = make(map[string]*runTracker)
	}
	d.trackers[uuid] = d.start(cntr)
	switch cntr.State {
	case Queued, Cancelled, Complete:
		d.trackers[uuid].close()
	}
	return nil
}

type runTracker struct {
	closing bool
	updates chan arvados.Container
}

func (tracker *runTracker) close() {
	if !tracker.closing {
		close(tracker.updates)
	}
	tracker.closing = true
}

func (tracker *runTracker) update(c arvados.Container) {
	if tracker.closing {
		return
	}
	select {
	case <-tracker.updates:
		log.Printf("debug: runner is handling updates slowly, discarded previous update for %s", c.UUID)
	default:
	}
	tracker.updates <- c
}
