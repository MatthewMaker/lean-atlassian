#!/usr/bin/env bash
#
# PostToolUse hook for the lean-atlassian plugin: catches Jira writes that
# reported success but didn't apply everything they were asked to.
#
# The Atlassian MCP server drops a field it can't place without an error:
# an unknown top-level parameter is ignored, and editJiraIssue ignores a
# bare-string assignee under `fields`. The call still returns the issue, so
# nothing looks wrong. createJiraIssue and editJiraIssue both return the
# issue's default fields, though, and this hook compares them with what was
# requested. When something is missing it adds a note for Claude next to the
# tool result. It never blocks and never grants anything.
#
# Three checks, each reported as one line of the note:
#
#   echo      assignee, components, labels and priority, wherever in the input
#             they were put (top level, `fields`, `additional_fields`, or a
#             misspelled container such as `additionalFields`), must show up
#             in the returned issue.
#   unknown   a top-level parameter the tool doesn't have. The lists below are
#             copied from the tools' schemas; a parameter Atlassian adds later
#             gets a needless note until it's added here, never a block.
#   unchanged an edit of fields the response doesn't echo (custom fields,
#             fixVersions, …) whose issue `updated` time is more than two
#             minutes old: Jira recorded no change at all.
#
# Fails quietly like the other hooks: no jq, an unparseable payload, or a
# response that isn't an issue all emit `{}`.

pass() {
    echo '{}'
    exit 0
}

command -v jq >/dev/null 2>&1 || pass

# shellcheck disable=SC2016  # $names are jq variables, not shell ones
program='
def lc: ascii_downcase;

# The MCP result as Claude Code hands it over: a JSON string, or content
# blocks holding one. Anything else is null.
def parsed:
  if type == "string" then (try fromjson catch null)
  elif type == "array" then
    ([.[] | select(.type? == "text") | .text] | first) as $t
    | if $t then (try ($t | fromjson) catch null) else null end
  elif type == "object" then .
  else null end;

# A Jira timestamp ("2026-11-19T13:12:08.177-0600" or "...Z") as epoch
# seconds, or null.
def epoch:
  ([capture("^(?<dt>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})(\\.[0-9]+)?(?<tz>Z|[+-][0-9]{2}:?[0-9]{2})$")] | first) as $m
  | if $m == null then null
    elif $m.tz == "Z" then ($m.dt + "Z" | fromdateiso8601)
    else
      ($m.tz | gsub(":"; "")) as $z
      | ($m.dt + "Z" | fromdateiso8601)
        - (($z[0:1] + "1" | tonumber) * (($z[1:3] | tonumber) * 3600 + ($z[3:5] | tonumber) * 60))
    end;

# Every value requested for field NAME, from any object it was put in.
def requested($boxes; $name): [$boxes[] | select(has($name)) | .[$name]];

# A name-or-object list ([{"name": "X"}] or ["X"]) as lowercase names.
def names: [(if type == "array" then .[] else . end) | (if type == "object" then .name else . end) | strings | lc];

{
  createJiraIssue: ["additional_fields", "assignToSprint", "assignee", "cloudId", "contentFormat",
    "description", "issueType", "labels", "parent", "priority", "projectKey", "summary"],
  editJiraIssue: ["actionSource", "additional_fields", "cloudId", "contentFormat", "fields",
    "inlineFileCollection", "inlineFileId", "inlineFileName", "issueIdOrKey", "rankAfterIssue",
    "rankBeforeIssue", "rankCustomFieldId", "responseContentFormat"]
} as $known
| ["assignee", "components", "labels", "priority"] as $echoed
| ((.tool_name // "") | [capture("__(?<op>createJiraIssue|editJiraIssue)$").op] | first) as $op
| (.tool_input // {}) as $in
| ((.tool_response | parsed) | (try .issues.nodes[0] catch null)) as $issue
| if $op == null or ($in | type) != "object" or ($issue | type) != "object"
     or ($issue.fields | type) != "object" then {}
  else
    $issue.key as $key
    | $issue.fields as $f
    | ([$in] + [$in[] | objects]) as $boxes

    # echo: requested values that are not on the returned issue.
    | [
        (if $f | has("assignee") then
           requested($boxes; "assignee")[]
           | (if . == null then null
              elif type == "string" then .
              elif type == "object" then (.accountId // .emailAddress // .name // empty)
              else empty end) as $want
           | $f.assignee as $got
           | if $want == null then
               (if $got == null then empty
                else "assignee: asked to clear it, but it is \($got.displayName // $got.accountId)" end)
             elif $got != null and any([$got.accountId, $got.emailAddress, $got.displayName][] | strings; lc == ($want | lc)) then empty
             else "assignee: asked for \($want), but it is \(if $got == null then "unset" else ($got.displayName // $got.accountId) end)" end
         else empty end),
        (if $f | has("components") then
           ([$f.components[]?.name | strings | lc]) as $got
           | ([requested($boxes; "components")[] | names[]] | unique | map(select(. as $n | $got | index($n) | not))) as $miss
           | if $miss == [] then empty else "components: \($miss | join(", ")) missing from the issue" end
         else empty end),
        (if $f | has("labels") then
           ([$f.labels[]? | strings | lc]) as $got
           | ([requested($boxes; "labels")[] | names[]] | unique | map(select(. as $n | $got | index($n) | not))) as $miss
           | if $miss == [] then empty else "labels: \($miss | join(", ")) missing from the issue" end
         else empty end),
        (if $f | has("priority") then
           ($f.priority.name? // "" | lc) as $got
           | requested($boxes; "priority")[] | names[]
           | select(. != $got)
           | "priority: asked for \(.), but it is \($f.priority.name? // "unset")"
         else empty end)
      ] as $echo

    # unknown: top-level parameters the tool does not have.
    | (($in | keys) - $known[$op]) as $unknown
    | (if $unknown == [] then [] else
         ["\($op) has no parameter \($unknown | map("`\(.)`") | join(", ")); the server drops unknown parameters without an error. Fields go inside `additional_fields`."]
       end) as $unk

    # unchanged: an edit of non-echoed fields that left `updated` behind.
    | (if $op == "editJiraIssue" and $echo == [] and $unk == [] then
         ([($in.fields // {}), ($in.additional_fields // {})] | map(objects | keys[]) | unique - $echoed) as $blind
         | ($f.updated | strings | epoch) as $t
         | if $blind != [] and $t != null and (now - $t) > 120 then
             ["no change recorded: \($key) was last updated \($f.updated), so \($blind | join(", ")) did not save. If those fields already held these values, ignore this."]
           else [] end
       else [] end) as $stale

    | ($echo + $unk + $stale) as $problems
    | if $problems == [] then {}
      else {
        hookSpecificOutput: {
          hookEventName: "PostToolUse",
          additionalContext: (
            "lean-atlassian: \($op) reported success for \($key), but Jira did not apply everything requested:\n"
            + ($problems | map("- " + .) | join("\n"))
            + (if $op == "createJiraIssue"
               then "\n\nThe issue exists: fix it with editJiraIssue, and do not create it again."
               else "\n\nRetry the edit with the field placement in references/jira-writes.md (atlassian-mediation skill)." end)
            + (if any($echo[]; startswith("assignee:"))
               then " Under `fields`, assignee takes {\"accountId\": \"…\"}; under `additional_fields`, a bare accountId works."
               else "" end)
          )
        }
      }
    end
  end
'

# -b: native Windows jq.exe writes CRLF otherwise (see approve-listed-operations.sh).
out="$(jq -b -c "$program" 2>/dev/null)" || pass
[[ -n "$out" ]] || pass
printf '%s\n' "$out"
exit 0
