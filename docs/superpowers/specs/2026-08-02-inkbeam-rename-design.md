# Historical Inkbeam Rename Design — Superseded

- Date: 2026-08-02
- Status: Superseded on 2026-08-03; do not implement
- Historical source commit: `b0d3622ba62e5d1822f13a29fae8b55ffd46b75a`

This file records that an earlier Inkbeam rename design was reviewed and
committed. Its full text remains available in the Git history at the source
commit above.

The earlier design required `.myshottr` compatibility, dual Native Messaging
hosts, MyShottr inbox migration, old/new app coexistence handling, unsigned ZIP
distribution, and no updater. Those decisions were explicitly rejected before
implementation because Inkbeam has one known user and does not need a legacy
compatibility layer.

Do not use this file as an implementation source. The sole normative design for
the clean Inkbeam cutover and official v0.2.0 release is:

- [`2026-08-03-inkbeam-v0.2.0-official-release-design.md`](./2026-08-03-inkbeam-v0.2.0-official-release-design.md)
