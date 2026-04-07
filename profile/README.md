# UiTM Systems

`uitm-systems` is a private-first portfolio of narrow, agent-operable repos for UiTM websites, portals, and supporting provider systems.

The portfolio is designed around one control tower plus many focused child repos:

- `uitm-index` is the portfolio control tower for discovery, routing, and health aggregation
- `uitm-web-map` is the broad UiTM domain and portal discovery layer
- child repos own one system or workflow family well instead of turning the portfolio into a monolith

Most capability repos are private in v1. The portfolio is optimized for safe routing, clear boundaries, and read-first operation before riskier authenticated or mutating flows.

## Current Portfolio

| Repo | Role | Auth Need | Write Risk | Best Use Case |
| --- | --- | --- | --- | --- |
| `uitm-index` | control tower | none | none | find the right repo for a URL or workflow |
| `uitm-web-map` | broad discovery | none | none | map UiTM domains, entrypoints, and login boundaries |
| `uitm-academic-calendar` | public information | none | none | official semester and academic calendar dates |
| `uitm-icress` | public information | none | none | timetable lookup by exact group code |
| `uitm-ecr` | student systems | optional for live tools | prepared-only | academic profile, registered courses, and safe eCR inspection |
| `uitm-ufuture` | student systems | required for live tools | mutation-gated | `myCourses`, notifications, forums, attendance, and course materials |
| `uitm-library-permata` | library and research | optional for authenticated tools | prepared plus gated | library search, fines, renewal discovery, and payment preparation |
| `uitm-bsu` | operations and admin | optional for authenticated tools | prepared-only | booking-system inspection and booking-list summaries |
| `uitm-ezaccess` | library and research | required for live tools | parent-shell only | EzAccess shell mapping, provider discovery, and provider handoff |
| `ezaccess-provider-ebsco-open` | provider-deep repo | none for public tools | none in current build | Open Dissertations search, record detail lookup, and provider-link resolution |

## Which Repo Should You Use First?

- If you only have a UiTM URL or domain:
  start with `uitm-web-map`
- If you know the workflow but not the owner:
  start with `uitm-index`
- If you need official academic dates:
  use `uitm-academic-calendar`
- If you need a timetable by exact group code:
  use `uitm-icress`
- If you need programme, profile, registered-course, or safe eCR work:
  use `uitm-ecr`
- If you need `myCourses`, notifications, forums, attendance, or course materials:
  use `uitm-ufuture`
- If you need library search, fines, renewal discovery, or payment preparation:
  use `uitm-library-permata`
- If you need booking-system inspection or booking lists:
  use `uitm-bsu`
- If you need EzAccess parent-shell discovery or provider handoff:
  use `uitm-ezaccess`
- If you need Open Dissertations provider-deep work:
  use `ezaccess-provider-ebsco-open`

## Safety Model

- `public-read`: safe public reads only
- `authenticated-read`: account-bound inspection only
- `prepared-action`: local or staged action preparation without final execution
- `mutation-gated`: live writes require explicit approval and runtime gates

The portfolio standard favors read-first implementations, explicit runtime gates, repo-local validation, and clear handoff boundaries between sibling repos.
