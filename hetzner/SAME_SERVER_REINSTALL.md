# Clean BOA reinstall on the same Hetzner VPS

## Agreed scope

On 15 October 2026 the operator chose to reuse the current VPS at night because
all other boxes were occupied. The current reference passed the corrected
standalone verifier with zero failures/warnings and reports Drupal 11.4.10.
Its running BOA source remains at the original pin.

The clean trial will use a reviewed corrected fork SHA after a manual rebuild
to Debian 13. Preserve the working reference as recovery material before
overwriting the disk. The scheduled reminder only resumes the guided session;
it does not shut down, rebuild or install anything.

## Before the rebuild

Complete these while the current site and Aegir are still accessible:

1. Confirm the latest site Verify and full site-files/classic-mysqldump Backup
   are green. Take a new full backup if the site changed since the last one.
2. Export/download the actual full site archive to the operator's computer or
   another independent location. Compare checksums after transfer.
3. Preserve the custom Composer platform code, composer.json, composer.lock
   and custom additions off the VPS. Aegir site Backup excludes shared platform
   code; the site archive alone is not the full recovery set.
4. Save a private copy of BOA instance/control settings, the source-pin record
   and Postfix configuration/credential/sender maps. These can contain mailbox
   passwords and database secrets; keep them out of Git and public logs.
5. Record the server identity, assigned IP, DNS, platform/site versions and
   available root SSH key/Console/Rescue access. Retain the working SSH private
   key on the operator's computer.
6. At the agreed night-time outage, shut the OS down gracefully and create a
   Hetzner Snapshot of the completed reference state. Wait for Snapshot
   completion and record its identifier before selecting Rebuild. Hetzner
   recommends a powered-off snapshot for disk consistency. Snapshots exclude
   attached Volumes, so preserve any data on them separately.

Copies stored only under /root or the account's backups directory on this VPS
will be lost in the rebuild. An earlier pre-install Debian snapshot is not a
snapshot of the completed BOA/Drupal/SMTP reference.

## Clean trial

1. Manually rebuild the same VPS with Debian 13 x86-64 using the tested root SSH
   key. Confirm the assigned IP, root SSH and Console/Rescue access afterward.
2. Select a reviewed corrected fork commit whose CI passed. Run the documented
   prepare/install phases on the clean image, with actual host/client values
   and the existing snapshot/rescue confirmation.
3. Exercise conversion/resumption, completion, pin identity, non-root execution,
   reboot and HTTPS. Record any required repair; a repaired run does not meet
   the repair-free clean-install gate.
4. Rebuild/register the Composer platform from the preserved source/lock or
   completed code, then restore/import the saved site with the appropriate BOA
   procedure. Verify content, uploaded files, version, cron and email.
5. Reapply reviewed mail/instance settings and test actual system and Drupal
   delivery. Treat the old configuration as reference; do not blindly overwrite
   the new installation or restore its old source-pin file.
6. Retain the recovery Snapshot and off-server copies until acceptance and
   recovery checks succeed. If the clean trial fails, use that Snapshot to
   recover the reference while the fork defect is corrected.

A same-VPS OS rebuild can exercise recovery onto a fresh installation. It does
not by itself prove recovery on independent hardware or provider storage.

## References

- [Installation steps](README.md)
- [Reference results and remaining gates](ACCEPTANCE_2026-10-15.md)
- [Mail setup](SMTP_587.md)
- [Hetzner Snapshot consistency and recovery](https://docs.hetzner.com/cloud/servers/backups-snapshots/faq/)
- [What Aegir site Backup contains](https://docs.boa.io/using/backups/backup-and-restore)
