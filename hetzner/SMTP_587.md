# Hetzner Cloud outbound email via authenticated SMTP on TCP/587

**Post-install only.** Hetzner Cloud ordinarily blocks **outbound** ports TCP/25 and TCP/465, but permits TCP/587 for an external SMTP submission provider. BOA's `nodns` option skips BOA's **installation-time** SMTP/DNS checks; it does not deliver mail or create a relay.

## Prerequisites

1. Finish BOA installation and verify Postfix is installed.
2. Choose a mail provider that offers SMTP AUTH + STARTTLS on port 587. Obtain its exact SMTP host, username and secret **privately**.
3. Configure the domain's SPF/DKIM/DMARC as the provider instructs. DNS for BOA (`server.example.com` and `*.server.example.com`) is a separate requirement.
4. Snapshot or back up the existing Postfix configuration first, and keep secrets off GitHub.

## Example Postfix configuration (adapt before use)

As root on the installed Devuan server:

~~~bash
SMTP_HOST=smtp.example.net  # Replace with your provider's actual submission host
cp -a /etc/postfix/main.cf "/root/postfix-main.cf.before-relay.$(date -u +%Y%m%d-%H%M%S)"
postconf -e "relayhost = [${SMTP_HOST}]:587"
postconf -e 'smtp_sasl_auth_enable = yes'
postconf -e 'smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd'
postconf -e 'smtp_sasl_security_options = noanonymous'
postconf -e 'smtp_tls_security_level = encrypt'
postconf -e 'smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt'
~~~

To create the credential file **without putting the password on the command line or in shell history**, use an interactive root shell. This example stores the secret in a protected Postfix hash map; it is *not* encrypted on disk and root must protect it:

~~~bash
umask 077
read -r -p 'SMTP username: ' SMTP_USER
read -r -s -p 'SMTP password / API key: ' SMTP_PASS; echo
printf '[%s]:587 %s:%s\n' "${SMTP_HOST}" "${SMTP_USER}" "${SMTP_PASS}" \
  > /etc/postfix/sasl_passwd
unset SMTP_PASS
chmod 0600 /etc/postfix/sasl_passwd
postmap hash:/etc/postfix/sasl_passwd
chmod 0600 /etc/postfix/sasl_passwd.db
postfix check
service postfix reload
~~~

If the provider has additional TLS certificate-name policies or requires a different SASL mechanism, follow its instructions. STARTTLS **must not be downgraded to cleartext** to make delivery succeed. For strict certificate-name verification, configure an appropriate provider-specific Postfix TLS policy after confirming the supported host/certificate pair.

## Verification

- Confirm TCP/587 reachability with an SMTP/TLS-capable client (an open port alone does **not** establish authentication or message delivery).
- Send one real test email through the local Postfix `sendmail` interface to an inbox you control.
- Verify receipt; inspect the Postfix queue/logs if delivery fails. On Devuan the log file path may vary (`/var/log/mail.log` is common); `mailq` shows pending mail.
- Test a BOA upgrade on a disposable VM and ensure the relay settings persist. If BOA resets them, add a reviewed reapply procedure before production use.

## Credential recovery does not depend on SMTP

When the welcome email never arrives, a successfully installed Octopus instance may retain it at `/data/disk/o1/log/setupmail.txt`. Inspect it **only** in a private root shell; do not copy it into Git, tickets, logs or CI artifacts.

You can also generate an Ægir admin login locally:

~~~bash
su -s /bin/bash o1 -c 'drush @hm uli'
~~~

Treat that one-time URL like a password.

**Security:** Never store SMTP secrets in Git, URLs, Bash arguments, preflight reports or published build artifacts.
