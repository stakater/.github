{{- /*
  Render types in hierarchical order: each container followed by the types it
  contains. Root kinds first in declared order; any leftover types not
  reached by traversal at the end, alphabetical.
*/ -}}

{{- define "renderHierarchy" -}}
{{- $args := . -}}
{{- $type := index $args 0 -}}
{{- $visited := index $args 1 -}}
{{- $typeNames := index $args 2 -}}
{{- $allTypes := index $args 3 -}}
{{- if not (hasKey $visited $type.Name) }}
{{- $_ := set $visited $type.Name true }}

{{ template "type" $type }}
{{- range $type.Members }}
{{- if .Type }}
  {{- $memberType := .Type }}
  {{- if not (hasKey $typeNames $memberType.Name) }}
    {{- if $memberType.UnderlyingType }}{{- $memberType = $memberType.UnderlyingType }}{{- end }}
    {{- if and $memberType $memberType.UnderlyingType }}
      {{- if not (hasKey $typeNames $memberType.Name) }}
        {{- $memberType = $memberType.UnderlyingType }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- if and $memberType (hasKey $typeNames $memberType.Name) }}
    {{- $resolved := index $allTypes $memberType.Name }}
    {{- template "renderHierarchy" (list $resolved $visited $typeNames $allTypes) }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}

{{- define "gvDetails" -}}
{{- $gv := . -}}

## {{ $gv.GroupVersionString }}

{{ $gv.Doc }}

{{- if $gv.Kinds  }}
### Resource Types
{{- range $gv.SortedKinds }}
- {{ $gv.TypeForKind . | markdownRenderTypeLink }}
{{- end }}
{{ end }}

{{- $typeNames := dict -}}
{{- range $gv.SortedTypes -}}
{{- $_ := set $typeNames .Name true -}}
{{- end -}}

{{- $visited := dict -}}

{{ range $gv.SortedKinds }}
{{- template "renderHierarchy" (list ($gv.TypeForKind .) $visited $typeNames $gv.Types) }}
{{- end }}

{{- range $gv.SortedTypes }}
{{- if not (hasKey $visited .Name) }}
{{- template "renderHierarchy" (list . $visited $typeNames $gv.Types) }}
{{- end }}
{{- end }}

{{- end -}}
