# CQL Patterns for Confluence

Common CQL query templates for use with `searchConfluenceUsingCql`.

## Basic Search

```cql
-- Pages with keyword in title
title ~ "deployment" AND type = page

-- Full-text search across all content
text ~ "authentication flow" AND type = page

-- Recently modified pages
type = page AND lastModified >= "2024-01-01" ORDER BY lastModified DESC
```

## Scope by Space

```cql
-- All pages in a space
space.key = "ENG" AND type = page ORDER BY title ASC

-- Recently updated in a space
space.key = "ENG" AND type = page AND lastModified >= -7d ORDER BY lastModified DESC

-- Search within multiple spaces
space.key IN ("ENG", "OPS", "PROD") AND text ~ "runbook" AND type = page
```

## Page Hierarchy

```cql
-- Children of a specific page (direct only, by page ID)
parent = 123456789 AND type = page

-- All descendants of a page (entire subtree)
ancestor = 123456789 AND type = page

-- Top-level pages in a space (no parent)
space.key = "ENG" AND type = page AND parent IS NULL
```

## By Author / Contributor

```cql
-- Pages created by current user
creator = currentUser() AND type = page ORDER BY created DESC

-- Pages last modified by current user
contributor = currentUser() AND type = page ORDER BY lastModified DESC
```

## Content Type Filtering

```cql
-- Pages only (exclude blog posts, attachments)
type = page

-- Blog posts only
type = blogpost

-- Pages with attachments
type = page AND attachment IS NOT EMPTY
```

## Labels

```cql
-- Pages with a specific label
type = page AND label = "runbook"

-- Pages with any of several labels
type = page AND label IN ("runbook", "operations", "incident")
```

## Combining Filters

```cql
-- Engineering runbooks, recently updated
space.key = "ENG"
  AND type = page
  AND label = "runbook"
  AND lastModified >= -30d
ORDER BY lastModified DESC

-- Search within a subtree for a keyword
ancestor = 123456789
  AND type = page
  AND text ~ "configuration"
ORDER BY title ASC
```

## Field Reference

Common fields for display:
- `title` — page title
- `space.title` / `space.key` — space name and key
- `creator` — who created the page
- `contributor` — who last edited
- `created` / `lastModified`
- `version` — page version number
- `label` — labels applied to page
- `ancestor` — parent page ID (for subtree scope)
- `parent` — direct parent page ID

## Notes

- `type = page` is almost always the right filter; omitting it returns blog posts and other content types
- `ancestor` searches the full subtree; `parent` searches only direct children
- Text search (`text ~`) is full-text across title + body; `title ~` is title-only and faster
- `limit` defaults to 25; set to 10 for digest use, up to 250 for bulk operations
- Date literals use `"YYYY-MM-DD"` format; relative dates use `-Nd` / `-Nw` / `-NM`
