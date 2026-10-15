# Hetzner reference installation acceptance — 2026-10-15

## Scope and evidence

This records results reported by the operator during the 13–15 October 2026
Hetzner test session (operator timezone: Asia/Kolkata). The operator executed
the server commands and UI tasks; these are not independently collected SSH
or penetration-test results. Hostnames, addresses, passwords, cron keys and
one-time login/reset links are deliberately omitted.

The reference BOA installation remains pinned to
`e652eec18df0d230677c50b4641f513f22cb61ee`. Later corrections on
`hetzner-drupal11` have CI coverage, but have not yet been exercised by a
fresh installation from the corrected branch. Keep this reference server
available until the clean rerun and replacement restore succeed.

## Results on the reference server

| Check | Result and scope |
| --- | --- |
| OS conversion | Debian 13 converted to Devuan Excalibur; no `/lib/systemd/systemd`; root SSH recovered after reboot. |
| BOA source | Pin validation passed; installed boa, barracuda, octopus and autoinit matched the pinned source. |
| Reviewed standalone verifier | The copy from commit `506f8007370a67f32f6446222cf8e8b8e5984b56` passed SHA256 verification and ran on the reference server with zero failures, zero warnings and exit code 0. Its real Drush 8 JSON probe reported Drupal 11.4.10 while the BOA source pin remained unchanged. |
| Completion | `boa info` reported three Percona lines. |
| Database | Percona 8.4.11-11; Drupal reported a connected MySQL database and successful bootstrap. |
| PHP and Drush | PHP CLI 8.4.26; BOA system Drush 8.5.15. |
| Non-root shell | `o1` could execute `/bin/sh` after the narrow traversal repair; `/opt/local` and `/opt/local/bin` remained `0711 root:root` after reboot. |
| HTTPS | Nginx validation and trusted control-panel HTTPS passed; site HTTP redirected to HTTPS. |
| Drupal operations | Administrator access, published test content, image upload and resized derivative worked. |
| Same-server restore | Full site-files/classic-mysqldump backup and Restore tasks were green. A temporary content edit disappeared after restore; original content and uploaded image remained. |
| Cron | Manual Drupal cron ran. With Drupal Automated Cron set to Never and Aegir set to hourly, Drupal's last-run timestamp advanced. This observation preceded the final platform migration. |
| Anonymous access | Published content was accessible; anonymous administration was denied. |
| Reboot survival | Root SSH, Percona completion count, non-root shell, Drupal bootstrap, published content and site Verify passed after reboot. This reboot preceded SMTP setup and the final platform migration. |
| System email | Authenticated Hostinger submission on TCP/587 delivered the previously queued Octopus report with the configured mailbox as sender. The Postfix queue became empty. |
| Custom platform | Composer 2.10.3 on PHP 8.4.26 built a platform under the account's static tree. Final packages: Drupal core 11.4.10, SMTP 1.4.0 and Drush 13.8.0. |
| Build checks | Composer manifest validation and platform requirements passed; `composer audit --no-dev` reported no security vulnerability advisories after upgrading core. Exact-version constraint warnings were expected. |
| Platform migration | New platform Verify and site Migrate were green. Original content and image remained visible; Drupal's status report showed 11.4.10. |
| Drupal email | SMTP module test email arrived in the operator's inbox from the configured mailbox. The operator subsequently confirmed a password change after the password-reset mail test. |
| Final backup | A full backup after migration, SMTP setup and password reset was green and appeared in the site's Backups tab. A standalone Verify after the final SMTP/password changes was requested but not separately reported. |

## Repairs and guidance corrections

1. The image had an ECDSA SSH key but the BOA preflight required an ed25519 key.
   An ed25519 key was added alongside the existing working key.
2. Public DNS was correct despite Debian's local `127.0.1.1` hosts entry. The
   preflight now queries the DNS NSS service, rather than requiring a hosts-file
   or cloud-init rewrite.
3. The wrapper's private `umask 077` leaked into BOA directory creation and
   blocked instance users from traversing `/opt/local/bin`. The wrapper now
   starts BOA's install child with `umask 022`; the live reference needed the
   targeted `chmod 0711` repair. A clean install must need no such repair.
4. Writing platform control files as `o1` failed against the existing control
   directory ownership/mode. Root installed only the two requested files with
   `o1.ftp:o1` ownership and mode `0644`; directory permissions were preserved.
5. A placeholder Octopus client address needed correction. Real recipient
   addresses must be supplied during the clean install; mailbox credentials
   stay outside this repository.
6. The original verifier incorrectly used the limited-shell `vdrush` wrapper
   from `o1` Bash. A subsequent string-format probe was also rejected by the
   installed Drush. The current verifier requests full Drush 8 JSON status,
   parses `drupal-version` with PHP and checks command success. The operator
   subsequently ran the reviewed standalone verifier against the reference:
   the real JSON probe reported 11.4.10 and the full verifier exited 0 with
   zero failures and warnings. This runtime contract now has both CI and
   actual-server evidence.
7. The new platform initially saved an incomplete `/platforms/.../web` path.
   Correcting the saved Publish Path to the full static-tree path resolved
   Verify. Confirm the saved value before diagnosing permissions or rebuilding.

## Security release encountered during testing

The first Composer build used Drupal 11.4.9 to match the existing demonstration
platform. Its audit identified SA-CORE-2026-014, -015 and -016, including the
critical Field UI remote-code-execution advisory. The new build was updated to
11.4.10 before registration and the site was then migrated onto it.

The [11.4.10 release](https://www.drupal.org/project/drupal/releases/11.4.10)
fixes those advisories. This is a dated result, not a permanent version floor:
check the supported core releases and audit the actual Composer lock before
hosting a site. The install verifier checks version/bootstrap-related stack
facts; it is not a dependency security audit.

## Remaining acceptance gates

- [x] Corrected standalone verifier passed against the reference site without
  changing its BOA source pin; the real JSON version probe reported 11.4.10.
- [ ] Confirm standalone site Verify after the final mail/account changes.
- [ ] Install from a reviewed corrected fork SHA on a separate clean Debian 13
  Hetzner VM with tested rescue access, without manual directory/DNS repairs.
- [ ] Prove BOA source pin retention through manual upgrades and scheduled
  source refresh on that disposable VM; retain negative-test evidence.
- [ ] Prove authenticated Postfix relay configuration survives BOA maintenance
  and a reboot. Delivery before maintenance is not evidence of persistence.
- [ ] Back up/reproduce custom platform code as well as the site archive, and
  restore onto a disposable replacement server. Aegir site Backup excludes the
  shared platform code; same-server Restore does not prove disaster recovery.
- [ ] Review an operator-safe pin promotion/rollback procedure before upgrades
  are used on production systems.

The upstream-control installation on a separate VM and the wider fault-injection
tests remain unperformed. This report establishes a working repaired reference,
not production approval or a successful unattended clean-install rerun.
