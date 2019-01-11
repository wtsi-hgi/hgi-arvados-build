# Copyright (C) The Arvados Authors. All rights reserved.
#
# SPDX-License-Identifier: Apache-2.0

class: Workflow
cwlVersion: v1.0
$namespaces:
  arv: "http://arvados.org/cwl#"
inputs:
  count:
    type: int[]
    default: [1, 2, 3, 4]
  script:
    type: File
    default:
      class: File
      location: check_mem.py
outputs:
  out: []
requirements:
  SubworkflowFeatureRequirement: {}
  ScatterFeatureRequirement: {}
  InlineJavascriptRequirement: {}
  StepInputExpressionRequirement: {}
steps:
  substep:
    in:
      count: count
      script: script
    out: []
    hints:
      - class: arv:RunInSingleContainer
      - class: arv:APIRequirement
    scatter: count
    run:
      class: Workflow
      id: mysub
      inputs:
        count: int
        script: File
      outputs: []
      hints:
        - class: ResourceRequirement
          ramMin: $(inputs.count*128)
      steps:
        sleep1:
          in:
            count: count
            script: script
          out: []
          run:
            class: CommandLineTool
            id: subtool
            inputs:
              count:
                type: int
              script: File
            outputs: []
            arguments: [python, $(inputs.script), $(inputs.count * 128)]
