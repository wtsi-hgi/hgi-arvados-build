// Copyright (C) The Arvados Authors. All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0

package arvados

import "encoding/json"

// ResourceListParams expresses which results are requested in a
// list/index API.
type ResourceListParams struct {
	Select       []string `json:"select,omitempty"`
	Filters      []Filter `json:"filters,omitempty"`
	IncludeTrash bool     `json:"include_trash,omitempty"`
	Limit        *int     `json:"limit,omitempty"`
	Offset       int      `json:"offset,omitempty"`
	Order        string   `json:"order,omitempty"`
	Distinct     bool     `json:"distinct,omitempty"`
	Count        string   `json:"count,omitempty"`
}

// A Filter restricts the set of records returned by a list/index API.
type Filter struct {
	Attr     string
	Operator string
	Operand  interface{}
}

// MarshalJSON encodes a Filter in the form expected by the API.
func (f *Filter) MarshalJSON() ([]byte, error) {
	return json.Marshal([]interface{}{f.Attr, f.Operator, f.Operand})
}
